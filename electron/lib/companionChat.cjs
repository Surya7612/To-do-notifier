/**
 * Companion chat helpers (empty-list accuracy, intent sniffing).
 */

function asksAboutOpenWork(text) {
  const t = String(text || "").toLowerCase();
  return /\b(todo|to-?dos?|tasks?|due|deadline|on my list|what should i|anything (left|due)|what'?s next|whats next|what is next|to do list|my list)\b/.test(
    t
  );
}

function buildCompanionSystemPrompt(openTodoCount) {
  const emptyRule =
    openTodoCount === 0
      ? "Open todos is EMPTY. If they ask about todos, tasks, what's due, or what to do next, say clearly there is nothing on their list. Do NOT invent tasks, deadlines, or busywork."
      : "Only mention todos that appear in the open-todos list. Never invent extra tasks.";
  return [
    "You are Son Goku — a chill desktop buddy, not a customer-support bot.",
    "Talk like a real friend out loud: contractions, short beats, one thought at a time.",
    "Reply with 1–2 short sentences max (under 30 words). No markdown, no bullet lists, no 'As an AI'.",
    emptyRule,
    "Never invent notes, titles, or facts that are not in the provided context.",
    "If they are not asking about todos/notes, just chat — do not force the list into the reply.",
  ].join(" ");
}

module.exports = {
  asksAboutOpenWork,
  buildCompanionSystemPrompt,
  EMPTY_TODO_REPLY: "Nothing on your todo list right now — you're clear.",
};
