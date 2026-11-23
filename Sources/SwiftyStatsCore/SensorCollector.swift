import Foundation
import IOKit.ps

public final class SensorCollector: Sendable {
    private let smc: SMCReader
    private let hidFallback: IOHIDTempFallback?

    public init(smc: SMCReader = SMCReader()) {
        self.smc = smc
        self.hidFallback = smc.discoveredKeys.cpuTempKeys.isEmpty ? IOHIDTempFallback() : nil
    }

    /// Ultra-lightweight sampling for menu bar updates while popover is closed.
    public func sampleCompact(includeTemperature: Bool, includePower: Bool) -> SensorSnapshot {
        var cpuAvg: Double?
        var cpuMax: Double?
        var cpuMin: Double?

        if includeTemperature {
            let temps = readCPUTemperatures()
            if !temps.isEmpty {
                cpuAvg = temps.reduce(0, +) / Double(temps.count)
                cpuMax = temps.max()
                cpuMin = temps.min()
            }
        }

        var sysPower: Double?
        if includePower, let key = smc.discoveredKeys.systemPowerKey {
            if let val = smc.readValue(for: key), val >= 0, val < 400 {
                sysPower = val
            }
        }

        return SensorSnapshot(
            cpuTempAverageC: cpuAvg,
            cpuTempMaxC: cpuMax,
            cpuTempMinC: cpuMin,
            systemPowerWatts: sysPower
        )
    }

