import { createRequire } from "module";
import { afterEach, describe, expect, it, vi } from "vitest";

const require = createRequire(import.meta.url);
const { watchCompanionProjects } = require("./companionProjects.cjs");

/**
 * The watch is what makes a reminder set in Max appear here in under a second
 * rather than on the next 30-second tick. A fake `fs.watch` stands in, because
 * real file events arrive with platform-dependent timing and batching.
 */
function fakeWatch() {
  let listener: ((event: string, name: string | null) => void) | null = null;
  let closed = false;
  const watch = (_dir: string, cb: typeof listener) => {
    listener = cb;
    return { close: () => (closed = true), on: () => {} };
  };
  return {
    watch,
    emit: (name: string | null) => listener?.("rename", name),
    get closed() {
      return closed;
    },
  };
}

describe("watchCompanionProjects", () => {
  afterEach(() => vi.useRealTimers());

  it("runs once for the burst of events one publish produces", () => {
    vi.useFakeTimers();
    const fake = fakeWatch();
    const onChange = vi.fn();
    watchCompanionProjects(onChange, {
      filePath: "/x/companion-projects.json",
      watch: fake.watch,
    });

    fake.emit("companion-projects.json");
    fake.emit("companion-projects.json");
    fake.emit(null);
    vi.advanceTimersByTime(400);

    expect(onChange).toHaveBeenCalledTimes(1);
  });

  it("ignores other files in the same container folder", () => {
    vi.useFakeTimers();
    const fake = fakeWatch();
    const onChange = vi.fn();
    watchCompanionProjects(onChange, {
      filePath: "/x/companion-projects.json",
      watch: fake.watch,
    });

    fake.emit("default.store-wal");
    vi.advanceTimersByTime(400);

    expect(onChange).not.toHaveBeenCalled();
  });

  it("treats a folder that does not exist as no watch, not a crash", () => {
    const stop = watchCompanionProjects(() => {}, {
      filePath: "/definitely/not/here/companion-projects.json",
    });
    expect(() => stop()).not.toThrow();
  });

  it("stops cleanly, including a change still pending", () => {
    vi.useFakeTimers();
    const fake = fakeWatch();
    const onChange = vi.fn();
    const stop = watchCompanionProjects(onChange, {
      filePath: "/x/companion-projects.json",
      watch: fake.watch,
    });

    fake.emit("companion-projects.json");
    stop();
    vi.advanceTimersByTime(400);

    expect(fake.closed).toBe(true);
    expect(onChange).not.toHaveBeenCalled();
  });
});
