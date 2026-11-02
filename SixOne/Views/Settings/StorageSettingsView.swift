//
//  StorageSettingsView.swift
//  SixOne
//
//  设置 → 存储：历史概况（条数、占用空间）、存储上限、保留时长（整档滑块）与清空历史。
//

import AppKit
import SwiftUI

struct StorageSettingsView: View {
    let settings: SettingsStore
    let loadStats: () async -> HistoryStorageStats
    let onClearHistory: () -> Void

    @Environment(\.locale) private var locale
    /// nil = 还没读到（首次加载、无磁盘占用、读库失败）。
    @State private var stats: HistoryStorageStats?

    var body: some View {
        Group {
            Section {
                statRow("Records", value: recordsText)
                statRow("Disk Usage", value: spaceText)
                Picker("Storage Limit", selection: storageLimitBinding) {
                    ForEach(HistoryStorageLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("History")
            } footer: {
                Text("Includes the history database and attachments; clearing history may not free disk space immediately. Images and rich text are trimmed oldest-first when they exceed the storage limit; the most recent item is always kept.")
            }

            Section {
                Slider(value: retentionBinding, in: 0...4) {
                    Text("History Retention")
                } currentValueLabel: {
                    Text(settings.historyRetention.title)
                        .foregroundStyle(.secondary)
                } ticks: {
                    SliderTickContentForEach(
                        (0...4).map { Double($0) },
                        id: \.self
                    ) { value in
                        SliderTick(value) {
                            Text(HistoryRetention(rawValue: Int(value.rounded()))?.title ?? .init(""))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Retention")
            } footer: {
                HStack {
                    Spacer()
                    Button("Clear History") {
                        confirmClearHistory()
                    }
                    .disabled(isHistoryEmpty)
                }
            }
        }
        .task {
            await refreshStats()
        }
        // 改保留档位或存储上限会立刻触发维护，概况要跟着变。
        .onChange(of: settings.historyRetention) { _, _ in
            Task { await refreshStats() }
        }
        .onChange(of: settings.storageLimit) { _, _ in
            Task { await refreshStats() }
        }
    }

    private func statRow(_ title: LocalizedStringKey, value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// 没读到条数时不置灰，避免像「不可用」而不是「没东西可清」。
    private var isHistoryEmpty: Bool {
        guard let itemCount = stats?.itemCount else { return false }
        return itemCount == 0
    }

    private var recordsText: String? {
        stats?.itemCount.map { $0.formatted(.number.locale(locale)) }
    }

    private var spaceText: String? {
        stats?.byteCount.map(ByteCountFormatting.string(fromByteCount:))
    }

    private func refreshStats() async {
        stats = await loadStats()
    }

    private func confirmClearHistory() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        ConfirmationAlert.present(
            on: window,
            title: Localizer.string("Clear History?"),
            message: Localizer.string("This deletes all clipboard history. It cannot be undone."),
            actionTitle: Localizer.string("Clear History"),
            onAction: {
                onClearHistory()
                Task { await refreshStats() }
            },
            onCancel: {}
        )
    }

    /// 滑块绑定：写入取整映射回枚举；重复档位由 `SettingsStore` 判等挡掉落盘与裁剪。
    private var retentionBinding: Binding<Double> {
        Binding(
            get: { Double(settings.historyRetention.rawValue) },
            set: { newValue in
                settings.historyRetention = HistoryRetention(rawValue: Int(newValue.rounded()))
                    ?? SettingsStore.defaultRetention
            }
        )
    }

    private var storageLimitBinding: Binding<HistoryStorageLimit> {
        Binding(
            get: { settings.storageLimit },
            set: { settings.storageLimit = $0 }
        )
    }
}

private extension HistoryRetention {
    var title: LocalizedStringKey {
        switch self {
        case .oneMonth: "1 Month"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .oneYear: "1 Year"
        case .unlimited: "Unlimited"
        }
    }
}

private extension HistoryStorageLimit {
    var title: LocalizedStringKey {
        switch self {
        case .megabytes500: "500 MB"
        case .gigabytes1: "1 GB"
        case .gigabytes2: "2 GB"
        case .gigabytes5: "5 GB"
        case .gigabytes10: "10 GB"
        case .unlimited: "Unlimited"
        }
    }
}
