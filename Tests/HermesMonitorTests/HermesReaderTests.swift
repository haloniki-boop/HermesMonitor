import XCTest
@testable import HermesMonitor

final class HermesReaderTests: XCTestCase {
    func testSystemInfoAndUptimeFormatting() {
        XCTAssertTrue(HermesSystemInfo.osName.hasPrefix("macOS "))
        XCTAssertEqual(HermesSystemInfo.uptimeLabel(nil), "—")
        XCTAssertEqual(HermesSystemInfo.uptimeLabel(59), "0分")
        XCTAssertEqual(HermesSystemInfo.uptimeLabel(3_660), "1時間 1分")
        XCTAssertEqual(HermesSystemInfo.uptimeLabel(90_060), "1日 1時間 1分")
    }

    func testPsElapsedTimeParsing() {
        XCTAssertEqual(HermesElapsedTime.seconds("01:30"), 90)
        XCTAssertEqual(HermesElapsedTime.seconds("02:01:30"), 7_290)
        XCTAssertEqual(HermesElapsedTime.seconds("1-02:01:30"), 93_690)
        XCTAssertNil(HermesElapsedTime.seconds("invalid"))
    }

    func testWorkingDirectoryPrefersActiveSessionThenRecentSession() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let db = home.appendingPathComponent("state.db").path
        let setup = """
        CREATE TABLE sessions (id TEXT PRIMARY KEY, cwd TEXT, started_at REAL, last_activity_at REAL);
        CREATE TABLE session_turn_leases (conversation_id TEXT, expires_at REAL, acquired_at REAL);
        INSERT INTO sessions VALUES ('active','/work/active',1,1),('recent','/work/recent',2,2);
        """
        XCTAssertEqual(CommandRunner.run("/usr/bin/sqlite3", [db, setup]).0, 0)
        let recent = HermesReader(home: home).read()
        XCTAssertEqual(recent.workingDirectory, "/work/recent")
        XCTAssertTrue(recent.workingDirectoryIsRecent)
        XCTAssertFalse(recent.machine.isEmpty)

