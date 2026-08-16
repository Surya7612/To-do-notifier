import { describe, expect, it } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
  asksAboutOpenWork,
  buildCompanionSystemPrompt,
  EMPTY_TODO_REPLY,
} = require("../../electron/lib/companionChat.cjs");

describe("companionChat helpers", () => {
  it("detects todo questions", () => {
    expect(asksAboutOpenWork("what's on my todo list")).toBe(true);
    expect(asksAboutOpenWork("anything due")).toBe(true);
    expect(asksAboutOpenWork("how are you")).toBe(false);
  });

  it("empty-list system prompt forbids inventing work", () => {
    const s = buildCompanionSystemPrompt(0);
    expect(s).toMatch(/EMPTY/i);
    expect(EMPTY_TODO_REPLY).toMatch(/nothing/i);
  });
});
