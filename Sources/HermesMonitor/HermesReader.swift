import Foundation

struct HermesTask: Identifiable {
    let id: String
    let name: String
    let detail: String
}

struct ProviderOption: Identifiable {
    let id: String
    let models: [String]
}

struct HermesNotice: Identifiable, Equatable {
    let id: String
    let time: String
    let level: String
    let message: String
}

struct HermesSnapshot {
    var isRunning = false
    var memoryMB: Int? = nil
    var os = HermesSystemInfo.osName
    var workingDirectory: String? = nil
    var workingDirectoryIsRecent = false
    var machine = ProcessInfo.processInfo.hostName
    var uptimeSeconds: TimeInterval? = nil
    var gatewayStartedAt: Date? = nil
    var model = "不明"
    var provider = "不明"
    var quota = "取得できません"
    var activeTasks: [HermesTask] = []
    var scheduledTasks: [HermesTask] = []
    var notices: [HermesNotice] = []
    var pastNotices: [HermesNotice] = []
    var lastError: String? = nil
    var updatedAt = Date()
}

enum HermesSystemInfo {
    static var osName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func uptimeLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        let minutes = Int(seconds) / 60
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let remainingMinutes = minutes % 60
        if days > 0 { return "\(days)日 \(hours)時間 \(remainingMinutes)分" }
        if hours > 0 { return "\(hours)時間 \(remainingMinutes)分" }
        return "\(remainingMinutes)分"
    }
}

enum HermesElapsedTime {
    static func seconds(_ value: String) -> TimeInterval? {
        let dayParts = value.split(separator: "-", maxSplits: 1)
        guard dayParts.count <= 2 else { return nil }
        let days = dayParts.count == 2 ? Int(dayParts[0]) : 0
        let clock = String(dayParts.last ?? "").split(separator: ":").compactMap { Int($0) }
        guard let days, (2...3).contains(clock.count) else { return nil }
        let hours = clock.count == 3 ? clock[0] : 0
        let minutes = clock.count == 3 ? clock[1] : clock[0]
        let seconds = clock.last ?? 0
        guard days >= 0, hours >= 0, (0..<60).contains(minutes), (0..<60).contains(seconds) else { return nil }
        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }
}

enum ModelConfigParser {
    static func read(_ source: String) -> (model: String, provider: String) {
        var inModel = false
        var model = ""
        var provider = ""
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line == "model:" { inModel = true; continue }
            if !line.hasPrefix(" ") && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                inModel = false
            }
            guard inModel, line.hasPrefix("  "), !line.hasPrefix("    ") else { continue }
            if trimmed.hasPrefix("default:") { model = scalar(trimmed.dropFirst("default:".count)) }
            if trimmed.hasPrefix("provider:") { provider = scalar(trimmed.dropFirst("provider:".count)) }
        }
        return (model, provider)
    }

    private static func scalar(_ value: Substring) -> String {
        let raw = value.trimmingCharacters(in: .whitespaces)
        if raw.count >= 2 && ((raw.first == "\"" && raw.last == "\"") ||
                              (raw.first == "'" && raw.last == "'")) {
            return String(raw.dropFirst().dropLast())
        }
        return raw.components(separatedBy: " #").first ?? raw
    }
}

enum CommandRunner {
    static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

enum HermesGatewayCommand: String {
    case start
    case stop

    var arguments: [String] { ["gateway", rawValue] }
}

enum HermesNoticeParser {
    static func parse(_ source: String) -> [HermesNotice] {
        Array(parseAll(source).suffix(5).reversed())
    }

