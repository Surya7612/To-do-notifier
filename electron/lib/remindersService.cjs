const { pickLine } = require("./random.cjs");

/**
 * Due-soon / overdue reminder sweep and its "mom voice" copy.
 */
function createRemindersService({
  loadData,
  saveData,
  notify,
  broadcast,
  speakPet,
  rebuildTrayMenu,
  inQuietHours,
  getFocusSessionActive,
}) {
  function momLine(todo, kind, tone) {
    const title = todo.title;
    if (kind === "upcoming") {
      if (tone === "strict") return `Focus. "${title}" is due soon. No excuses.`;
      if (tone === "gentle")
        return `Hey love — "${title}" is coming up. You've got this.`;
      return `Oi! "${title}" is almost due. Power up and finish it!`;
    }
    if (tone === "strict") return `"${title}" is overdue. Handle it now.`;
    if (tone === "gentle")
      return `"${title}" slipped past due. Want to knock it out together?`;
    return `Still waiting on "${title}"! Even Goku trains on schedule.`;
  }

  function inQuietHoursLocal(settings) {
    return inQuietHours(settings, new Date());
  }

  function checkReminders() {
    const data = loadData();
    if (inQuietHoursLocal(data.settings)) return;

    const softBlock =
      getFocusSessionActive() && data.settings.softBlockDuringFocus === true;
    const now = Date.now();
    const leadMs = (data.settings.reminderLeadMinutes || 60) * 60_000;
    const nagMs = (data.settings.overdueNagMinutes || 30) * 60_000;
    let changed = false;

    for (const todo of data.todos) {
      if (todo.status === "done") continue;
      const due = new Date(todo.dueAt).getTime();
      if (Number.isNaN(due)) continue;

      // Soft-block only suppresses *upcoming* nags — overdue still fires
      if (due > now && due - now <= leadMs) {
        if (!todo.remindedAt && !softBlock) {
          const ok = notify(
            "Due soon",
            momLine(todo, "upcoming", data.settings.momTone)
          );
          if (ok) {
            todo.remindedAt = new Date().toISOString();
            changed = true;
            broadcast("pet:action", "scold");
            speakPet(pickLine(["Heads up!", "Due soon!", "Don't flake!"]));
          }
        }
      }

      if (due <= now) {
        const last = todo.overdueRemindedAt
          ? new Date(todo.overdueRemindedAt).getTime()
          : 0;
        // First overdue fire: allow sooner (2 min) so due-time ping isn't "wait 30m"
        const interval = last ? nagMs : Math.min(nagMs, 2 * 60_000);
        if (now - last >= interval) {
          const ok = notify(
            "Overdue",
            momLine(todo, "overdue", data.settings.momTone)
          );
          if (ok) {
            todo.overdueRemindedAt = new Date().toISOString();
            changed = true;
            broadcast("pet:action", "scold");
            speakPet(pickLine(["Still waiting!", "Overdue!", "Get on it!"]));
          }
        }
      }
    }

    if (changed) {
      saveData(data);
      broadcast("data:changed", data);
      rebuildTrayMenu();
    }
  }

  return { momLine, checkReminders };
}

module.exports = { createRemindersService };