    /// Full sensor sampling while popover is visible.
    public func sampleFull() -> SensorSnapshot {
        let keys = smc.discoveredKeys

        let cpuTemps = readCPUTemperatures()
        let cpuAvg = cpuTemps.isEmpty ? nil : (cpuTemps.reduce(0, +) / Double(cpuTemps.count))
        let cpuMax = cpuTemps.max()
        let cpuMin = cpuTemps.min()

        let gpuTemps = smc.readValues(for: keys.gpuTempKeys, validRange: 10...125)
        let gpuAvg = gpuTemps.isEmpty ? nil : (gpuTemps.reduce(0, +) / Double(gpuTemps.count))

        let socTemps = smc.readValues(for: keys.socTempKeys, validRange: 10...125)
        let socAvg = socTemps.isEmpty ? nil : (socTemps.reduce(0, +) / Double(socTemps.count))

        let ssdTemps = smc.readValues(for: keys.ssdTempKeys, validRange: 10...125)
        let ssdAvg = ssdTemps.isEmpty ? nil : (ssdTemps.reduce(0, +) / Double(ssdTemps.count))

        let battTemps = smc.readValues(for: keys.batteryTempKeys, validRange: 5...90)
        let battAvg = battTemps.isEmpty ? nil : (battTemps.reduce(0, +) / Double(battTemps.count))

        let sysPower = keys.systemPowerKey.flatMap { smc.readValue(for: $0) }.flatMap { (0...400).contains($0) ? $0 : nil }
        let dcPower = keys.dcInPowerKey.flatMap { smc.readValue(for: $0) }.flatMap { (0...400).contains($0) ? $0 : nil }
        let battPower = keys.batteryPowerKey.flatMap { smc.readValue(for: $0) }.flatMap { (0...400).contains($0) ? $0 : nil }

        var powerRails: [NamedSensorReading] = []
        if let sysPower {
            powerRails.append(NamedSensorReading(id: "PSTR", name: "Système total", value: sysPower))
        }
        if let dcPower, dcPower > 0.05 {
            powerRails.append(NamedSensorReading(id: "PDTR", name: "Adaptateur secteur", value: dcPower))
        }
        if let battPower, battPower > 0.05 {
            powerRails.append(NamedSensorReading(id: "PPBR", name: "Batterie", value: battPower))
        }

        var socRailsSum: Double = 0
        var socRailsCount = 0
        let railNames: [String: String] = [
            "PHPC": "SoC (CPU/GPU)",
            "PHPM": "Mémoire / PMIC",
            "PHPS": "Sous-système SoC",
            "PTHS": "Système thermique",
            "PPMC": "Package CPU",
            "PPSC": "Package SoC",
        ]
        for key in keys.socPowerKeys {
            if let val = smc.readValue(for: key), val >= 0.01, val < 300 {
                if key.key == "PHPC" || key.key == "PHPM" || key.key == "PHPS" {
                    socRailsSum += val
                    socRailsCount += 1
                }
                powerRails.append(
                    NamedSensorReading(
                        id: key.key,
                        name: railNames[key.key] ?? key.key,
                        value: val
                    )
                )
            }
        }
        let socPower: Double? = socRailsCount > 0 ? socRailsSum : nil

        var tempGroups: [NamedSensorReading] = []
        if let cpuAvg { tempGroups.append(NamedSensorReading(id: "cpu_avg", name: "CPU (moyenne)", value: cpuAvg)) }
        if let cpuMax { tempGroups.append(NamedSensorReading(id: "cpu_max", name: "CPU (pic max)", value: cpuMax)) }
        if let gpuAvg { tempGroups.append(NamedSensorReading(id: "gpu_avg", name: "GPU (moyenne)", value: gpuAvg)) }
        if let socAvg { tempGroups.append(NamedSensorReading(id: "soc_avg", name: "SoC / ANE", value: socAvg)) }
        if let ssdAvg { tempGroups.append(NamedSensorReading(id: "ssd_avg", name: "SSD / NAND", value: ssdAvg)) }
        if let battAvg { tempGroups.append(NamedSensorReading(id: "batt_avg", name: "Batterie", value: battAvg)) }

        var fans: [FanReading] = []
        for (idx, fan) in keys.fanKeys.enumerated() {
            let current = max(0, smc.readValue(for: fan.actual) ?? 0)
            let minRPM = max(0, fan.min.flatMap { smc.readValue(for: $0) } ?? 0)
            let maxRPM = max(0, fan.max.flatMap { smc.readValue(for: $0) } ?? 6000)
            let fanName = keys.fanKeys.count == 1 ? "Ventilateur" : (idx == 0 ? "Ventilateur gauche" : "Ventilateur droit")
            fans.append(FanReading(id: idx, name: fanName, currentRPM: current, minRPM: minRPM, maxRPM: maxRPM))
        }

        let battery = Self.readBatterySnapshot()

        return SensorSnapshot(
            cpuTempAverageC: cpuAvg,
            cpuTempMaxC: cpuMax,
            cpuTempMinC: cpuMin,
            gpuTempAverageC: gpuAvg,
            socTempAverageC: socAvg,
            ssdTempAverageC: ssdAvg,
            batteryTempC: battAvg,
            systemPowerWatts: sysPower,
            dcInPowerWatts: dcPower,
            batteryPowerWatts: battPower,
            socPowerWatts: socPower,
            fans: fans,
            battery: battery,
            temperatureGroups: tempGroups,
            powerRails: powerRails
        )
    }

    private func readCPUTemperatures() -> [Double] {
        let smcTemps = smc.readValues(for: smc.discoveredKeys.cpuTempKeys, validRange: 10...125)
        if !smcTemps.isEmpty {
            return smcTemps
        }
        return hidFallback?.readDieTemperatures() ?? []
    }

    private static func readBatterySnapshot() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return BatterySnapshot(isPresent: false)
        }

        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = maxCap > 0 ? min(100, max(0, (current * 100) / maxCap)) : current
            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String
            let isOnAC = powerSourceState == kIOPSACPowerValue

            var timeMinutes: Int?
            if isCharging {
                if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0 {
                    timeMinutes = t
                }
            } else if !isOnAC {
                if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 {
                    timeMinutes = t
                }
            }

            return BatterySnapshot(
                isPresent: true,
                chargePercent: pct,
                isCharging: isCharging,
                isOnACPower: isOnAC,
                timeRemainingMinutes: timeMinutes
            )
        }

        return BatterySnapshot(isPresent: false)
    }
}
