import Foundation

/// Opt-in bridge to a local MCP server (stdio JSON-RPC).
///
/// Max never drives the browser. MCP is for *reading* tools the user configured
/// — notes, docs, a problem bank — and the results are labelled as tool output,
/// never as the user's own words. Off by default; a dead command fails soft.
nonisolated enum MCPClient {
    struct ToolNote: Equatable, Sendable {
        let tool: String
        let text: String
    }

    /// Outcome of an opt-in MCP pass. Failures are surfaced so a dead launch
    /// does not look like the toggle doing nothing.
    struct Enrichment: Equatable, Sendable {
        var notes: [ToolNote] = []
        /// One line for the status bar when the server was asked and failed.
        var problem: String? = nil
    }

    /// Runs `tools/list`, then calls up to three tools whose names or
    /// descriptions overlap the question.
    static func enrich(question: String,
                       launch: [String],
                       enabled: Bool) async -> Enrichment {
        guard enabled, launch.count >= 1 else { return Enrichment() }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Enrichment() }

        do {
            let session = try await Session.start(launch: launch)
            defer { session.terminate() }

            try await session.initialize()
            let tools = try await session.listTools()
            guard !tools.isEmpty else {
                return Enrichment(problem: "MCP server listed no tools")
            }

            let chosen = selectTools(tools, for: trimmed, limit: 3)
            guard !chosen.isEmpty else { return Enrichment() }

            var notes: [ToolNote] = []
            for tool in chosen {
                if let text = try await session.callTool(name: tool.name,
                                                         arguments: simpleArguments(for: trimmed)) {
                    let clipped = text.count > 2500 ? String(text.prefix(2500)) + "…" : text
                    notes.append(ToolNote(tool: tool.name, text: clipped))
                }
            }
            return Enrichment(notes: notes)
        } catch {
            NSLog("[MCP] \(error.localizedDescription)")
            return Enrichment(problem: "MCP didn’t respond — answering without tools")
        }
    }

    /// Formats notes for the model prompt.
    static func promptLines(for notes: [ToolNote]) -> [String] {
        notes.map { "- [\($0.tool)] \($0.text)" }
    }

    /// Picks tools whose name/description share tokens with the question.
    static func selectTools(_ tools: [Tool], for question: String, limit: Int) -> [Tool] {
        let tokens = Set(
            question.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 4 }
        )
        guard !tokens.isEmpty else { return Array(tools.prefix(min(1, limit))) }

        let ranked = tools.compactMap { tool -> (Tool, Int)? in
            let hay = (tool.name + " " + (tool.description ?? "")).lowercased()
            let score = tokens.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
            return score > 0 ? (tool, score) : nil
        }
        .sorted { $0.1 > $1.1 }

        if ranked.isEmpty {
            // No lexical hit — still offer the first tool so a single-purpose
            // server (one search tool) is usable without naming it.
            return Array(tools.prefix(min(1, limit)))
        }
        return Array(ranked.prefix(limit).map(\.0))
    }

    static func simpleArguments(for question: String) -> [String: String] {
        ["query": question, "q": question, "text": question, "prompt": question]
    }

    struct Tool: Equatable, Sendable {
        let name: String
        let description: String?
    }

    /// One stdio MCP session.
    final class Session: @unchecked Sendable {
        private let process: Process
        private let stdin: FileHandle
        private let stdout: FileHandle
        private var nextID = 1
        private let lock = NSLock()

        static func start(launch: [String]) async throws -> Session {
            guard let first = launch.first, !first.isEmpty else {
                throw Failure.badLaunch
            }
            let process = Process()
            // `npx` / `uvx` live on PATH — run through env when the binary is
            // not an absolute path, same pattern shell scripts use.
            if first.hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: first)
                process.arguments = Array(launch.dropFirst())
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = launch
            }
            let inPipe = Pipe()
            let outPipe = Pipe()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = Pipe()
            try process.run()
            return Session(process: process,
                           stdin: inPipe.fileHandleForWriting,
                           stdout: outPipe.fileHandleForReading)
        }

        private init(process: Process, stdin: FileHandle, stdout: FileHandle) {
            self.process = process
            self.stdin = stdin
            self.stdout = stdout
        }

        func terminate() {
            if process.isRunning { process.terminate() }
        }

        func initialize() async throws {
            _ = try await request(method: "initialize", params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: String],
                "clientInfo": ["name": "TodoCompanion", "version": "1"] as [String: String],
            ] as [String: Any])
            try notify(method: "notifications/initialized", params: [:] as [String: String])
        }

        func listTools() async throws -> [Tool] {
            let result = try await request(method: "tools/list", params: [:] as [String: String])
            guard let tools = result["tools"] as? [[String: Any]] else { return [] }
            return tools.compactMap { raw in
                guard let name = raw["name"] as? String else { return nil }
                return Tool(name: name, description: raw["description"] as? String)
            }
        }

        func callTool(name: String, arguments: [String: String]) async throws -> String? {
            let result = try await request(method: "tools/call", params: [
                "name": name,
                "arguments": arguments,
            ] as [String: Any])
            return flattenContent(result["content"])
        }

        private func flattenContent(_ raw: Any?) -> String? {
            guard let blocks = raw as? [[String: Any]] else {
                if let text = raw as? String { return text }
                return nil
            }
            let parts = blocks.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                return nil
            }
            let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
            let id: Int = {
                lock.lock()
                defer { lock.unlock() }
                let value = nextID
                nextID += 1
                return value
            }()

            var message: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": method,
            ]
            message["params"] = params
            try write(message)

            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if let line = try readLine() {
                    guard let data = line.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    if let error = json["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "MCP error"
                        throw Failure.remote(message)
                    }
                    if let responseID = json["id"] as? Int, responseID == id,
                       let result = json["result"] as? [String: Any] {
                        return result
                    }
                    // Notifications / other ids — keep reading.
                } else {
                    try await Task.sleep(for: .milliseconds(40))
                }
            }
            throw Failure.timeout
        }

        private func notify(method: String, params: [String: Any]) throws {
            let message: [String: Any] = [
                "jsonrpc": "2.0",
                "method": method,
                "params": params,
            ]
            try write(message)
        }

        private func write(_ message: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: message)
            var payload = data
            payload.append(contentsOf: "\n".utf8)
            try stdin.write(contentsOf: payload)
        }

        private var buffer = Data()

        private func readLine() throws -> String? {
            if let range = buffer.range(of: Data("\n".utf8)) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(data: line, encoding: .utf8)
            }
            let chunk = stdout.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            if let range = buffer.range(of: Data("\n".utf8)) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(data: line, encoding: .utf8)
            }
            return nil
        }
    }

    enum Failure: LocalizedError {
        case badLaunch
        case timeout
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .badLaunch: "MCP launch command is empty."
            case .timeout: "MCP server timed out."
            case let .remote(message): message
            }
        }
    }
}
