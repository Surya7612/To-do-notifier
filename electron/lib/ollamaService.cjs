/**
 * Local Ollama discovery / boot / probe.
 * @param {{ spawn: Function, fs: typeof import('fs'), path: typeof import('path') }} deps
 */
function createOllamaService({ spawn, fs, path }) {
  let ollamaBootPromise = null;

  async function probeOllama(model) {
    try {
      const tags = await fetch("http://127.0.0.1:11434/api/tags");
      if (!tags.ok) return { ok: false, error: "Ollama not reachable on :11434" };
      const json = await tags.json();
      const models = (json.models ?? []).map((m) => m.name);
      const hasModel = models.some(
        (m) => m === model || m.startsWith(`${model}:`) || m.split(":")[0] === model
      );
      return { ok: true, models, hasModel };
    } catch {
      return {
        ok: false,
        error:
          "Ollama is not running. The app will try to start it automatically.",
      };
    }
  }

  function ollamaBinaryCandidates() {
    const home = process.env.HOME || "";
    return [
      "/opt/homebrew/bin/ollama",
      "/usr/local/bin/ollama",
      path.join(home, ".ollama/bin/ollama"),
      "/Applications/Ollama.app/Contents/Resources/ollama",
      path.join(home, "Applications/Ollama.app/Contents/Resources/ollama"),
      "ollama",
    ];
  }

  function spawnDetachedSafe(command, args) {
    return new Promise((resolve) => {
      try {
        // Prefer absolute paths that exist; skip bare names that will ENOENT in GUI PATH
        if (command.includes(path.sep) && !fs.existsSync(command)) {
          resolve(false);
          return;
        }
        const child = spawn(command, args, {
          detached: true,
          stdio: "ignore",
          env: {
            ...process.env,
            PATH: [
              "/opt/homebrew/bin",
              "/usr/local/bin",
              "/usr/bin",
              "/bin",
              process.env.PATH || "",
            ].join(":"),
          },
        });
        child.once("error", () => resolve(false));
        // If still alive briefly, treat as started
        child.unref();
        resolve(true);
      } catch {
        resolve(false);
      }
    });
  }

  async function ensureOllamaRunning(model) {
    try {
      const first = await probeOllama(model);
      if (first.ok) return first;

      if (!ollamaBootPromise) {
        ollamaBootPromise = (async () => {
          try {
            for (const bin of ollamaBinaryCandidates()) {
              const ok = await spawnDetachedSafe(bin, ["serve"]);
              if (ok) break;
            }
            await spawnDetachedSafe("open", ["-a", "Ollama"]);

            for (let i = 0; i < 16; i++) {
              await new Promise((r) => setTimeout(r, 500));
              const s = await probeOllama(model);
              if (s.ok) return s;
            }
            return {
              ok: false,
              error:
                "Ollama is not running. Open the Ollama app once, or install from https://ollama.com",
            };
          } catch {
            return {
              ok: false,
              error:
                "Ollama is not running. Open the Ollama app once, or install from https://ollama.com",
            };
          }
        })().finally(() => {
          ollamaBootPromise = null;
        });
      }
      return ollamaBootPromise;
    } catch {
      return {
        ok: false,
        error:
          "Ollama is not running. Open the Ollama app once, or install from https://ollama.com",
      };
    }
  }

  return {
    probeOllama,
    ollamaBinaryCandidates,
    spawnDetachedSafe,
    ensureOllamaRunning,
  };
}

module.exports = { createOllamaService };
