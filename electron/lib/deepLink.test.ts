import { createRequire } from "module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const { parseDeepLink } = require("./deepLink.cjs");

/**
 * A link is input from outside this app, so most of this pins what must be
 * ignored: the worst a malformed link may do is nothing.
 */

describe("parseDeepLink", () => {
  it("reads a task link, including an id with a prefix and a colon", () => {
    expect(
      parseDeepLink("todonotifier://task?id=companion%3AABC-123")
    ).toEqual({ kind: "task", id: "companion:ABC-123" });
  });

  it("reads a project link", () => {
    expect(parseDeepLink("todonotifier://project?id=P1")).toEqual({
      kind: "project",
      id: "P1",
    });
  });

  it("ignores other schemes, unknown kinds, and missing ids", () => {
    expect(parseDeepLink("https://task?id=1")).toBeNull();
    expect(parseDeepLink("todonotifier://delete?id=1")).toBeNull();
    expect(parseDeepLink("todonotifier://task")).toBeNull();
    expect(parseDeepLink("not a url")).toBeNull();
    expect(parseDeepLink(undefined as unknown as string)).toBeNull();
  });

  it("refuses an absurdly long id rather than passing it to the renderer", () => {
    expect(parseDeepLink(`todonotifier://task?id=${"x".repeat(500)}`)).toBeNull();
  });
});
