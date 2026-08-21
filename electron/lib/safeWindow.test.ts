import { describe, expect, it } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
  isLive,
  safeSend,
  safeGetBounds,
  safeSetBounds,
  safeCall,
} = require("./safeWindow.cjs");

describe("safeWindow", () => {
  it("treats null/destroyed as not live", () => {
    expect(isLive(null)).toBe(false);
    expect(isLive(undefined)).toBe(false);
    expect(isLive({ isDestroyed: () => true })).toBe(false);
    expect(isLive({ isDestroyed: () => false })).toBe(true);
  });

  it("safeSend skips destroyed windows and does not throw", () => {
    expect(safeSend(null, "x", 1)).toBe(false);
    expect(
      safeSend(
        {
          isDestroyed: () => false,
          webContents: { isDestroyed: () => true, send: () => {} },
        },
        "x",
        1
      )
    ).toBe(false);

    const sent: Array<[string, unknown]> = [];
    expect(
      safeSend(
        {
          isDestroyed: () => false,
          webContents: {
            isDestroyed: () => false,
            send: (ch: string, payload: unknown) => sent.push([ch, payload]),
          },
        },
        "pet:action",
        "idle"
      )
    ).toBe(true);
    expect(sent).toEqual([["pet:action", "idle"]]);
  });

  it("safeGetBounds / safeSetBounds / safeCall swallow errors", () => {
    expect(safeGetBounds(null)).toBe(null);
    expect(
      safeGetBounds({
        isDestroyed: () => false,
        getBounds: () => {
          throw new Error("dead");
        },
      })
    ).toBe(null);

    expect(safeSetBounds(null, { x: 0 })).toBe(false);
    expect(
      safeSetBounds(
        {
          isDestroyed: () => false,
          setBounds: () => {
            throw new Error("dead");
          },
        },
        { x: 1, y: 2, width: 3, height: 4 }
      )
    ).toBe(false);

    expect(safeCall(null, "show")).toBe(false);
    expect(
      safeCall(
        {
          isDestroyed: () => false,
          show: () => {
            throw new Error("dead");
          },
        },
        "show"
      )
    ).toBe(false);
  });
});
