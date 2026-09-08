/**
 * Turning the companion's reminder requests into tasks this app owns.
 *
 * The companion cannot create a task. `app-data.json` belongs to this process,
 * which holds it in memory and rewrites it whole, so a second writer would
 * eventually lose an edit or truncate the file. Instead the companion publishes
 * what it would like — the same "propose, don't write" rule it applies to the
 * files it edits — and this decides what to make of it.
 *
 * The point of importing rather than merely displaying: a task created here is
 * genuinely this app's, so it can be completed, rescheduled and notified like
 * any other. A mirrored list would have looked the same and done none of that.
 *
 * Pure, so the interesting part — not importing the same reminder twice — is
 * testable without a disk or a running companion.
 */

/**
 * Marks a task as having come from the companion.
 *
 * A prefix rather than a flag on the object, because the id is the only field
 * that survives everything: the user can rename a task, complete it, or change
 * its date, and it must still be recognised as one already imported.
 */
const COMPANION_TODO_PREFIX = "companion:";

/**
 * @param {string} requestId The companion's own reminder identifier.
 */
function companionTodoId(requestId) {
  return `${COMPANION_TODO_PREFIX}${requestId}`;
}

/**
 * @param {unknown} id
 */
function isCompanionTodoId(id) {
  return typeof id === "string" && id.startsWith(COMPANION_TODO_PREFIX);
}

/**
 * The tasks that would be new, given what is already here.
 *
 * Idempotency rests entirely on the id, which is why the companion's
 * identifier has to be stable: this runs at startup and on a timer, and a
 * reminder stays in the published list for a while after it fires. Note that an
 * already-imported task counts whether it is open or done — a task completed
 * here must not come back the next time this runs.
 *
 * @param {Array<{id: string, title: string, dueAt: string}>} requestedTasks
 * @param {Array<{id?: string}>} existingTodos
 * @param {Date} [now] When the task is recorded as having been created.
 */
function todosToImport(requestedTasks, existingTodos, now = new Date()) {
  const alreadyHere = new Set(
    (existingTodos || []).map((todo) => todo && todo.id).filter((id) => typeof id === "string")
  );

  const created = [];
  for (const request of requestedTasks || []) {
    if (!request || typeof request.id !== "string" || request.id === "") continue;

    const id = companionTodoId(request.id);
    if (alreadyHere.has(id)) continue;
    // Guards against the same reminder appearing twice in one file, which
    // would otherwise produce two tasks sharing an id.
    alreadyHere.add(id);

    created.push({
      id,
      title: request.title,
      dueAt: request.dueAt,
      status: "open",
      createdAt: now.toISOString(),
    });
  }

  return created;
}

/**
 * Adds whatever is new, and reports what it added.
 *
 * Returns the original array untouched when there is nothing to do, so the
 * caller can skip saving. That matters more than it looks: this runs every
 * thirty seconds, and writing unconditionally would rewrite the file — and
 * re-render the task list — on every tick.
 *
 * @param {Array} todos
 * @param {Array} requestedTasks
 * @param {Date} [now]
 */
function importCompanionTasks(todos, requestedTasks, now = new Date()) {
  const existing = todos || [];
  const created = todosToImport(requestedTasks, existing, now);

  return {
    todos: created.length === 0 ? existing : [...existing, ...created],
    created,
  };
}

module.exports = {
  companionTodoId,
  isCompanionTodoId,
  importCompanionTasks,
};
