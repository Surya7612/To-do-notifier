/**
 * Pure data-merge helpers for app persistence (testable).
 */

/**
 * Merge reminder stamps; clear stamps when dueAt changes so reschedules re-notify.
 * @param {Array} prevTodos
 * @param {Array} nextTodos
 */
function mergeTodoStamps(prevTodos, nextTodos) {
  const prevById = new Map((prevTodos || []).map((t) => [t.id, t]));
  return (nextTodos || []).map((t) => {
    const old = prevById.get(t.id);
    if (!old) return t;
    const dueChanged = String(t.dueAt || "") !== String(old.dueAt || "");
    if (dueChanged) {
      return {
        ...t,
        remindedAt: undefined,
        overdueRemindedAt: undefined,
      };
    }
    return {
      ...t,
      remindedAt: t.remindedAt || old.remindedAt,
      overdueRemindedAt: t.overdueRemindedAt || old.overdueRemindedAt,
    };
  });
}

/**
 * @param {object} defaults
 * @param {object} prev
 * @param {object} next
 */
function mergeAppData(defaults, prev, next) {
  const settings = {
    ...defaults,
    ...(prev.settings || {}),
    ...(next.settings || {}),
  };
  return {
    todos: mergeTodoStamps(prev.todos, next.todos ?? prev.todos ?? []),
    notes: next.notes ?? prev.notes ?? [],
    flashcards: next.flashcards ?? prev.flashcards ?? [],
    training: next.training ?? prev.training ?? [],
    settings,
    streak: next.streak ?? prev.streak ?? 0,
    longestStreak: next.longestStreak ?? prev.longestStreak ?? 0,
    lastActiveDate:
      next.lastActiveDate !== undefined
        ? next.lastActiveDate
        : prev.lastActiveDate,
    dayPlan: next.dayPlan !== undefined ? next.dayPlan : prev.dayPlan,
    lastRecapDate:
      next.lastRecapDate !== undefined ? next.lastRecapDate : prev.lastRecapDate,
  };
}

/**
 * @param {object} settings
 * @param {Date} [now]
 */
function inQuietHours(settings, now = new Date()) {
  if (!settings || !settings.quietHoursEnabled) return false;
  const hour = now.getHours();
  const start = settings.quietHoursStart ?? 22;
  const end = settings.quietHoursEnd ?? 7;
  if (start === end) return false;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}

/**
 * @param {unknown} payload
 */
function validateNotifyPayload(payload) {
  const title = String(payload?.title || "To-Do Notifier").slice(0, 120);
  const body = String(payload?.body || "").slice(0, 500);
  return { title, body };
}

/**
 * @param {unknown} text
 * @param {number} max
 */
function clampText(text, max = 400) {
  return String(text || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

module.exports = {
  mergeTodoStamps,
  mergeAppData,
  inQuietHours,
  validateNotifyPayload,
  clampText,
};
