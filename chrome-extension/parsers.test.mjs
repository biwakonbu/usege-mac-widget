import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseUsageFromText } from "./parsers.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function fixture(name) {
  return fs.readFile(path.join(__dirname, "fixtures", name), "utf8");
}

test("codex parser extracts delta and limits while cost is disabled", async () => {
  const text = await fixture("codex-success.txt");
  const parsed = parseUsageFromText("codex", text);

  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 0);
  assert.equal(parsed.metrics.delta_day_usd, 3.2);
  assert.equal(parsed.metrics.rate_limit_5h, 31);
  assert.equal(parsed.metrics.rate_limit_1w, 58);
  assert.equal(parsed.parser_version, "codex.v4");
});

test("auth required text returns AUTH_REQUIRED", async () => {
  const text = await fixture("no-auth.txt");
  const parsed = parseUsageFromText("claude", text);

  assert.equal(parsed.ok, false);
  assert.equal(parsed.error_code, "AUTH_REQUIRED");
});

test("z.ai parser extracts without limits", async () => {
  const text = await fixture("zai-success.txt");
  const parsed = parseUsageFromText("zai", text);

  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 0);
  assert.equal(parsed.metrics.delta_day_usd, 1.1);
  assert.equal(parsed.metrics.rate_limit_5h, null);
  assert.equal(parsed.metrics.rate_limit_1w, null);
  assert.equal(parsed.parser_version, "zai.v4");
});

test("parser prefers labeled usage metrics over noise money values", () => {
  const text = `
  Header
  Promo credit: $999.99
  Codex usage
  Total spend this month: $42.50
  Random data USD 11.11
  Today change: -$3.20
  5h window used 31%
  1w window used 58%
  `;

  const parsed = parseUsageFromText("codex", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 0);
  assert.equal(parsed.metrics.delta_day_usd, -3.2);
});

test("delta only page still succeeds even without cost line", () => {
  const text = `
  Codex usage
  Today change: +$1.25
  5h window used 31%
  `;

  const parsed = parseUsageFromText("codex", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 0);
  assert.equal(parsed.metrics.delta_day_usd, 1.25);
});

test("limit ratio notation is parsed", () => {
  const text = `
  Codex usage
  Today change: +$1.25
  5h window used 44.4/100
  1w window used 55.5/100
  `;

  const parsed = parseUsageFromText("codex", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.rate_limit_5h, 44.4);
  assert.equal(parsed.metrics.rate_limit_1w, 55.5);
});

test("japanese limit labels without percent are parsed", () => {
  const text = `
  Codex usage
  Today change: +$1.25
  5時間ウィンドウ 44.4
  1週間ウィンドウ 55.5
  `;

  const parsed = parseUsageFromText("codex", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.rate_limit_5h, 44.4);
  assert.equal(parsed.metrics.rate_limit_1w, 55.5);
});

test("missing delta is treated as 0", () => {
  const text = `
  Codex usage
  Total spend this month: $42.50
  5h window used 31%
  `;

  const parsed = parseUsageFromText("codex", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.delta_day_usd, 0);
  assert.equal(parsed.metrics.cost_usd, 0);
});

test("delta not found falls back to 0 even on noisy content", () => {
  const text = `
  Dashboard
  Promo credit $100.00
  Last invoice USD 50.00
  `;

  const parsed = parseUsageFromText("claude", text);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 0);
  assert.equal(parsed.metrics.delta_day_usd, 0);
});
