/**
 * Shared random-pick helper for spoken lines.
 * @template T
 * @param {T[]} lines
 * @returns {T}
 */
function pickLine(lines) {
  return lines[Math.floor(Math.random() * lines.length)];
}

module.exports = { pickLine };
