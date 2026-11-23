import Foundation
import Testing
@testable import SwiftyStatsCore

@Suite("SwiftyStatsCore")
struct SwiftyStatsCoreTests {

    @Test("RingBuffer maintains chronological order after wraparound")
    func ringBufferWraparound() {
        var buffer = RingBuffer<Int>(capacity: 3)
        #expect(buffer.isEmpty)
        buffer.append(10)
        buffer.append(20)
        #expect(buffer.values == [10, 20])
        #expect(buffer.latest == 20)

        buffer.append(30)
        #expect(buffer.values == [10, 20, 30])
        #expect(buffer.latest == 30)

        buffer.append(40)
        #expect(buffer.values == [20, 30, 40])
        #expect(buffer.latest == 40)

        buffer.append(50)
        buffer.append(60)
        #expect(buffer.values == [40, 50, 60])
        #expect(buffer.latest == 60)
    }

    @Test("CPUCollector computes accurate multi-core deltas")
    func cpuDeltaMath() {
        let prev = [
            CoreTicks(user: 100, system: 50, idle: 850, nice: 0),
            CoreTicks(user: 200, system: 100, idle: 700, nice: 0),
        ]
        let curr = [
            CoreTicks(user: 120, system: 60, idle: 920, nice: 0), // +20u, +10s, +70i = 30%
            CoreTicks(user: 250, system: 120, idle: 730, nice: 0), // +50u, +20s, +30i = 70%
        ]

        let result = CPUCollector.computeUsage(previous: prev, current: curr)
        #expect(abs(result.total - 50.0) < 0.001)
        #expect(abs(result.user - 35.0) < 0.001)
        #expect(abs(result.system - 15.0) < 0.001)
        #expect(abs(result.idle - 50.0) < 0.001)
        #expect(result.perCore.count == 2)
        #expect(abs(result.perCore[0] - 30.0) < 0.001)
        #expect(abs(result.perCore[1] - 70.0) < 0.001)
    }

    @Test("MemoryCollector computes Activity Monitor style used memory")
    func memoryMath() {
        let gb: UInt64 = 1024 * 1024 * 1024
        let pageSize: UInt64 = 16384
        let pagesPerGB = gb / pageSize

        let counts = VMPageCounts(
            pageSize: pageSize,
            internalPages: 10 * pagesPerGB,
            purgeablePages: 2 * pagesPerGB,   // app = 8 GB
            wiredPages: 3 * pagesPerGB,       // wired = 3 GB
            compressedPages: 1 * pagesPerGB,  // compressed = 1 GB -> used = 12 GB / 24 GB = 50%
            externalPages: 4 * pagesPerGB     // cached = 6 GB
        )

        let snap = MemoryCollector.computeSnapshot(
            totalBytes: 24 * gb,
            counts: counts,
            swapUsedBytes: gb / 2,
            swapTotalBytes: 2 * gb,
            pressure: .normal,
            selfFootprintBytes: 20 * 1024 * 1024
        )

        #expect(snap.appBytes == 8 * gb)
        #expect(snap.wiredBytes == 3 * gb)
        #expect(snap.compressedBytes == 1 * gb)
        #expect(snap.usedBytes == 12 * gb)
        #expect(snap.cachedBytes == 6 * gb)
        #expect(snap.freeBytes == 12 * gb)
        #expect(abs(snap.usedPercent - 50.0) < 0.001)
    }