        let lease = "INSERT INTO session_turn_leases VALUES ('active',strftime('%s','now')+60,strftime('%s','now'));"
        XCTAssertEqual(CommandRunner.run("/usr/bin/sqlite3", [db, lease]).0, 0)
        let active = HermesReader(home: home).read()
        XCTAssertEqual(active.workingDirectory, "/work/active")
        XCTAssertFalse(active.workingDirectoryIsRecent)
    }

    func testModelConfigParserIgnoresOtherSections() {
        let source = """
        other:
          default: wrong
        model:
          provider: ollama-launch
          default: gemma4:12b
        next:
          provider: wrong
        """
        let parsed = ModelConfigParser.read(source)
        XCTAssertEqual(parsed.model, "gemma4:12b")
        XCTAssertEqual(parsed.provider, "ollama-launch")
    }

    func testMissingConfigDoesNotFabricateMeasurements() {
        let reader = HermesReader(home: URL(fileURLWithPath: "/nonexistent/hermes-monitor-test"))
        let snapshot = reader.read()
        XCTAssertEqual(snapshot.model, "不明")
        XCTAssertNil(snapshot.memoryMB)
        XCTAssertNotNil(snapshot.lastError)
    }

    func testScheduledJobsOnlyShowsEnabledUpcomingItems() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("cron"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try "model:\n  default: gemma4:12b\n  provider: ollama-launch\n".write(
            to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let jobs = """
        {"jobs":[
          {"id":"a","name":"朝の確認","enabled":true,"next_run_at":"2026-10-11T09:00:00+09:00"},
          {"id":"b","name":"停止中","enabled":false,"next_run_at":"2026-10-11T10:00:00+09:00"},
          {"id":"c","name":"完了","enabled":true,"next_run_at":null}
        ]}
        """
        try jobs.write(to: home.appendingPathComponent("cron/jobs.json"), atomically: true, encoding: .utf8)
        let snapshot = HermesReader(home: home).read()
        XCTAssertEqual(snapshot.model, "gemma4:12b")
        XCTAssertEqual(snapshot.quota, "ローカルモデル（利用枠なし）")
        XCTAssertEqual(snapshot.scheduledTasks.map(\.name), ["朝の確認"])
    }

    func testInvalidModelNeverCallsHermes() {
        let error = HermesReader().changeModel(to: "bad\nmodel")
        XCTAssertEqual(error, "モデル名が無効です")
    }

    func testGatewayCommandsUseHermesCLI() {
        XCTAssertEqual(HermesGatewayCommand.start.arguments, ["gateway", "start"])
        XCTAssertEqual(HermesGatewayCommand.stop.arguments, ["gateway", "stop"])
    }

    func testNoticeParserOnlyKeepsRecentHermesWarnings() {
        let source = """
        2026-10-10 08:00:00,000 INFO gateway: ready
        2026-10-10 08:01:00,000 WARNING gateway: retrying
        2026-10-10 08:02:00,000 ERROR agent: unavailable
        """
        let notices = HermesNoticeParser.parse(source)
        XCTAssertEqual(notices.map(\.level), ["ERROR", "WARNING"])
        XCTAssertEqual(notices.first?.message, "agent: unavailable")
    }

    func testNoticeParserSeparatesCurrentAndPreviousGatewayRun() {
        let source = """
        2026-10-11 05:59:00,000 WARNING gateway: old issue
        2026-10-11 06:01:00,000 WARNING gateway: new issue
        """
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        let started = formatter.date(from: "2026-10-11 06:00:00,000")!
        let result = HermesNoticeParser.split(source, since: started)
        XCTAssertEqual(result.current.map(\.message), ["gateway: new issue"])
        XCTAssertEqual(result.past.map(\.message), ["gateway: old issue"])
    }

    func testNoMessagingNoticeIsExplainedAsInformational() {
        let notice = HermesNotice(id: "1", time: "2026-10-11", level: "WARNING",
                                  message: "gateway.run: No messaging platforms enabled.")
        XCTAssertEqual(HermesNoticeJapanese.displayLevel(for: notice), "案内")
        XCTAssertTrue(HermesNoticeJapanese.fallback(for: notice).contains("対応は不要"))
    }

    func testDisabledRemoteLoginMovesSecurityFindingToResolvedHistory() {
        let source = """
        2026-10-11 06:00:26,701 WARNING hermes.security_audit: Security posture audit found 1 issue(s)
        2026-10-11 06:00:26,701 WARNING hermes.security_audit: SSH password authentication is ENABLED
        2026-10-11 06:00:27,005 WARNING gateway.run: No messaging platforms enabled.
        """
        let started = Date(timeIntervalSince1970: 0)
        let result = HermesNoticeParser.split(source, since: started, remoteLoginDisabled: true)
        XCTAssertEqual(result.current.count, 1)
        XCTAssertTrue(result.current[0].message.contains("No messaging"))
        XCTAssertEqual(result.past.count, 2)
        let unresolved = HermesNoticeParser.split(source, since: started, remoteLoginDisabled: false)
        XCTAssertEqual(unresolved.current.count, 3)
    }

    func testLongNoticeIsNotTruncated() {
        let body = String(repeating: "notification details ", count: 30)
        let notices = HermesNoticeParser.parse("2026-10-10 08:00:00,000 WARNING gateway: \(body)")
        XCTAssertEqual(notices.first?.message, "gateway: \(body)")
    }

    func testJapaneseNoticeFallback() {
        let notice = HermesNotice(id: "1", time: "2026-10-10", level: "WARNING",
                                  message: "gateway: connection refused")
        XCTAssertEqual(HermesNoticeJapanese.level(notice.level), "警告")
        XCTAssertEqual(HermesNoticeJapanese.fallback(for: notice),
                       "接続先に到達できませんでした。Hermesとモデルの接続状態を確認してください。")
        XCTAssertTrue(HermesNoticeJapanese.containsJapanese("接続できません"))
        XCTAssertFalse(HermesNoticeJapanese.containsJapanese("connection refused"))
    }

    func testProviderMenuReadsConfiguredAndAuthenticatedProviders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try "providers:\n  ollama-launch:\n    models:\n      - gemma4:12b\n".write(
            to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        try "{\"credential_pool\":{\"nous\":[]}}".write(
            to: home.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let providers = HermesReader(home: home).availableProviders(current: "ollama-launch", currentModel: "gemma4:12b")
        XCTAssertEqual(providers.map(\.id), ["nous", "ollama-launch"])
        XCTAssertEqual(providers.first(where: { $0.id == "ollama-launch" })?.models, ["gemma4:12b"])
    }
}
