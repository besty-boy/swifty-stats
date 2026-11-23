import AppKit
import Observation
import SwiftUI
import SwiftyStatsCore

@MainActor
@Observable
final class PopoverUIState {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Aperçu"
        case sensors = "Capteurs"
        case settings = "Réglages"

        var id: String { rawValue }
    }

    enum ThermalChartMode: String, CaseIterable {
        case temperature = "°C"
        case power = "W"
    }

    enum ProcessSortMode: String, CaseIterable {
        case cpu = "CPU"
        case ram = "RAM"
    }

    var selectedTab: Tab = .overview
    var thermalChartMode: ThermalChartMode = .temperature
    var processSortMode: ProcessSortMode = .cpu
    var launchAtLogin: Bool = false
}

struct PopoverRootView: View {
    let monitor: SystemMonitor
    let uiState: PopoverUIState
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 8)

            Picker("", selection: Binding(
                get: { uiState.selectedTab },
                set: { uiState.selectedTab = $0 }
            )) {
                ForEach(PopoverUIState.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch uiState.selectedTab {
                    case .overview:
                        OverviewTabView(monitor: monitor, uiState: uiState)
                    case .sensors:
                        SensorsTabView(monitor: monitor)
                    case .settings:
                        SettingsTabView(monitor: monitor, uiState: uiState)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 440)

            Divider()

            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 344)
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text("SwiftyStats")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(monitor.topology.chipName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("\(StatsFormatter.compactBytesShort(monitor.totalMemoryBytes)) RAM")
                    Text("·")
                    Text("Actif \(StatsFormatter.uptime(monitor.cpu.uptimeSeconds))")
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rafraîchir maintenant")
        }
    }

    private var footerView: some View {
        HStack(spacing: 8) {
            if monitor.memory.selfFootprintBytes > 0 {
                Text("App : \(StatsFormatter.compactBytesShort(monitor.memory.selfFootprintBytes))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                openActivityMonitor()
            } label: {
                Label("Activité", systemImage: "waveform.path.ecg")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Ouvrir le Moniteur d'activité")

            Button(role: .destructive) {
                onQuit()
            } label: {
                Text("Quitter")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
