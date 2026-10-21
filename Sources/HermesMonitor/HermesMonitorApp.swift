import SwiftUI
import AppKit
import Combine

@MainActor
final class Monitor: ObservableObject {
    @Published var snapshot = HermesSnapshot()
    @Published var providers: [ProviderOption] = []
    @Published var selectedProvider = ""
    @Published var models: [String] = []
    @Published var selectedModel = ""
    @Published var isChanging = false
    @Published var isControlling = false
    @Published var actionMessage: String? = nil
    private var hasPendingSelection = false

    private let reader = HermesReader()

    func refresh() {
        let reader = self.reader
        Task {
            let result = await Task.detached { () -> (HermesSnapshot, [ProviderOption]) in
                let snapshot = reader.read()
                return (snapshot, reader.availableProviders(current: snapshot.provider, currentModel: snapshot.model))
            }.value
            snapshot = result.0
            providers = result.1
            if !hasPendingSelection && !isChanging {
                selectedProvider = snapshot.provider
                selectedModel = snapshot.model
            }
            models = providers.first(where: { $0.id == selectedProvider })?.models ?? [selectedModel]
        }
    }

    func selectProvider(_ provider: String) {
        selectedProvider = provider
        models = providers.first(where: { $0.id == provider })?.models ?? []
        selectedModel = provider == snapshot.provider ? snapshot.model : (models.first ?? "")
        hasPendingSelection = true
    }

    func selectModel(_ model: String) {
        selectedModel = model
        hasPendingSelection = true
    }

    func changeModel() {
        guard !isChanging else { return }
        isChanging = true
        actionMessage = nil
        let model = selectedModel
        let provider = selectedProvider
        let reader = self.reader
        Task {
            let error = await Task.detached { reader.changeProvider(provider, model: model) }.value
            isChanging = false
            hasPendingSelection = error != nil
            actionMessage = error == nil ? "モデルとプロバイダーを更新しました。次のセッションから反映されます。" : error
            refresh()
        }
    }

    func controlGateway(_ command: HermesGatewayCommand) {
        guard !isControlling else { return }
        isControlling = true
        actionMessage = nil
        let reader = self.reader
        Task {
            let error = await Task.detached { reader.controlGateway(command) }.value
            isControlling = false
            actionMessage = error == nil ? (command == .start ? "Hermesの開始を要求しました" : "Hermesの停止を要求しました") : error
            refresh()
        }
    }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var showPastNotices = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(monitor.snapshot.isRunning ? .green : .secondary)
                    .font(.title2)
                Text("Hermes Agent").font(.headline)
                Spacer()
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("更新")
            }

            HStack {
                Circle().fill(monitor.snapshot.isRunning ? .green : .gray).frame(width: 8, height: 8)
                Text(monitor.snapshot.isRunning ? "稼働中" : "停止中")
                Spacer()
                Text("メモリ: \(monitor.snapshot.memoryMB.map { "\($0) MB" } ?? "—")")
            }.font(.subheadline)

            HStack {
                Text("Hermes Gateway").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(monitor.snapshot.isRunning ? "OFF・停止" : "ON・開始") {
                    monitor.controlGateway(monitor.snapshot.isRunning ? .stop : .start)
                }
                .disabled(monitor.isControlling)
            }

            Divider()
            LabeledContent("OS", value: monitor.snapshot.os)
            LabeledContent("作業マシーン", value: monitor.snapshot.machine)
            LabeledContent("稼働時間", value: HermesSystemInfo.uptimeLabel(monitor.snapshot.uptimeSeconds))
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.snapshot.workingDirectoryIsRecent ? "作業ディレクトリ（直近のセッション）" : "作業ディレクトリ")
                    .foregroundStyle(.secondary)
                Text(monitor.snapshot.workingDirectory ?? "—")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            LabeledContent("使用中のモデル", value: monitor.snapshot.model)
            LabeledContent("モデルの残量", value: monitor.snapshot.quota)

            VStack(alignment: .leading, spacing: 6) {
                Text("プロバイダー・モデル変更").font(.caption).foregroundStyle(.secondary)
                Picker("プロバイダー", selection: Binding(
                    get: { monitor.selectedProvider }, set: { monitor.selectProvider($0) }
                )) {
                    ForEach(monitor.providers) { Text($0.id).tag($0.id) }
                }
                HStack {
                    Picker("モデル", selection: Binding(
                        get: { monitor.selectedModel }, set: { monitor.selectModel($0) }
                    )) {
                        ForEach(monitor.models, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: .infinity)
                    Button("適用") { monitor.changeModel() }
                        .disabled(monitor.isChanging || monitor.selectedModel.isEmpty ||
                                  (monitor.selectedModel == monitor.snapshot.model &&
                                   monitor.selectedProvider == monitor.snapshot.provider))
                }
            }

            if let message = monitor.actionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            taskSection("実行中のタスク", tasks: monitor.snapshot.activeTasks, empty: "実行中のタスクはありません")
            Divider()
            taskSection("実行予定のタスク", tasks: Array(monitor.snapshot.scheduledTasks.prefix(6)), empty: "予定されたタスクはありません")

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Hermesからの通知").font(.subheadline).bold()
                if monitor.snapshot.notices.isEmpty {
                    Text("現在の通知はありません").font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(monitor.snapshot.notices) { notice in
                            if #available(macOS 15.0, *) {
                                JapaneseNoticeRow(notice: notice)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(HermesNoticeJapanese.displayLevel(for: notice))  \(notice.time)")
                                        .font(.caption2).foregroundStyle(.orange)
                                    Text(HermesNoticeJapanese.fallback(for: notice))
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(notice.message).font(.caption2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !monitor.snapshot.pastNotices.isEmpty {
                    DisclosureGroup("過去・解決済みの通知（直近\(monitor.snapshot.pastNotices.count)件）", isExpanded: $showPastNotices) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(monitor.snapshot.pastNotices) { notice in
                                if #available(macOS 15.0, *) {
                                    JapaneseNoticeRow(notice: notice)
                                } else {
                                    Text("\(HermesNoticeJapanese.displayLevel(for: notice))  \(notice.time)\n\(HermesNoticeJapanese.fallback(for: notice))")
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .font(.caption)
                }
            }

            if let error = monitor.snapshot.lastError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("更新: \(monitor.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
            }.font(.caption)
            }
            .padding(16)
        }
        .frame(width: 360, height: min(700, max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 80)))
        .onAppear { monitor.refresh() }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            monitor.refresh()
        }
    }

    private func taskSection(_ title: String, tasks: [HermesTask], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).bold()
            if tasks.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name).lineLimit(1)
                        Text(task.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

@main
struct HermesMonitorApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra("Hermes Agent", systemImage: "bolt.circle") {
            Dashboard(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
