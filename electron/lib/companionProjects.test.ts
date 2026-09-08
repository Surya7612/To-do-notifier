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
    expect(out.updatedAt).toBeNull();
  });

  it("looks inside the companion's sandbox container", () => {
    const location = companionProjectsPath("/Users/example");
    expect(location).toBe(
      "/Users/example/Library/Containers/surya.TodoCompanion/Data/Library/Application Support/companion-projects.json"
    );
  });
});
