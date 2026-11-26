import Foundation

struct BotConfiguration {
    let executable: URL
    let directory: URL
    let environment: [String: String]

    static func isProject(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent(".astrbot").path)
    }

    static func discoverProject() -> URL? {
        // Finder and Terminal can give an app very different working directories.
        let locations = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                         Bundle.main.bundleURL.deletingLastPathComponent(),
                         FileManager.default.homeDirectoryForCurrentUser]
        for location in locations {
            var candidate = location.standardizedFileURL
            while candidate.path != "/" {
                if isProject(candidate) { return candidate }
                candidate = candidate.deletingLastPathComponent()
            }
        }
        return nil
    }

    static func resolve(in directory: URL) throws -> Self {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let paths = (inherited + ["\(home)/.local/bin", "\(home)/.cargo/bin", "/opt/homebrew/bin",
                                 "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
        let files = FileManager.default
        let executable = [directory.appendingPathComponent(".venv/bin/astrbot")]
            + paths.map { URL(fileURLWithPath: $0).appendingPathComponent("astrbot") }
        guard let command = executable.first(where: { url in
            var isDirectory: ObjCBool = false
            return files.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
                && files.isExecutableFile(atPath: url.path)
        }) else {
            throw NSError(domain: "Astrview", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "找不到 astrbot。请安装 AstrBot CLI，或在项目的 .venv/bin 中提供 astrbot。"])
        }
        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["DASHBOARD_PORT"] = "6185"
        environment["DASHBOARD_HOST"] = "127.0.0.1"
        environment["DASHBOARD_SSL_ENABLE"] = "0"
        return Self(executable: command, directory: directory, environment: environment)
    }
}

struct BotOutput {
    private static let ansi = try! NSRegularExpression(pattern: #"\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#)
    private static let ready = try! NSRegularExpression(pattern: #"\bAstrBot v([^\s]+) WebUI is ready\b"#)
    private var pending = Data()
    private var reportedReady = false

    mutating func consume(_ bytes: Data, end: Bool = false) -> (text: String, version: String?) {
        pending.append(bytes)
        let boundary: Data.Index
        if end {
            boundary = pending.endIndex
        } else if let newline = pending.lastIndex(of: 10) {
            boundary = newline + 1
        } else if pending.count > 128 * 1024 {
            // Bound buffering even if an unusually long line never ends.
            boundary = pending.endIndex - 4096
        } else {
            boundary = pending.startIndex
        }
        let complete = String(decoding: pending.prefix(upTo: boundary), as: UTF8.self)
        pending = Data(pending.suffix(from: boundary))
        let text = Self.plain(complete)
        var version: String?
        if !reportedReady {
            // Detect a complete banner even if it has no trailing newline yet.
            let candidate = text + Self.plain(String(decoding: pending, as: UTF8.self))
            if let match = Self.ready.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
               let range = Range(match.range(at: 1), in: candidate) {
                version = String(candidate[range])
                reportedReady = true
            }
        }
        return (text, version)
    }

    private static func plain(_ text: String) -> String {
        Self.ansi.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

final class BotProcess {
    private let process = Process()
    private let pipe = Pipe()

    func start(_ configuration: BotConfiguration, output: @escaping (String, String?) -> Void,
               exited: @escaping (Int32) -> Void) throws {
        process.executableURL = configuration.executable
        process.arguments = ["run"]
        process.currentDirectoryURL = configuration.directory
        process.environment = configuration.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        try? pipe.fileHandleForWriting.close()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var parser = BotOutput()
            let reader = pipe.fileHandleForReading
            while true {
                let data = reader.availableData
                let result = parser.consume(data, end: data.isEmpty)
                if !result.text.isEmpty || result.version != nil {
                    DispatchQueue.main.async { output(result.text, result.version) }
                }
                if data.isEmpty { break }
            }
            try? reader.close()
            process.waitUntilExit()
            let status = process.terminationStatus
            DispatchQueue.main.async { exited(status) }
        }
    }

    func stop() {
        guard process.isRunning else { return }
        process.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
