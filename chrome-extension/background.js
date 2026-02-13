import { parseUsageFromText } from "./parsers.mjs";

const HOST_NAME = "com.usege.sync.host";
const ALARM_NAME = "usege-sync-5m";

const PROVIDERS = {
  codex: {
    sourceUrl: "https://chatgpt.com/codex/settings/usage",
    tabPatterns: ["https://chatgpt.com/*"]
  },
  claude: {
    sourceUrl: "https://claude.ai/*",
    tabPatterns: ["https://claude.ai/*"]
  },
  cursor: {
    sourceUrl: "https://cursor.com/*",
    tabPatterns: ["https://cursor.com/*"]
  },
  gemini: {
    sourceUrl: "https://aistudio.google.com/*",
    tabPatterns: ["https://aistudio.google.com/*", "https://console.cloud.google.com/*"]
  },
  zai: {
    sourceUrl: "https://z.ai/manage-apikey/subscription",
    tabPatterns: ["https://z.ai/*"]
  }
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sendNativeMessage(payload) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, payload, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
        return;
      }
      resolve(response);
    });
  });
}

async function sendNativeWithRetry(payload, maxAttempts = 3) {
  let attempt = 0;
  let delay = 500;
  while (attempt < maxAttempts) {
    try {
      return await sendNativeMessage(payload);
    } catch (error) {
      attempt += 1;
      if (attempt >= maxAttempts) {
        throw error;
      }
      await sleep(delay);
      delay *= 2;
    }
  }
}

async function readTabText(tabId) {
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId },
    func: () => ({
      text: document.body ? document.body.innerText : "",
      url: location.href,
      title: document.title
    })
  });
  return result;
}

async function pickProviderTab(providerName) {
  const provider = PROVIDERS[providerName];
  if (!provider) {
    return null;
  }

  const tabs = await chrome.tabs.query({
    url: provider.tabPatterns
  });

  if (!tabs.length) {
    return null;
  }

  return tabs.find((tab) => tab.active) || tabs[0];
}

function buildSyncError(provider, code, message, sourceUrl) {
  return {
    v: 1,
    type: "sync_error",
    provider,
    captured_at: new Date().toISOString(),
    source_url: sourceUrl,
    error_code: code,
    error_message: message
  };
}

async function syncOneProvider(providerName) {
  const provider = PROVIDERS[providerName];
  const tab = await pickProviderTab(providerName);

  if (!tab || !tab.id) {
    const payload = buildSyncError(
      providerName,
      "AUTH_REQUIRED",
      `${providerName} の使用量ページを開いた状態で再実行してください。`,
      provider.sourceUrl
    );
    await sendNativeWithRetry(payload);
    return;
  }

  let capture;
  try {
    capture = await readTabText(tab.id);
  } catch (error) {
    const payload = buildSyncError(
      providerName,
      "AUTH_REQUIRED",
      `タブへのアクセスに失敗しました: ${error.message}`,
      provider.sourceUrl
    );
    await sendNativeWithRetry(payload);
    return;
  }

  const parsed = parseUsageFromText(providerName, capture.text || "");

  if (!parsed.ok) {
    const payload = buildSyncError(
      providerName,
      parsed.error_code || "PARSER_BROKEN",
      parsed.error_message || "Parser failed",
      capture.url || provider.sourceUrl
    );
    await sendNativeWithRetry(payload);
    return;
  }

  const payload = {
    v: 1,
    type: "usage_snapshot",
    provider: providerName,
    captured_at: new Date().toISOString(),
    source_url: capture.url || provider.sourceUrl,
    metrics: parsed.metrics,
    parser_version: parsed.parser_version
  };

  await sendNativeWithRetry(payload);
}

async function runSyncCycle(trigger) {
  for (const providerName of Object.keys(PROVIDERS)) {
    try {
      await syncOneProvider(providerName);
    } catch (error) {
      console.error(`[usege] ${trigger} sync failed (${providerName}):`, error);
      const payload = buildSyncError(
        providerName,
        "HOST_UNAVAILABLE",
        `Native host unavailable: ${error.message}`,
        PROVIDERS[providerName].sourceUrl
      );

      try {
        await sendNativeWithRetry(payload, 1);
      } catch {
        // Native host unavailable; no further fallback channel.
      }
    }
  }
}

async function ensureAlarm() {
  await chrome.alarms.create(ALARM_NAME, {
    periodInMinutes: 5
  });
}

chrome.runtime.onInstalled.addListener(async () => {
  await ensureAlarm();
  await runSyncCycle("install");
});

chrome.runtime.onStartup.addListener(async () => {
  await ensureAlarm();
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== ALARM_NAME) {
    return;
  }
  await runSyncCycle("alarm");
});

chrome.action.onClicked.addListener(async () => {
  await runSyncCycle("manual");
});
