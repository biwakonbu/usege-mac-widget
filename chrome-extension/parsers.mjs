const AUTH_KEYWORDS = /(log in|login|sign in|authentication|reauthenticate|ログイン|サインイン)/i;

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

function findMoneyCandidates(text) {
  const regex = /[+-]?\s*(?:USD|US\$|\$)\s*[+-]?[0-9][0-9,]*(?:\.[0-9]+)?/g;
  const candidates = [];

  let match;
  while ((match = regex.exec(text)) !== null) {
    const raw = match[0];
    const amount = parseSignedMoneyToken(raw);
    if (amount === null) {
      continue;
    }

    const start = Math.max(0, match.index - 60);
    const end = Math.min(text.length, match.index + raw.length + 60);
    const context = text.slice(start, end).toLowerCase();

    candidates.push({ amount, raw, context });
  }

  return candidates;
}

function scoreCostCandidate(candidate) {
  let score = 0;
  if (/(total|spent|spend|cost|usage|this month|current)/i.test(candidate.context)) score += 3;
  if (/(today|daily|24h|change|delta|increase|decrease)/i.test(candidate.context)) score -= 2;
  if (candidate.raw.includes("+") || candidate.raw.includes("-")) score -= 2;
  if (candidate.amount >= 0) score += 1;
  return score;
}

function scoreDeltaCandidate(candidate) {
  let score = 0;
  if (/(today|daily|24h|change|delta)/i.test(candidate.context)) score += 3;
  if (/(total|this month|current|overall)/i.test(candidate.context)) score -= 1;
  if (candidate.raw.includes("+") || candidate.raw.includes("-")) score += 3;
  return score;
}

function pickBest(candidates, scorer) {
  if (!candidates.length) return null;
  return candidates
    .map((candidate) => ({ candidate, score: scorer(candidate) }))
    .sort((a, b) => b.score - a.score)[0].candidate;
}

function extractLimitPercent(text, key) {
  const patterns = [
    new RegExp(`${key}[^\\n\\r0-9%]{0,24}(\\d+(?:\\.\\d+)?)\\s*%`, "i"),
    new RegExp(`(\\d+(?:\\.\\d+)?)\\s*%[^\\n\\r]{0,24}${key}`, "i")
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;

    const value = Number.parseFloat(match[1]);
    if (!Number.isNaN(value)) {
      return value;
    }
  }

  return null;
}

function toPlainText(input) {
  return (input || "").replace(/\s+/g, " ").trim();
}

export function parseUsageFromText(provider, inputText) {
  const text = toPlainText(inputText);

  if (!text || text.length < 24) {
    return {
      ok: false,
      error_code: "AUTH_REQUIRED",
      error_message: "ページ本文が取得できません。ログイン状態を確認してください。"
    };
  }

  const moneyCandidates = findMoneyCandidates(text);

  if (!moneyCandidates.length && AUTH_KEYWORDS.test(text)) {
    return {
      ok: false,
      error_code: "AUTH_REQUIRED",
      error_message: "ログインが必要です。対象サービスの使用量ページを開いてください。"
    };
  }

  const costCandidate = pickBest(moneyCandidates, scoreCostCandidate);
  const deltaCandidate = pickBest(moneyCandidates, scoreDeltaCandidate);

  if (!costCandidate) {
    return {
      ok: false,
      error_code: "PARSER_BROKEN",
      error_message: "コスト情報を抽出できませんでした。DOM変更の可能性があります。"
    };
  }

  const rateLimit5h = extractLimitPercent(text, "5h");
  const rateLimit1w = extractLimitPercent(text, "1w") ?? extractLimitPercent(text, "7d");

  return {
    ok: true,
    metrics: {
      cost_usd: costCandidate.amount,
      delta_day_usd: deltaCandidate ? deltaCandidate.amount : 0,
      rate_limit_5h: rateLimit5h,
      rate_limit_1w: rateLimit1w
    },
    parser_version: `${provider}.v1`
  };
}
