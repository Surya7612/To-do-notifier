import { createRequire } from "module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const {
  companionProjectsPath,
  parseCompanionProjects,
  loadCompanionProjects,
} = require("../../electron/lib/companionProjects.cjs");

/**
 * The companion owns this file and writes it from a sandbox container. Anything
 * this app reads out of it is therefore another process's output, which can be
 * absent, older than the reader, or mid-write — so every shape of bad input has
 * to land on "no projects" rather than on a crash in the todo list.
 */
describe("companionProjects", () => {
  it("reads projects and their task ids", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        version: 1,
        updatedAt: "2026-09-07T22:00:00Z",
        projects: [
          {
            id: "p1",
            name: "Engram",
            todoIDs: ["t1", "t2"],
            savedContextCount: 3,
          },
        ],
      })
    );

    expect(out.projects).toHaveLength(1);
    expect(out.projects[0].name).toBe("Engram");
    expect(out.projects[0].todoIDs).toEqual(["t1", "t2"]);
    expect(out.projects[0].savedContextCount).toBe(3);
    expect(out.updatedAt).toBe("2026-09-07T22:00:00Z");
  });

  it("treats garbage as no projects", () => {
    expect(parseCompanionProjects("not json").projects).toEqual([]);
    expect(parseCompanionProjects("").projects).toEqual([]);
    expect(parseCompanionProjects("null").projects).toEqual([]);
    expect(parseCompanionProjects("[]").projects).toEqual([]);
    expect(parseCompanionProjects('{"projects":"nope"}').projects).toEqual([]);
  });

  it("skips entries with no usable identity", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [
          { id: "", name: "Nameless id" },
          { id: "p2", name: "" },
          { name: "No id at all" },
          null,
          "string",
          { id: "p5", name: "Keeper" },
        ],
      })
    );

    expect(out.projects.map((p) => p.name)).toEqual(["Keeper"]);
  });

  it("defaults a project with no task list to an empty one", () => {
    const out = parseCompanionProjects(
      JSON.stringify({ projects: [{ id: "p1", name: "Engram" }] })
    );
    expect(out.projects[0].todoIDs).toEqual([]);
    expect(out.projects[0].savedContextCount).toBe(0);
  });

  it("drops task ids that could never match a task", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [{ id: "p1", name: "Engram", todoIDs: ["t1", 7, null, "", "t2"] }],
      })
    );
    expect(out.projects[0].todoIDs).toEqual(["t1", "t2"]);
  });

  it("keeps unknown fields from breaking a newer writer", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        version: 99,
        projects: [
          { id: "p1", name: "Engram", colour: "indigo", nested: { a: 1 } },
        ],
      })
    );
    expect(out.projects).toHaveLength(1);
    expect(out.projects[0].name).toBe("Engram");
  });

  it("reports no projects when the companion has never run", () => {
    const out = loadCompanionProjects("/nonexistent/companion-projects.json");
    expect(out.projects).toEqual([]);
    expect(out.requestedTasks).toEqual([]);
    expect(out.updatedAt).toBeNull();
  });

  it("reads the reminders offered as tasks", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [],
        requestedTasks: [
          { id: "r1", title: "Text voice bugs", dueAt: "2026-09-09T10:00:00-04:00" },
        ],
      })
    );

    expect(out.requestedTasks).toHaveLength(1);
    expect(out.requestedTasks[0]).toEqual({
      id: "r1",
      title: "Text voice bugs",
      dueAt: "2026-09-09T10:00:00-04:00",
    });
  });

  it("labels an imported reminder with its project", () => {
    // The companion publishes the id the imported task will have, which is
    // derivable from the reminder's own. That is what lets the existing
    // project labelling work on a task this app has not created yet.
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [{ id: "p1", name: "Engram", todoIDs: ["t1", "companion:r1"] }],
        requestedTasks: [
          { id: "r1", title: "Text voice bugs", dueAt: "2026-09-09T10:00:00Z" },
        ],
      })
    );

    expect(out.projects[0].todoIDs).toContain("companion:r1");
  });

  it("has no requested tasks when an older companion wrote the file", () => {
    // The field was added after the first version, so its absence is ordinary
    // and must not take the projects down with it.
    const out = parseCompanionProjects(
      JSON.stringify({ projects: [{ id: "p1", name: "Engram" }] })
    );

    expect(out.projects).toHaveLength(1);
    expect(out.requestedTasks).toEqual([]);
  });

  it("refuses a request it could not turn into a usable task", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [],
        requestedTasks: [
          { id: "", title: "No id", dueAt: "2026-09-09T10:00:00Z" },
          { id: "r2", title: "   ", dueAt: "2026-09-09T10:00:00Z" },
          { id: "r3", title: "No date" },
          { id: "r4", title: "Unparseable date", dueAt: "next tuesday" },
          { id: "r5", title: "Keeper", dueAt: "2026-09-09T10:00:00Z" },
          null,
        ],
      })
    );

    expect(out.requestedTasks.map((task) => task.title)).toEqual(["Keeper"]);
  });

  it("treats a malformed task list as none, keeping the projects", () => {
    const out = parseCompanionProjects(
      JSON.stringify({
        projects: [{ id: "p1", name: "Engram" }],
        requestedTasks: "nope",
      })
    );

    expect(out.projects).toHaveLength(1);
    expect(out.requestedTasks).toEqual([]);
  });

  it("looks inside the companion's sandbox container", () => {
    const location = companionProjectsPath("/Users/example");
    expect(location).toBe(
      "/Users/example/Library/Containers/surya.TodoCompanion/Data/Library/Application Support/companion-projects.json"
    );
  });
});
