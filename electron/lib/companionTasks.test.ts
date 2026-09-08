import { createRequire } from "module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const {
  companionTodoId,
  importCompanionTasks,
  isCompanionTodoId,
  todosToImport,
} = require("../../electron/lib/companionTasks.cjs");

/**
 * This app's half of the reminder hand-over.
 *
 * The companion cannot write `app-data.json`, so it publishes reminders and
 * this creates real tasks from them. Worth testing because the failure is
 * persisted and compounding: an import that is not idempotent adds the same
 * task on every window focus, and one that is too eager brings back a task the
 * user has already dealt with.
 */
describe("importing the companion's reminder requests", () => {
  const request = (id: string, title = "Text voice bugs") => ({
    id,
    title,
    dueAt: "2026-09-09T10:00:00-04:00",
    projectID: null,
  });

  it("creates an open task carrying the user's own words", () => {
    const { todos, created } = importCompanionTasks([], [request("abc")]);

    expect(created).toHaveLength(1);
    expect(todos).toHaveLength(1);
    expect(created[0]).toMatchObject({
      id: "companion:abc",
      title: "Text voice bugs",
      dueAt: "2026-09-09T10:00:00-04:00",
      status: "open",
    });
    expect(created[0].createdAt).toBeTruthy();
  });

  it("does not import the same reminder twice", () => {
    // The whole basis of the contract: this runs on every launch and every
    // focus, and the reminder stays published until it fires.
    const existing = importCompanionTasks([], [request("abc")]).todos;
    const { todos, created } = importCompanionTasks(existing, [request("abc")]);

    expect(created).toHaveLength(0);
    expect(todos).toHaveLength(1);
  });

  it("leaves a completed task completed rather than recreating it", () => {
    // Finishing it here must be the end of it. Re-adding a task the user has
    // ticked off is the failure that would make the feature unusable.
    const done = [
      {
        id: "companion:abc",
        title: "Text voice bugs",
        dueAt: "2026-09-09T10:00:00-04:00",
        status: "done",
        createdAt: "2026-09-08T10:00:00-04:00",
      },
    ];
    const { todos, created } = importCompanionTasks(done, [request("abc")]);

    expect(created).toHaveLength(0);
    expect(todos).toEqual(done);
  });

  it("returns the original array when there is nothing new", () => {
    // The caller skips saving on this, so it decides whether coming back to
    // the window rewrites the file and re-renders the list every time.
    const existing = [{ id: "own-task" }];
    const { todos } = importCompanionTasks(existing, []);

    expect(todos).toBe(existing);
  });

  it("never collides with a task this app created itself", () => {
    const { created } = importCompanionTasks([{ id: "abc" }], [request("abc")]);

    expect(created).toHaveLength(1);
    expect(created[0].id).toBe("companion:abc");
  });

  it("collapses the same reminder appearing twice in one file", () => {
    const { created } = importCompanionTasks([], [request("abc"), request("abc")]);

    expect(created).toHaveLength(1);
  });

  it("skips a request with no usable id", () => {
    const { created } = importCompanionTasks(
      [],
      [{ id: "", title: "x", dueAt: "2026-09-09T10:00:00-04:00" }, null, undefined]
    );

    expect(created).toHaveLength(0);
  });

  it("survives absent todos and absent requests", () => {
    expect(importCompanionTasks(null, null).created).toHaveLength(0);
    expect(todosToImport(undefined, undefined)).toHaveLength(0);
  });

  it("recognises its own ids, and only its own", () => {
    // The reminder sweep skips these, because the companion already scheduled
    // a notification when the user set the reminder. A false negative here
    // announces one thing twice; a false positive silences a task this app
    // created itself.
    expect(companionTodoId("abc")).toBe("companion:abc");
    expect(isCompanionTodoId("companion:abc")).toBe(true);
    expect(isCompanionTodoId("abc")).toBe(false);
    expect(isCompanionTodoId("my-companion:abc")).toBe(false);
    expect(isCompanionTodoId(undefined)).toBe(false);
  });
});