    static func split(_ source: String, since startedAt: Date,
                      remoteLoginDisabled: Bool = false) -> (current: [HermesNotice], past: [HermesNotice]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        let notices = parseAll(source)
        let currentSSHSeconds = Set(notices.filter { notice in
            guard let time = formatter.date(from: notice.time) else { return false }
            return time >= startedAt && notice.message.contains("SSH password authentication is ENABLED")
        }.map { String($0.time.prefix(19)) })
        func isResolvedSSHNotice(_ notice: HermesNotice) -> Bool {
            guard remoteLoginDisabled else { return false }
            if notice.message.contains("SSH password authentication is ENABLED") { return true }
            return notice.message.contains("Security posture audit found 1 issue(s)") &&
                currentSSHSeconds.contains(String(notice.time.prefix(19)))
        }
        let current = notices.filter { notice in
            guard let time = formatter.date(from: notice.time) else { return true }
            return time >= startedAt && !isResolvedSSHNotice(notice)
        }
        let past = notices.filter { notice in
            guard let time = formatter.date(from: notice.time) else { return false }
            return time < startedAt || (time >= startedAt && isResolvedSSHNotice(notice))
        }
        return (Array(current.suffix(5).reversed()), Array(past.suffix(5).reversed()))
    }

    private static func parseAll(_ source: String) -> [HermesNotice] {
        source.components(separatedBy: .newlines).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3)
            guard fields.count == 4, ["WARNING", "ERROR", "CRITICAL"].contains(String(fields[2])) else {
                return nil
            }
            return HermesNotice(id: String(line.hashValue), time: String(fields[0]) + " " + String(fields[1]),
                                level: String(fields[2]), message: String(fields[3]))
        }
    }
}

