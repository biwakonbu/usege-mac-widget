import assert from "node:assert/strict";
import test from "node:test";
import { PROVIDER_RULES, isUsageUrl } from "./provider-rules.mjs";

test("canonical usage URL with query/hash is accepted", () => {
  assert.equal(
    isUsageUrl("codex", "https://chatgpt.com/codex/settings/usage?tab=billing#section"),
    true
  );
});

test("same domain but non-usage path is rejected", () => {
  assert.equal(isUsageUrl("codex", "https://chatgpt.com/pricing"), false);
});

test("provider host/path definition exists and is strict", () => {
  assert.equal(isUsageUrl("zai", PROVIDER_RULES.zai.sourceUrl), true);
  assert.equal(isUsageUrl("zai", "https://example.com/manage-apikey/subscription"), false);
});
