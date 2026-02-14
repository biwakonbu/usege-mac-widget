const SHARED_COST_KEYWORDS = [
  "total",
  "spent",
  "spend",
  "cost",
  "usage",
  "this month",
  "current cost",
  "current usage",
  "subscription"
];

const SHARED_DELTA_KEYWORDS = [
  "today",
  "daily",
  "24h",
  "delta",
  "change",
  "increase",
  "decrease",
  "today's",
  "today usage",
  "本日",
  "今日",
  "24時間",
  "増減",
  "変化"
];

export const PROVIDER_RULES = {
  codex: {
    sourceUrl: "https://chatgpt.com/codex/settings/usage",
    tabPatterns: ["https://chatgpt.com/*"],
    costKeywords: ["total spend", "spent this month", ...SHARED_COST_KEYWORDS],
    deltaKeywords: ["today change", ...SHARED_DELTA_KEYWORDS],
    limit5hKeywords: ["5h", "5 hour", "5-hour", "5時間", "5 時間"],
    limit1wKeywords: ["1w", "7d", "7 day", "7-day", "week", "1週間", "1 週間", "週"]
  },
  claude: {
    sourceUrl: "https://claude.ai/settings/billing",
    tabPatterns: ["https://claude.ai/*"],
    costKeywords: ["billing", "monthly spend", ...SHARED_COST_KEYWORDS],
    deltaKeywords: SHARED_DELTA_KEYWORDS,
    limit5hKeywords: ["5h"],
    limit1wKeywords: ["1w", "7d"]
  },
  cursor: {
    sourceUrl: "https://cursor.com/settings/billing",
    tabPatterns: ["https://cursor.com/*"],
    costKeywords: ["billing", "team spend", ...SHARED_COST_KEYWORDS],
    deltaKeywords: SHARED_DELTA_KEYWORDS,
    limit5hKeywords: ["5h"],
    limit1wKeywords: ["1w", "7d"]
  },
  gemini: {
    sourceUrl: "https://aistudio.google.com/app/settings/plan",
    tabPatterns: ["https://aistudio.google.com/*", "https://console.cloud.google.com/*"],
    costKeywords: ["plan", "billing", ...SHARED_COST_KEYWORDS],
    deltaKeywords: SHARED_DELTA_KEYWORDS,
    limit5hKeywords: ["5h"],
    limit1wKeywords: ["1w", "7d"]
  },
  zai: {
    sourceUrl: "https://z.ai/manage-apikey/subscription",
    tabPatterns: ["https://z.ai/*"],
    costKeywords: ["current cost", "subscription usage", ...SHARED_COST_KEYWORDS],
    deltaKeywords: ["24h delta", ...SHARED_DELTA_KEYWORDS],
    limit5hKeywords: ["5h"],
    limit1wKeywords: ["1w", "7d"]
  }
};

function normalizePath(pathname) {
  const normalized = (pathname || "/").replace(/\/+$/, "");
  return normalized || "/";
}

export function getProviderRule(provider) {
  return PROVIDER_RULES[provider] || null;
}

export function isUsageUrl(provider, rawUrl) {
  const rule = getProviderRule(provider);
  if (!rule || !rawUrl) {
    return false;
  }

  try {
    const current = new URL(rawUrl);
    const canonical = new URL(rule.sourceUrl);
    return current.hostname.toLowerCase() === canonical.hostname.toLowerCase()
      && normalizePath(current.pathname) === normalizePath(canonical.pathname);
  } catch {
    return false;
  }
}