struct HermesReader {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")) {
        self.home = home
    }

    func read() -> HermesSnapshot {
        var snapshot = HermesSnapshot()
        let configURL = home.appendingPathComponent("config.yaml")
        if let config = try? String(contentsOf: configURL, encoding: .utf8) {
            let parsed = ModelConfigParser.read(config)
            snapshot.model = parsed.model.isEmpty ? "未設定" : parsed.model
            snapshot.provider = parsed.provider.isEmpty ? "未設定" : parsed.provider
            snapshot.quota = parsed.provider.contains("ollama") ? "ローカルモデル（利用枠なし）" : "プロバイダーから取得不可"
        } else {
            snapshot.lastError = "Hermes の設定を読み取れません"
        }

        let processes = processRows()
        let hermesProcesses = processes.filter {
            let command = $0.command.lowercased()
            return (command.contains("hermes-agent") || command.contains("hermes_cli") ||
                    command.contains("hermes gateway")) && !command.contains("hermesmonitor")
        }
        if !hermesProcesses.isEmpty {
            snapshot.isRunning = true
            snapshot.memoryMB = Int(ceil(Double(hermesProcesses.reduce(0) { $0 + $1.rssKB }) / 1024.0))
        }
        if let gateway = hermesProcesses.filter({ $0.command.hasSuffix("gateway run --external-supervisor") })
            .compactMap({ $0.elapsedSeconds }).min() {
            snapshot.uptimeSeconds = gateway
            snapshot.gatewayStartedAt = Date().addingTimeInterval(-gateway)
        }

        let db = home.appendingPathComponent("state.db").path
        if FileManager.default.fileExists(atPath: db) {
            let heartbeatSQL = "SELECT pid,host,started_at FROM gateway_heartbeats WHERE last_heartbeat > strftime('%s','now') - 45 ORDER BY last_heartbeat DESC"
            if let heartbeats = query(db: db, sql: heartbeatSQL) {
                for heartbeat in heartbeats {
                    guard let pid = heartbeat["pid"] as? Int else { continue }
                    guard processes.contains(where: { $0.pid == pid }) else { continue }
                    snapshot.isRunning = true
                    if snapshot.uptimeSeconds == nil {
                        if let host = heartbeat["host"] as? String, !host.isEmpty { snapshot.machine = host }
                        if let started = heartbeat["started_at"] as? Double {
                            snapshot.gatewayStartedAt = Date(timeIntervalSince1970: started)
                            snapshot.uptimeSeconds = max(0, Date().timeIntervalSince1970 - started)
                        }
                    }
                }
            }

            let activeSQL = """
            SELECT l.conversation_id AS id,
                   COALESCE(NULLIF(s.title,''), NULLIF(s.display_name,''), s.source, 'Hermes task') AS name,
                   COALESCE(s.last_activity_description,'実行中') AS detail
            FROM session_turn_leases l
            LEFT JOIN sessions s ON s.id = l.conversation_id
            WHERE l.expires_at > strftime('%s','now')
            ORDER BY l.acquired_at DESC LIMIT 8
            """
            if let rows = query(db: db, sql: activeSQL) {
                snapshot.activeTasks = rows.compactMap { row in
                    guard let id = row["id"] as? String else { return nil }
                    return HermesTask(id: id, name: row["name"] as? String ?? "Hermes task",
                                      detail: row["detail"] as? String ?? "実行中")
                }
            }

            let activeDirectorySQL = """
            SELECT s.cwd AS cwd FROM session_turn_leases l JOIN sessions s ON s.id = l.conversation_id
            WHERE l.expires_at > strftime('%s','now') AND NULLIF(s.cwd,'') IS NOT NULL
            ORDER BY l.acquired_at DESC LIMIT 1
            """
            let recentDirectorySQL = """
            SELECT cwd FROM sessions WHERE NULLIF(cwd,'') IS NOT NULL
            ORDER BY COALESCE(last_activity_at,started_at) DESC LIMIT 1
            """
            if let row = query(db: db, sql: activeDirectorySQL)?.first {
                snapshot.workingDirectory = row["cwd"] as? String
            } else if let row = query(db: db, sql: recentDirectorySQL)?.first {
                snapshot.workingDirectory = row["cwd"] as? String
                snapshot.workingDirectoryIsRecent = true
            }
        }

        let jobsURL = home.appendingPathComponent("cron/jobs.json")
        if let data = try? Data(contentsOf: jobsURL),
           let json = try? JSONSerialization.jsonObject(with: data),
           let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] {
            snapshot.scheduledTasks = jobs.compactMap { job in
                guard (job["enabled"] as? Bool ?? true),
                      let next = job["next_run_at"] as? String, !next.isEmpty else { return nil }
                let id = String(describing: job["id"] ?? next)
                return HermesTask(id: id, name: job["name"] as? String ?? "無名のタスク", detail: next)
            }.sorted { $0.detail < $1.detail }
        }
        let errorLog = home.appendingPathComponent("logs/errors.log")
        if let content = try? String(contentsOf: errorLog, encoding: .utf8) {
            if let startedAt = snapshot.gatewayStartedAt {
                let notices = HermesNoticeParser.split(content, since: startedAt,
                                                       remoteLoginDisabled: remoteLoginDisabled())
                snapshot.notices = notices.current
                snapshot.pastNotices = notices.past
            } else {
                snapshot.notices = HermesNoticeParser.parse(content)
            }
        }
        snapshot.updatedAt = Date()
        return snapshot
    }

    func availableProviders(current: String, currentModel: String) -> [ProviderOption] {
        var ids = Set([current])
        if let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
           let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            ids.formUnion((auth["providers"] as? [String: Any])?.keys ?? [:].keys)
            ids.formUnion((auth["credential_pool"] as? [String: Any])?.keys ?? [:].keys)
        }

        let config = (try? String(contentsOf: home.appendingPathComponent("config.yaml"), encoding: .utf8)) ?? ""
        var inProviders = false
        var localModels: [String: [String]] = [:]
        var configuredID = ""
        var inModels = false
        for line in config.components(separatedBy: .newlines) {
            if line == "providers:" { inProviders = true; continue }
            if inProviders && !line.hasPrefix(" ") && !line.isEmpty { inProviders = false }
            guard inProviders else { continue }
            if line.hasPrefix("  ") && !line.hasPrefix("    ") && line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                configuredID = String(line.trimmingCharacters(in: .whitespaces).dropLast())
                ids.insert(configuredID)
                inModels = false
            } else if line.trimmingCharacters(in: .whitespaces) == "models:" && line.hasPrefix("    ") {
                inModels = true
            } else if inModels && line.hasPrefix("      - ") {
                localModels[configuredID, default: []].append(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces))
            }
        }

        var cachedModels: [String: [String]] = [:]
        if let data = try? Data(contentsOf: home.appendingPathComponent("provider_models_cache.json")),
           let cache = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (id, entry) in cache { cachedModels[id] = entry["models"] as? [String] ?? [] }
        }
        if let data = try? Data(contentsOf: home.appendingPathComponent("cache/model_catalog.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let catalog = root["providers"] as? [String: [String: Any]] {
            for (id, entry) in catalog {
                let models = (entry["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                cachedModels[id, default: []].append(contentsOf: models)
            }
        }
        return ids.filter { !$0.isEmpty }.sorted().map { id in
            var models = (localModels[id] ?? []) + (cachedModels[id] ?? [])
            if id == current { models.insert(currentModel, at: 0) }
            return ProviderOption(id: id, models: Array(Set(models.filter { !$0.isEmpty })).sorted())
        }
    }

    func availableModels(current: String) -> [String] {
        var models = [current]
        // Hermes の現行プロバイダーが Ollama の場合はローカルのモデル一覧を利用する。
        let ollama = "/opt/homebrew/bin/ollama"
        if FileManager.default.isExecutableFile(atPath: ollama) {
            let (status, output) = CommandRunner.run(ollama, ["list"])
            if status == 0 {
                models += output.components(separatedBy: .newlines).dropFirst().compactMap {
                    $0.split(whereSeparator: \.isWhitespace).first.map(String.init)
                }
            }
        }
        return Array(Set(models.filter { !$0.isEmpty && $0 != "不明" })).sorted()
    }

    func changeModel(to model: String) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            return "モデル名が無効です"
        }
        let command = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hermes").path
        guard FileManager.default.isExecutableFile(atPath: command) else { return "Hermes コマンドが見つかりません" }
        let (status, output) = CommandRunner.run(command, ["config", "set", "model.default", trimmed])
        if status != 0 { return output.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    func changeProvider(_ provider: String, model: String) -> String? {
        guard !provider.isEmpty, !model.isEmpty,
              !provider.contains("\n"), !model.contains("\n") else { return "プロバイダーまたはモデルが無効です" }
        let bridge = Bundle.main.resourceURL?.appendingPathComponent("hermes_bridge.py")
        guard let bridge, FileManager.default.fileExists(atPath: bridge.path) else {
            return "Hermes連携ファイルが見つかりません"
        }
        let installs = home.appendingPathComponent("installs")
        let interpreter = findHermesPython(in: installs)
        guard let interpreter else { return "HermesのPython環境が見つかりません" }
        let (status, output) = CommandRunner.run(interpreter, [bridge.path, provider, model])
        let payload = output.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if status != 0 || payload?["ok"] as? Bool != true {
            return payload?["error"] as? String ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    func controlGateway(_ command: HermesGatewayCommand) -> String? {
        let executable = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hermes").path
        guard FileManager.default.isExecutableFile(atPath: executable) else { return "Hermesコマンドが見つかりません" }
        let (status, output) = CommandRunner.run(executable, command.arguments)
        return status == 0 ? nil : output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findHermesPython(in directory: URL) -> String? {
        guard let installs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        let candidates = installs.flatMap { install -> [URL] in
            let environments = install.appendingPathComponent("environments")
            return (try? FileManager.default.contentsOfDirectory(at: environments, includingPropertiesForKeys: nil)) ?? []
        }.map { $0.appendingPathComponent("venv/bin/python") }
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
            .max { (a, b) in
                let am = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bm = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return am < bm
            }?.path
    }

    private func query(db: String, sql: String) -> [[String: Any]]? {
        let (status, output) = CommandRunner.run("/usr/bin/sqlite3", ["-readonly", "-json", db, sql])
        guard status == 0, let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private func processRows() -> [(pid: Int, rssKB: Int, elapsedSeconds: TimeInterval?, command: String)] {
        let (status, output) = CommandRunner.run("/bin/ps", ["-axo", "pid=,rss=,etime=,command="])
        guard status == 0 else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard parts.count == 4, let pid = Int(parts[0]), let rss = Int(parts[1]) else { return nil }
            return (pid, rss, HermesElapsedTime.seconds(String(parts[2])), String(parts[3]))
        }
    }

    private func remoteLoginDisabled() -> Bool {
        let (status, output) = CommandRunner.run("/bin/launchctl", ["print-disabled", "system"])
        return status == 0 && output.contains("\"com.openssh.sshd\" => disabled")
    }
}
