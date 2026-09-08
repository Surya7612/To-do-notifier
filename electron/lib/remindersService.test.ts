import { describe, expect, it } from "vitest";

// @ts-expect-error CommonJS module without types
import { createRemindersService } from "./remindersService.cjs";
// @ts-expect-error CommonJS module without types
import { companionTodoId } from "./companionTasks.cjs";

/**
 * Who announces a task, when two apps can see it.
 *
 * A task imported from a companion reminder is announced by the companion,
 * which scheduled a notification the moment the user set it. This app is where
 * that task gets worked, not where it gets announced — nagging here too would
 * mean two alerts for one thing asked about once, and the user would have no
 * way of telling which app to go and switch off.
 */
describe("the reminder sweep", () => {
  const overdue = new Date(Date.now() - 60 * 60_000).toISOString();

  function sweep(todos: unknown[]) {
    const announced: string[] = [];
    const data = {
      settings: { reminderLeadMinutes: 60, overdueNagMinutes: 30, momTone: "gentle" },
      todos,
    };
    const service = createRemindersService({
      loadData: () => data,
      saveData: () => undefined,
      notify: (title: string) => {
        announced.push(title);
        return true;
      },
      broadcast: () => undefined,
      speakPet: () => undefined,
      rebuildTrayMenu: () => undefined,
      inQuietHours: () => false,
      getFocusSessionActive: () => false,
    });
    service.checkReminders();
    return announced;
  }

  it("announces an ordinary overdue task", () => {
    expect(sweep([{ id: "mine", title: "Write it up", dueAt: overdue, status: "open" }])).toEqual([
      "Overdue",
    ]);
  });

  it("leaves a task imported from a companion reminder to the companion", () => {
    const imported = [
      { id: companionTodoId("abc"), title: "revisit the code", dueAt: overdue, status: "open" },
    ];

    expect(sweep(imported)).toEqual([]);
  });

  it("still announces the rest of the list", () => {
    // The skip must be per task. Bailing out of the sweep on meeting one would
    // silence every task after it, which is invisible until something is missed.
    const mixed = [
      { id: companionTodoId("abc"), title: "revisit the code", dueAt: overdue, status: "open" },
      { id: "mine", title: "Write it up", dueAt: overdue, status: "open" },
    ];

    expect(sweep(mixed)).toEqual(["Overdue"]);
  });
});
