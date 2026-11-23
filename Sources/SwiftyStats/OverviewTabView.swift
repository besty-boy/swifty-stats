import SwiftUI
import SwiftyStatsCore

struct OverviewTabView: View {
    let monitor: SystemMonitor
    let uiState: PopoverUIState

    var body: some View {
        VStack(spacing: 8) {
            cpuCard
            memoryCard
            thermalPowerCard
            processesCard
        }
    }

    // MARK: - CPU Card

    private var cpuCard: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(StatsFormatter.percentOneDecimal(monitor.cpu.totalPercent))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(severityColor(StatsFormatter.cpuSeverity(monitor.cpu.totalPercent), default: .primary))
            }

            HStack(spacing: 12) {
                metricDot(color: .blue, label: "Util.", value: StatsFormatter.percentOneDecimal(monitor.cpu.userPercent))
                metricDot(color: .red.opacity(0.85), label: "Syst.", value: StatsFormatter.percentOneDecimal(monitor.cpu.systemPercent))
                Spacer()
                Text(
                    String(
                        format: "Charge %.2f · %.2f · %.2f",
                        monitor.cpu.loadAverage.one,
                        monitor.cpu.loadAverage.five,
                        monitor.cpu.loadAverage.fifteen
                    )
                )
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            SparklineView(
                values: monitor.cpuHistory,
                minValue: 0,
                maxValue: 100,
                color: .blue,
                height: 30
            )

            if !monitor.cpu.perCorePercent.isEmpty {
                coreBarsView
            }
        }
    }

    private var coreBarsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(Array(monitor.cpu.perCorePercent.enumerated()), id: \.offset) { idx, pct in
                    GeometryReader { geo in
                        let fillH = max(2, geo.size.height * CGFloat(min(100, max(0, pct)) / 100.0))
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(coreBarColor(index: idx, percent: pct))
                                .frame(height: fillH)
                        }
                    }
                    .frame(height: 16)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
            }

            if !monitor.topology.clusters.isEmpty {
                HStack(spacing: 8) {
                    ForEach(monitor.topology.clusters) { cluster in
                        Text("\(cluster.count) \(cluster.name)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(monitor.topology.totalCores) cœurs")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func coreBarColor(index: Int, percent: Double) -> Color {
        if percent >= 85 { return .red }
        if percent >= 60 { return .orange }
        let firstClusterCount = monitor.topology.clusters.first?.count ?? 0
        return index < firstClusterCount ? .blue : .cyan
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        SectionCard {
            HStack(alignment: .firstTextBaseline) {
                Label("Mémoire", systemImage: "memorychip")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                pressureBadge(monitor.memory.pressure)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(StatsFormatter.percentInt(monitor.memory.usedPercent))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundStyle(
                            severityColor(
                                StatsFormatter.ramSeverity(monitor.memory.usedPercent, pressure: monitor.memory.pressure),
                                default: .primary
                            )
                        )
                    Text("\(StatsFormatter.compactBytesShort(monitor.memory.usedBytes)) / \(StatsFormatter.compactBytesShort(monitor.memory.totalBytes))")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            SegmentedMemoryBar(
                total: monitor.memory.totalBytes,
                app: monitor.memory.appBytes,
                wired: monitor.memory.wiredBytes,
                compressed: monitor.memory.compressedBytes,
                cached: monitor.memory.cachedBytes
            )

            HStack(spacing: 6) {
                metricDot(color: .purple, label: "App", value: StatsFormatter.compactGB(monitor.memory.appBytes))
                metricDot(color: .orange, label: "Câbl.", value: StatsFormatter.compactGB(monitor.memory.wiredBytes))
                metricDot(color: .cyan, label: "Comp.", value: StatsFormatter.compactGB(monitor.memory.compressedBytes))
                Spacer(minLength: 4)
                if monitor.memory.swapUsedBytes > 0 {
                    Text("Swap \(StatsFormatter.compactGB(monitor.memory.swapUsedBytes))")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            SparklineView(
                values: monitor.memoryHistory,
                minValue: 0,
                maxValue: 100,
                color: .purple,
                height: 26
            )
        }
    }

    private func pressureBadge(_ pressure: MemoryPressureLevel) -> some View {
        let color: Color = {
            switch pressure {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }()
        return Text(pressure.label)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    // MARK: - Thermal & Power Card

    private var thermalPowerCard: some View {
        SectionCard {
            HStack(alignment: .center) {
                Label("Thermique & Énergie", systemImage: "thermometer.medium")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { uiState.thermalChartMode },
                    set: { uiState.thermalChartMode = $0 }
                )) {
                    ForEach(PopoverUIState.ThermalChartMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 68)
            }

            HStack(spacing: 10) {
                // Temperature column
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU Temp")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    let displayTemp = monitor.selectedTemperatureC(from: monitor.sensors)
                    Text(StatsFormatter.temperatureDetailed(displayTemp, unit: monitor.settings.temperatureUnit))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(severityColor(StatsFormatter.tempSeverity(displayTemp), default: .primary))
                    HStack(spacing: 6) {
                        if let maxT = monitor.sensors.cpuTempMaxC {
                            Text("Pic \(StatsFormatter.temperatureCompact(maxT, unit: monitor.settings.temperatureUnit))")
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let gpuT = monitor.sensors.gpuTempAverageC {
                            Text("GPU \(StatsFormatter.temperatureCompact(gpuT, unit: monitor.settings.temperatureUnit))")
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 36)

                // Power & Fans column
                VStack(alignment: .leading, spacing: 2) {
                    Text("Puissance")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(StatsFormatter.wattsDetailed(monitor.sensors.systemPowerWatts))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(severityColor(StatsFormatter.powerSeverity(monitor.sensors.systemPowerWatts), default: .primary))

                    HStack(spacing: 6) {
                        if monitor.sensors.battery.isPresent {
                            let batt = monitor.sensors.battery
                            let icon = batt.isCharging ? "bolt.fill" : (batt.isOnACPower ? "powerplug.fill" : "battery.75")
                            HStack(spacing: 2) {
                                Image(systemName: icon)
                                    .font(.system(size: 8.5))
                                Text("\(batt.chargePercent)%")
                                if let rem = StatsFormatter.batteryTimeRemaining(batt.timeRemainingMinutes) {
                                    Text("· \(rem)")
                                }
                            }
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                        } else {
                            fanSummaryText
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !monitor.sensors.fans.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "fan.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    fanSummaryText
                    Spacer()
                    if let ssdT = monitor.sensors.ssdTempAverageC {
                        Text("SSD \(StatsFormatter.temperatureCompact(ssdT, unit: monitor.settings.temperatureUnit))")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if uiState.thermalChartMode == .temperature {
                let temps = monitor.temperatureHistory
                let maxT = max(75.0, (temps.max() ?? 50.0) + 10.0)
                SparklineView(
                    values: temps,
                    minValue: 20,
                    maxValue: maxT,
                    color: .orange,
                    height: 26
                )
            } else {
                let watts = monitor.powerHistory
                let maxW = max(25.0, (watts.max() ?? 15.0) * 1.25)
                SparklineView(
                    values: watts,
                    minValue: 0,
                    maxValue: maxW,
                    color: .green,
                    height: 26
                )
            }
        }
    }

    private var fanSummaryText: some View {
        let maxRPM = monitor.sensors.fans.map(\.currentRPM).max() ?? 0
        return Group {
            if maxRPM < 10 {
                Text("Ventilateurs silencieux (0 RPM)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            } else {
                let text = monitor.sensors.fans
                    .map { "\(Int($0.currentRPM.rounded())) RPM" }
                    .joined(separator: " · ")
                Text(text)
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Top Processes Card

    private var processesCard: some View {
        SectionCard {
            HStack {
                Label("Top Processus", systemImage: "list.bullet.rectangle.portrait")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { uiState.processSortMode },
                    set: { uiState.processSortMode = $0 }
                )) {
                    ForEach(PopoverUIState.ProcessSortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 92)
            }

            let list = uiState.processSortMode == .cpu
                ? Array(monitor.processes.topByCPU.prefix(5))
                : Array(monitor.processes.topByMemory.prefix(5))

            if list.isEmpty {
                Text("Chargement des processus…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(list) { proc in
                        processRow(proc, mode: uiState.processSortMode)
                    }
                }
            }
        }
    }

    private func processRow(_ proc: ProcessItem, mode: PopoverUIState.ProcessSortMode) -> some View {
        HStack(spacing: 6) {
            Text(proc.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if mode == .cpu {
                Text(StatsFormatter.percentOneDecimal(proc.cpuPercent))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(proc.cpuPercent >= 50 ? .orange : .primary)
                    .frame(width: 46, alignment: .trailing)
                Text(StatsFormatter.compactBytesShort(proc.memoryBytes))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            } else {
                Text(StatsFormatter.compactBytesShort(proc.memoryBytes))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 52, alignment: .trailing)
                Text(StatsFormatter.percentOneDecimal(proc.cpuPercent))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func metricDot(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func severityColor(_ severity: MetricSeverity, default fallback: Color) -> Color {
        switch severity {
        case .normal: return fallback
        case .elevated: return .orange
        case .critical: return .red
        }
    }
}