    @Test("SMCReader FourCC and value decoders")
    func smcDecoders() {
        #expect(SMCReader.fromFourCC(SMCReader.fourCC("PSTR")) == "PSTR")
        #expect(SMCReader.fromFourCC(SMCReader.fourCC("Tp00")) == "Tp00")

        // flt (little endian IEEE 754 float 42.5)
        let fBits = Float(42.5).bitPattern
        let fBytes: [UInt8] = [
            UInt8(fBits & 0xFF),
            UInt8((fBits >> 8) & 0xFF),
            UInt8((fBits >> 16) & 0xFF),
            UInt8((fBits >> 24) & 0xFF),
        ]
        #expect(SMCReader.decodeValue(dataType: "flt ", dataSize: 4, bytes: fBytes) == 42.5)

        // sp78 (signed 7.8 fixed point: 35.5 = 9088 = 0x2380)
        #expect(SMCReader.decodeValue(dataType: "sp78", dataSize: 2, bytes: [0x23, 0x80]) == 35.5)

        // fpe2 (unsigned 14.2 fixed point: 2500.0 = 10000 = 0x2710)
        #expect(SMCReader.decodeValue(dataType: "fpe2", dataSize: 2, bytes: [0x27, 0x10]) == 2500.0)

        // ui8
        #expect(SMCReader.decodeValue(dataType: "ui8 ", dataSize: 1, bytes: [2]) == 2.0)

        // ui16
        #expect(SMCReader.decodeValue(dataType: "ui16", dataSize: 2, bytes: [0x01, 0x00]) == 256.0)

        // ioft (little endian Q48.16: 25.5 * 65536 = 1671168)
        let rawIOFT = UInt64(1_671_168)
        let ioftBytes = (0..<8).map { UInt8((rawIOFT >> ($0 * 8)) & 0xFF) }
        #expect(SMCReader.decodeValue(dataType: "ioft", dataSize: 8, bytes: ioftBytes) == 25.5)
    }

    @Test("ProcessCollector parses spaced names and sorts CPU & RAM")
    func processParsing() {
        let sample = """
          612   7.7 192480 WindowServer
        37829   6.9 501632 T3 Code (Beta) Helper (Renderer)
         6971   1.2 1127568 Discord Helper (Renderer)
         1455  14.3 164416 Stats
        """

        let parsed = ProcessCollector.parsePSOutput(sample, limit: 2)
        #expect(parsed.topByCPU.count == 2)
        #expect(parsed.topByCPU[0].name == "Stats")
        #expect(parsed.topByCPU[1].name == "WindowServer")

        #expect(parsed.topByMemory.count == 2)
        #expect(parsed.topByMemory[0].name == "Discord Helper (Renderer)")
        #expect(parsed.topByMemory[1].name == "T3 Code (Beta) Helper (Renderer)")
    }

    @Test("StatsFormatter formats metrics concisely")
    func formatting() {
        #expect(StatsFormatter.percentInt(3.4) == "3%")
        #expect(StatsFormatter.percentInt(56.6) == "57%")
        #expect(StatsFormatter.compactGB(14 * 1024 * 1024 * 1024) == "14.0G")
        #expect(StatsFormatter.temperatureCompact(31.2, unit: .celsius) == "31°")
        #expect(StatsFormatter.temperatureCompact(30.0, unit: .fahrenheit) == "86°")
        #expect(StatsFormatter.wattsCompact(7.24) == "7.2W")
        #expect(StatsFormatter.wattsCompact(18.6) == "19W")
        #expect(StatsFormatter.uptime(90060) == "1j 1h")
    }

    @Test("SettingsStore preserves at least one metric and persists to UserDefaults")
    @MainActor
    func settingsBehavior() {
        let suiteName = "com.swiftystats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.enabledMetrics == [.cpu, .ram, .temperature])

        store.showRAM = false
        store.showTemperature = false
        #expect(store.enabledMetrics == [.cpu])

        // Turning off the last metric should keep it enabled
        store.showCPU = false
        #expect(store.enabledMetrics == [.cpu])

        store.showPower = true
        store.ramDisplayMode = .usedGB
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.showPower == true)
        #expect(reloaded.ramDisplayMode == .usedGB)
    }

    @Test("Live hardware collectors return valid readings on this Mac")
    func liveHardwareCollectors() {
        let cpu = CPUCollector()
        #expect(cpu.topology.totalCores > 0)
        let cpuSnap = cpu.sample(includeExtras: true)
        #expect(cpuSnap.perCorePercent.count == cpu.topology.totalCores)
        #expect(cpuSnap.uptimeSeconds > 0)

        let mem = MemoryCollector()
        #expect(mem.totalBytes > 0)
        let memSnap = mem.sample(includeExtras: true)
        #expect(memSnap.usedBytes > 0)
        #expect(memSnap.usedPercent > 0 && memSnap.usedPercent <= 100)
        #expect(memSnap.selfFootprintBytes > 0)

        let sensors = SensorCollector()
        let full = sensors.sampleFull()
        #expect(full.cpuTempAverageC != nil)
        if let temp = full.cpuTempAverageC {
            #expect((15.0...115.0).contains(temp))
        }
        #expect(full.systemPowerWatts != nil)
    }
}
