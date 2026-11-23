import AppKit
import SwiftUI
import SwiftyStatsCore

struct SettingsTabView: View {
    let monitor: SystemMonitor
    let uiState: PopoverUIState

    private let intervals: [(label: String, value: TimeInterval)] = [
        ("1s", 1.0),
        ("2s", 2.0),
        ("3s", 3.0),
        ("5s", 5.0),
    ]

    var body: some View {
        let settings = monitor.settings

        VStack(spacing: 8) {
            livePreviewCard
            metricsCard(settings: settings)
            formattingCard(settings: settings)
            appearanceCard(settings: settings)
            systemCard(settings: settings)
        }
        .onAppear {
            uiState.launchAtLogin = settings.isLaunchAtLoginEnabled
        }
    }

    // MARK: - Live Menu Bar Preview

    private var livePreviewCard: some View {
        let items = monitor.buildMenuBarItems(
            cpu: monitor.cpu,
            memory: monitor.memory,
            sensors: monitor.sensors
        )
        let previewOptions = MenuBarRenderer.RenderOptions(
            colorMode: monitor.settings.colorMode,
            density: monitor.settings.density,
            isDarkAppearance: true
        )
        let previewImage = MenuBarRenderer.render(items: items, options: previewOptions)

        return SectionCard {
            HStack {
                Label("Aperçu barre des menus", systemImage: "menubar.rectangle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(previewImage.size.width)) pt")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    if previewImage.isTemplate {
                        Image(nsImage: previewImage)
                            .renderingMode(.template)
                            .foregroundStyle(.white)
                    } else {
                        Image(nsImage: previewImage)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.24, blue: 0.36),
                            Color(red: 0.18, green: 0.30, blue: 0.44),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Metrics Toggles

    private func metricsCard(settings: SettingsStore) -> some View {
        SectionCard {
            Label("Métriques affichées", systemImage: "checklist")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                toggleRow("CPU (%)", isOn: Binding(
                    get: { settings.showCPU },
                    set: { settings.showCPU = $0 }
                ))
                toggleRow("RAM", isOn: Binding(
                    get: { settings.showRAM },
                    set: { settings.showRAM = $0 }
                ))
                toggleRow("Température CPU", isOn: Binding(
                    get: { settings.showTemperature },
                    set: { settings.showTemperature = $0 }
                ))
                toggleRow("Consommation (Watts)", isOn: Binding(
                    get: { settings.showPower },
                    set: { settings.showPower = $0 }
                ))
            }
        }
    }

    // MARK: - Formatting

    private func formattingCard(settings: SettingsStore) -> some View {
        SectionCard {
            Label("Format des valeurs", systemImage: "slider.horizontal.3")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                HStack {
                    Text("Affichage RAM")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.ramDisplayMode },
                        set: { settings.ramDisplayMode = $0 }
                    )) {
                        ForEach(RAMDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 110)
                }

                HStack {
                    Text("Unité température")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.temperatureUnit },
                        set: { settings.temperatureUnit = $0 }
                    )) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 110)
                }

                HStack {
                    Text("Calcul température")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.temperatureAggregation },
                        set: { settings.temperatureAggregation = $0 }
                    )) {
                        ForEach(TemperatureAggregation.allCases) { agg in
                            Text(agg.label).tag(agg)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 146)
                }
            }
        }
    }

    // MARK: - Appearance & Interval

    private func appearanceCard(settings: SettingsStore) -> some View {
        SectionCard {
            Label("Apparence & Fréquence", systemImage: "paintbrush")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                HStack {
                    Text("Couleurs")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.colorMode },
                        set: { settings.colorMode = $0 }
                    )) {
                        ForEach(MenuBarColorMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 168)
                }

                HStack {
                    Text("Espacement")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.density },
                        set: { settings.density = $0 }
                    )) {
                        ForEach(MenuBarDensity.allCases) { density in
                            Text(density.label).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 168)
                }

                HStack {
                    Text("Rafraîchissement")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.refreshInterval },
                        set: { settings.refreshInterval = $0 }
                    )) {
                        ForEach(intervals, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 168)
                }
            }
        }
    }

    // MARK: - System / Launch at Login

    private func systemCard(settings: SettingsStore) -> some View {
        SectionCard {
            Label("Système", systemImage: "gearshape")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { uiState.launchAtLogin },
                set: { newValue in
                    settings.setLaunchAtLogin(newValue)
                    uiState.launchAtLogin = settings.isLaunchAtLoginEnabled
                }
            )) {
                Text("Lancer au démarrage de macOS")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11.5))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}
