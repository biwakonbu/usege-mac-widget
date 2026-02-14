import { getProviderRule } from "./provider-rules.mjs";

const AUTH_KEYWORDS = /(log in|login|sign in|authentication|reauthenticate|ログイン|サインイン)/i;
const MONEY_REGEX = /[+-]?\s*(?:USD|US\$|\$)\s*[+-]?[0-9][0-9,]*(?:\.[0-9]+)?|[+-]?[0-9][0-9,]*(?:\.[0-9]+)?\s*(?:USD|US\$|\$)/gi;
const PERCENT_REGEX = /(\d+(?:\.\d+)?)\s*%/g;

function normalizeNumber(value) {
  return Number.parseFloat(value.replace(/,/g, ""));
}

function parseSignedMoneyToken(token) {
  const compact = token.replace(/\s+/g, "");
  const numberMatch = compact.match(/([0-9][0-9,]*(?:\.[0-9]+)?)/);
  if (!numberMatch) return null;

  const base = normalizeNumber(numberMatch[1]);
  if (Number.isNaN(base)) return null;

  const sign = compact.includes("-") ? -1 : 1;
  return sign * base;
}

function toLines(input) {
  return (input || "")
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter((line) => line.length > 0);
}

function includesAnyKeyword(line, keywords) {
  const lower = line.toLowerCase();
  return keywords.some((keyword) => lower.includes(keyword.toLowerCase()));
}

function extractMoneyTokens(line) {
  const candidates = [];
  const matches = line.match(MONEY_REGEX) || [];

  for (const raw of matches) {
    const amount = parseSignedMoneyToken(raw);
    if (amount === null) {
      continue;
    }

    candidates.push({
      amount,
      signed: /[+-]/.test(raw),
      raw
    });
  }

  return candidates;
}

function pickMetricMoney(lines, keywords, options = {}) {
  const allowNegative = options.allowNegative ?? true;
  const preferSigned = options.preferSigned ?? false;
  const candidates = [];

  for (let index = 0; index < lines.length; index += 1) {
    if (!includesAnyKeyword(lines[index], keywords)) {
      continue;
    }

    const contexts = [{ text: lines[index], distance: 0 }];
    if (index + 1 < lines.length) {
      contexts.push({ text: lines[index + 1], distance: 1 });
    }

    for (const context of contexts) {
      for (const token of extractMoneyTokens(context.text)) {
        if (!allowNegative && token.amount < 0) {
          continue;
        }
        candidates.push({
          amount: token.amount,
          signed: token.signed,
          distance: context.distance
        });
      }
    }
  }

  if (!candidates.length) {
    return null;
  }

  const signedCandidates = preferSigned
    ? candidates.filter((candidate) => candidate.signed)
    : candidates;
  const effective = signedCandidates.length ? signedCandidates : candidates;

  return effective
    .map((candidate) => {
      let score = 0;
      score -= candidate.distance * 3;
      score += candidate.signed ? (preferSigned ? 4 : -1) : (preferSigned ? 0 : 2);
      score += candidate.amount >= 0 ? 1 : 0;
      return { candidate, score };
    })
    .sort((a, b) => b.score - a.score)[0].candidate.amount;
}

function pickLimitPercent(lines, keywords) {
  for (let index = 0; index < lines.length; index += 1) {
    if (!includesAnyKeyword(lines[index], keywords)) {
      continue;
    }

    const contexts = [lines[index]];
    if (index + 1 < lines.length) {
      contexts.push(lines[index + 1]);
    }

    for (const context of contexts) {
      const ratioMatch = context.match(/(\d+(?:\.\d+)?)\s*\/\s*100/i);
      if (ratioMatch) {
        const ratioValue = Number.parseFloat(ratioMatch[1]);
        if (!Number.isNaN(ratioValue)) {
          return ratioValue;
        }
      }

      const percentMatch = context.match(PERCENT_REGEX);
      if (percentMatch && percentMatch.length) {
        const first = Number.parseFloat(percentMatch[0].replace("%", "").trim());
        if (!Number.isNaN(first)) {
          return first;
        }
      }

      let scrubbed = context;
      for (const keyword of keywords) {
        scrubbed = scrubbed.replace(new RegExp(escapeRegex(keyword), "ig"), " ");
      }

      const plainNumberMatches = [...scrubbed.matchAll(/(\d+(?:\.\d+)?)/g)];
      const plainCandidates = plainNumberMatches
        .map((match) => Number.parseFloat(match[1]))
        .filter((value) => !Number.isNaN(value) && value >= 0 && value <= 100);

      if (plainCandidates.length) {
        return plainCandidates[plainCandidates.length - 1];
      }
    }
  }

  return null;
}

function toPlainText(input) {
  return (input || "").replace(/\s+/g, " ").trim();
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function authRequired(message) {
  return {
    ok: false,
    error_code: "AUTH_REQUIRED",
    error_message: message
  };
}

function parserBroken(message) {
  return {
    ok: false,
    error_code: "PARSER_BROKEN",
    error_message: message
  };
}

export function parseUsageFromText(provider, inputText) {
  const rule = getProviderRule(provider);
  if (!rule) {
    return parserBroken(`Unknown provider: ${provider}`);
  }

  const text = toPlainText(inputText);
  const lines = toLines(inputText);

  if (!text || text.length < 24 || !lines.length) {
    return authRequired("ページ本文が取得できません。ログイン状態を確認してください。");
  }

  if (AUTH_KEYWORDS.test(text)) {
    return authRequired("ログインが必要です。対象サービスの使用量ページを開いてください。");
  }

  const delta = pickMetricMoney(lines, rule.deltaKeywords, {
    allowNegative: true,
    preferSigned: true
  });
  const normalizedDelta = delta ?? 0;

  const rateLimit5h = pickLimitPercent(lines, rule.limit5hKeywords);
  const rateLimit1w = pickLimitPercent(lines, rule.limit1wKeywords);

  if (rateLimit5h !== null && (rateLimit5h < 0 || rateLimit5h > 100)) {
    return parserBroken("5h 制限値の抽出結果が不正です。");
  }
  if (rateLimit1w !== null && (rateLimit1w < 0 || rateLimit1w > 100)) {
    return parserBroken("1w 制限値の抽出結果が不正です。");
  }

  return {
    ok: true,
    metrics: {
      // Cost collection is intentionally disabled.
      cost_usd: 0,
      delta_day_usd: normalizedDelta,
      rate_limit_5h: rateLimit5h,
      rate_limit_1w: rateLimit1w
    },
    parser_version: `${provider}.v4`
  };
}
