import { describe, expect, it } from "vitest";
import {
  isWakePhrase,
  parsePetCommand,
  stripWake,
  wantsDictate,
  wantsStandDown,
  wantsStopDictate,
} from "./voiceParse";

describe("voiceParse", () => {
  it("detects wake phrases", () => {
    expect(isWakePhrase("hey goku")).toBe(true);
    expect(isWakePhrase("hi goku whats up")).toBe(true);
    expect(isWakePhrase("hello there")).toBe(false);
  });

  it("strips wake and leaves intent", () => {
    expect(stripWake("hey goku run")).toBe("run");
    expect(stripWake("hey goku")).toBe("");
  });

  it("does not treat bare tutor as dictate", () => {
    expect(wantsDictate("tutor")).toBe(false);
    expect(wantsDictate("dictate")).toBe(false);
    expect(wantsDictate("tutor mode")).toBe(true);
  });

  it("parses pet commands", () => {
    expect(parsePetCommand("please run now")).toBe("run");
    expect(parsePetCommand("open the app")).toBe("open");
    expect(parsePetCommand("hello friend")).toBe(null);
  });

  it("detects stop dictate", () => {
    expect(wantsStopDictate("stop dictating")).toBe(true);
    expect(wantsStopDictate("that's all")).toBe(true);
    expect(wantsStopDictate("stop")).toBe(false);
  });

  it("detects stand down / stop listening", () => {
    expect(wantsStandDown("stop listening")).toBe(true);
    expect(wantsStandDown("go to sleep")).toBe(true);
    expect(wantsStandDown("never mind")).toBe(true);
    expect(wantsStandDown("stop")).toBe(true);
    expect(wantsStandDown("what is due today")).toBe(false);
  });

  it("does not wake on hey google", () => {
    expect(isWakePhrase("hey google")).toBe(false);
    expect(isWakePhrase("hello goku")).toBe(false);
    expect(isWakePhrase("hey goku")).toBe(true);
  });
});
