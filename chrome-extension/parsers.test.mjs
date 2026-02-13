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

test("codex parser extracts cost, delta and limits", async () => {
  const text = await fixture("codex-success.txt");
  const parsed = parseUsageFromText("codex", text);

  assert.equal(parsed.ok, true);
  assert.equal(parsed.metrics.cost_usd, 42.5);
  assert.equal(parsed.metrics.delta_day_usd, 3.2);
  assert.equal(parsed.metrics.rate_limit_5h, 31);
  assert.equal(parsed.metrics.rate_limit_1w, 58);
  assert.equal(parsed.parser_version, "codex.v1");
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
  assert.equal(parsed.metrics.cost_usd, 18.9);
  assert.equal(parsed.metrics.delta_day_usd, 1.1);
  assert.equal(parsed.metrics.rate_limit_5h, null);
  assert.equal(parsed.metrics.rate_limit_1w, null);
});
