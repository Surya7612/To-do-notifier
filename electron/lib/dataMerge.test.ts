import { createRequire } from "module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const {
  mergeTodoStamps,
  mergeAppData,
  inQuietHours,
  validateNotifyPayload,
} = require("../../electron/lib/dataMerge.cjs");
const { validateExternalUrl } = require("../../electron/lib/safeExternal.cjs");

describe("dataMerge", () => {
  it("preserves stamps when dueAt unchanged", () => {
    const prev = [
      { id: "1", dueAt: "2026-01-01T10:00:00.000Z", remindedAt: "x" },
    ];
    const next = [{ id: "1", dueAt: "2026-01-01T10:00:00.000Z", title: "A" }];
    const out = mergeTodoStamps(prev, next);
    expect(out[0].remindedAt).toBe("x");
  });

  it("clears stamps when dueAt changes", () => {
    const prev = [
      {
        id: "1",
        dueAt: "2026-01-01T10:00:00.000Z",
        remindedAt: "x",
        overdueRemindedAt: "y",
      },
    ];
    const next = [{ id: "1", dueAt: "2026-01-02T10:00:00.000Z", title: "A" }];
    const out = mergeTodoStamps(prev, next);
    expect(out[0].remindedAt).toBeUndefined();
    expect(out[0].overdueRemindedAt).toBeUndefined();
  });

  it("merges settings with prev + next over defaults", () => {
    const defaults = { a: 1, b: 2, openaiApiKey: "" };
    const prev = { settings: { a: 9, openaiApiKey: "sk" }, todos: [] };
    const next = { settings: { b: 3 }, todos: [] };
    const out = mergeAppData(defaults, prev, next);
    expect(out.settings.a).toBe(9);
    expect(out.settings.b).toBe(3);
    expect(out.settings.openaiApiKey).toBe("sk");
  });

  it("quiet hours overnight wrap and same start/end", () => {
    const settings = {
      quietHoursEnabled: true,
      quietHoursStart: 22,
      quietHoursEnd: 7,
    };
    expect(inQuietHours(settings, new Date("2026-01-01T23:00:00"))).toBe(true);
    expect(inQuietHours(settings, new Date("2026-01-01T08:00:00"))).toBe(false);
    expect(
      inQuietHours(
        { ...settings, quietHoursStart: 5, quietHoursEnd: 5 },
        new Date("2026-01-01T05:00:00")
      )
    ).toBe(false);
  });

  it("clamps notify payload", () => {
    const v = validateNotifyPayload({
      title: "x".repeat(200),
      body: "y".repeat(1000),
    });
    expect(v.title.length).toBe(120);
    expect(v.body.length).toBe(500);
  });
});

describe("safeExternal", () => {
  it("allows https and blocks file/javascript", () => {
    expect(validateExternalUrl("https://example.com").ok).toBe(true);
    expect(validateExternalUrl("file:///etc/passwd").ok).toBe(false);
    expect(validateExternalUrl("javascript:alert(1)").ok).toBe(false);
    expect(
      validateExternalUrl(
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      ).ok
    ).toBe(true);
  });
});
