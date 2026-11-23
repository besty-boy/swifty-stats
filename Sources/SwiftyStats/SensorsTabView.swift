import SwiftUI
import SwiftyStatsCore

struct SensorsTabView: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 8) {
            temperaturesCard
            powerRailsCard
            fansCard
            if monitor.sensors.battery.isPresent {
                batteryCard
            }
        }
    }

    private var temperaturesCard: some View {
        SectionCard {
            Label("Températures", systemImage: "thermometer.sun")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            if monitor.sensors.temperatureGroups.isEmpty {
                Text("Aucun capteur thermique détecté.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 6) {
                    ForEach(monitor.sensors.temperatureGroups) { sensor in
                        VStack(spacing: 3) {
                            HStack {
                                Text(sensor.name)
                                    .font(.system(size: 11))
                                Spacer()
                                Text(StatsFormatter.temperatureDetailed(sensor.value, unit: monitor.settings.temperatureUnit))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(tempColor(sensor.value))
                            }
                            GeometryReader { geo in
                                let fraction = min(1.0, max(0.04, (sensor.value - 20.0) / 80.0))
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(tempColor(sensor.value).opacity(0.85))
                                        .frame(width: geo.size.width * CGFloat(fraction))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
    }

    private var powerRailsCard: some View {
        SectionCard {
            Label("Alimentation & Rails", systemImage: "bolt.circle")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            if monitor.sensors.powerRails.isEmpty {
                Text("Aucun capteur de puissance détecté.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 5) {
                    ForEach(monitor.sensors.powerRails) { rail in
                        HStack {
                            Text(rail.name)
                                .font(.system(size: 11))
                            Text(rail.id)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(StatsFormatter.wattsDetailed(rail.value))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private var fansCard: some View {
        SectionCard {
            Label("Ventilateurs", systemImage: "fan")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            if monitor.sensors.fans.isEmpty {
                Text("Refroidissement passif (sans ventilateur)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(monitor.sensors.fans) { fan in
                        VStack(spacing: 3) {
                            HStack {
                                Text(fan.name)
                                    .font(.system(size: 11))
                                Spacer()
                                if fan.currentRPM < 10 {
                                    Text("Arrêté · 0 RPM")
                                        .font(.system(size: 10.5).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(Int(fan.currentRPM.rounded())) / \(Int(fan.maxRPM.rounded())) RPM")
                                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(Color.cyan)
                                        .frame(width: geo.size.width * CGFloat(fan.percent / 100.0))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
    }

    private var batteryCard: some View {
        let batt = monitor.sensors.battery
        return SectionCard {
            HStack {
                Label("Batterie", systemImage: batt.isCharging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(batt.chargePercent)%")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
            }
            HStack {
                Text(batt.isCharging ? "En charge" : (batt.isOnACPower ? "Sur secteur" : "Sur batterie"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if let rem = StatsFormatter.batteryTimeRemaining(batt.timeRemainingMinutes) {
                    Text(batt.isCharging ? "Pleine dans \(rem)" : "Restant : \(rem)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tempColor(_ celsius: Double) -> Color {
        if celsius >= 85 { return .red }
        if celsius >= 68 { return .orange }
        if celsius >= 50 { return .yellow }
        return .green
    }
}
