import Foundation
import IOKit

public struct CachedSMCKey: Sendable, Equatable {
    public let key: String
    public let keyCode: UInt32
    public let dataSize: UInt32
    public let dataType: String

    public init(key: String, keyCode: UInt32, dataSize: UInt32, dataType: String) {
        self.key = key
        self.keyCode = keyCode
        self.dataSize = dataSize
        self.dataType = dataType
    }
}

public struct DiscoveredSMCKeys: Sendable {
    public let cpuTempKeys: [CachedSMCKey]
    public let gpuTempKeys: [CachedSMCKey]
    public let socTempKeys: [CachedSMCKey]
    public let ssdTempKeys: [CachedSMCKey]
    public let batteryTempKeys: [CachedSMCKey]
    public let systemPowerKey: CachedSMCKey?
    public let dcInPowerKey: CachedSMCKey?
    public let batteryPowerKey: CachedSMCKey?
    public let socPowerKeys: [CachedSMCKey]
    public let fanCountKey: CachedSMCKey?
    public let fanKeys: [(actual: CachedSMCKey, min: CachedSMCKey?, max: CachedSMCKey?)]
}

public final class SMCReader: @unchecked Sendable {
    private struct SMCKeyData {
        struct Version {
            var major: CUnsignedChar = 0
            var minor: CUnsignedChar = 0
            var build: CUnsignedChar = 0
            var reserved: CUnsignedChar = 0
            var release: CUnsignedShort = 0
        }
        struct PLimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: IOByteCount32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        var key: UInt32 = 0
        var vers: Version = Version()
        var pLimitData: PLimitData = PLimitData()
        var keyInfo: KeyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private enum Selector {
        static let handleYPCEvent: UInt32 = 2
        static let readKey: UInt8 = 5
        static let getKeyFromIndex: UInt8 = 8
        static let getKeyInfo: UInt8 = 9
    }

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    public let discoveredKeys: DiscoveredSMCKeys

    public var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != 0
    }

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var conn: io_connect_t = 0
            if IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS {
                self.connection = conn
            }
        }
        self.discoveredKeys = Self.discoverKeys(connection: self.connection)
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func readValue(for key: CachedSMCKey) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }
        return Self.readCachedKeyLocked(connection: connection, cached: key)
    }

    public func readValues(for keys: [CachedSMCKey], validRange: ClosedRange<Double>? = nil) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return [] }
        var values: [Double] = []
        values.reserveCapacity(keys.count)
        for key in keys {
            if let value = Self.readCachedKeyLocked(connection: connection, cached: key) {
                if let range = validRange, !range.contains(value) {
                    continue
                }
                values.append(value)
            }
        }
        return values
    }

    // MARK: - Pure Encoding / Decoding Helpers (Unit-Testable)

    public static func fourCC(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in s.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    public static func fromFourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func decodeValue(dataType: String, dataSize: UInt32, bytes: [UInt8]) -> Double? {
        guard bytes.count >= Int(dataSize) else { return nil }
        switch (dataType, dataSize) {
        case ("flt ", 4):
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Float(bitPattern: bits)
            return value.isFinite ? Double(value) : nil

        case ("sp78", 2):
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0

        case ("sp87", 2):
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 128.0

        case ("fpe2", 2):
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0

        case ("ui8 ", 1):
            return Double(bytes[0])

        case ("ui16", 2):
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)

        case ("ui32", 4):
            let raw = (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return Double(raw)

        case ("ioft", 8):
            let raw = UInt64(bytes[0])
                | (UInt64(bytes[1]) << 8)
                | (UInt64(bytes[2]) << 16)
                | (UInt64(bytes[3]) << 24)
                | (UInt64(bytes[4]) << 32)
                | (UInt64(bytes[5]) << 40)
                | (UInt64(bytes[6]) << 48)
                | (UInt64(bytes[7]) << 56)
            return Double(raw) / 65536.0

        default:
            return nil
        }
    }

    // MARK: - Private Low-Level IOKit SMC Access

    private static func callSMC(connection: io_connect_t, input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            Selector.handleYPCEvent,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard kr == KERN_SUCCESS else { return nil }
        return output
    }

    private static func keyInfo(connection: io_connect_t, key: String) -> CachedSMCKey? {
        let code = fourCC(key)
        var input = SMCKeyData()
        input.key = code
        input.data8 = Selector.getKeyInfo
        guard let output = callSMC(connection: connection, input: &input), output.result == 0 else {
            return nil
        }
        return CachedSMCKey(
            key: key,
            keyCode: code,
            dataSize: output.keyInfo.dataSize,
            dataType: fromFourCC(output.keyInfo.dataType)
        )
    }

    private static func readCachedKeyLocked(connection: io_connect_t, cached: CachedSMCKey) -> Double? {
        var input = SMCKeyData()
        input.key = cached.keyCode
        input.keyInfo.dataSize = cached.dataSize
        input.data8 = Selector.readKey
        guard let output = callSMC(connection: connection, input: &input), output.result == 0 else {
            return nil
        }
        let rawBytes = withUnsafeBytes(of: output.bytes) { Array($0) }
        return decodeValue(dataType: cached.dataType, dataSize: cached.dataSize, bytes: rawBytes)
    }

    private static func discoverKeys(connection: io_connect_t) -> DiscoveredSMCKeys {
        guard connection != 0 else {
            return DiscoveredSMCKeys(
                cpuTempKeys: [],
                gpuTempKeys: [],
                socTempKeys: [],
                ssdTempKeys: [],
                batteryTempKeys: [],
                systemPowerKey: nil,
                dcInPowerKey: nil,
                batteryPowerKey: nil,
                socPowerKeys: [],
                fanCountKey: nil,
                fanKeys: []
            )
        }

        // Fast direct lookups for well-known power & fan keys
        let systemPowerKey = keyInfo(connection: connection, key: "PSTR")
        let dcInPowerKey = keyInfo(connection: connection, key: "PDTR")
        let batteryPowerKey = keyInfo(connection: connection, key: "PPBR")
        let socPowerCandidates = ["PHPC", "PHPM", "PHPS", "PTHS", "PPMC", "PPSC"]
        let socPowerKeys = socPowerCandidates.compactMap { keyInfo(connection: connection, key: $0) }

        let fanCountKey = keyInfo(connection: connection, key: "FNum")
        var fanKeys: [(actual: CachedSMCKey, min: CachedSMCKey?, max: CachedSMCKey?)] = []
        if let fNumKey = fanCountKey, let fanCount = readCachedKeyLocked(connection: connection, cached: fNumKey) {
            let n = min(8, max(0, Int(fanCount.rounded())))
            for i in 0..<n {
                if let actual = keyInfo(connection: connection, key: "F\(i)Ac") {
                    let minK = keyInfo(connection: connection, key: "F\(i)Mn")
                    let maxK = keyInfo(connection: connection, key: "F\(i)Mx")
                    fanKeys.append((actual, minK, maxK))
                }
            }
        }

        // Enumerate SMC keys once to dynamically discover all CPU/GPU/SoC/SSD/Battery thermal sensors
        // across M1, M2, M3, M4, M5 and Intel Macs.
        var cpuKeys: [CachedSMCKey] = []
        var intelCpuKeys: [CachedSMCKey] = []
        var gpuKeys: [CachedSMCKey] = []
        var socKeys: [CachedSMCKey] = []
        var ssdKeys: [CachedSMCKey] = []
        var batteryKeys: [CachedSMCKey] = []

        if let countKey = keyInfo(connection: connection, key: "#KEY"),
           let totalCount = readCachedKeyLocked(connection: connection, cached: countKey) {
            let count = min(10_000, max(0, Int(totalCount)))
            for idx in 0..<count {
                var input = SMCKeyData()
                input.data8 = Selector.getKeyFromIndex
                input.data32 = UInt32(idx)
                guard let output = callSMC(connection: connection, input: &input), output.result == 0 else {
                    continue
                }
                let name = fromFourCC(output.key)
                guard name.first == "T" else { continue }

                let category = classifyTempKey(name)
                guard let category else { continue }
                guard let info = keyInfo(connection: connection, key: name) else { continue }
                // Validate that sensor currently yields a sane temperature reading (10°C..125°C)
                guard let val = readCachedKeyLocked(connection: connection, cached: info),
                      (10.0...125.0).contains(val) else {
                    continue
                }

                switch category {
                case .appleSiliconCPU: cpuKeys.append(info)
                case .intelCPU: intelCpuKeys.append(info)
                case .gpu: gpuKeys.append(info)
                case .soc: socKeys.append(info)
                case .ssd: ssdKeys.append(info)
                case .battery: batteryKeys.append(info)
                }
            }
        }

        let resolvedCPUKeys = cpuKeys.isEmpty ? intelCpuKeys : cpuKeys
        return DiscoveredSMCKeys(
            cpuTempKeys: resolvedCPUKeys,
            gpuTempKeys: gpuKeys,
            socTempKeys: socKeys,
            ssdTempKeys: ssdKeys,
            batteryTempKeys: batteryKeys,
            systemPowerKey: systemPowerKey,
            dcInPowerKey: dcInPowerKey,
            batteryPowerKey: batteryPowerKey,
            socPowerKeys: socPowerKeys,
            fanCountKey: fanCountKey,
            fanKeys: fanKeys
        )
    }

    private enum TempCategory {
        case appleSiliconCPU
        case intelCPU
        case gpu
        case soc
        case ssd
        case battery
    }

    private static func classifyTempKey(_ key: String) -> TempCategory? {
        guard key.count == 4 else { return nil }
        // Apple Silicon CPU die sensors: Tp0*, Tp1*, Tp2* (M1-M5)
        if key.hasPrefix("Tp0") || key.hasPrefix("Tp1") || key.hasPrefix("Tp2") {
            return .appleSiliconCPU
        }
        // Fallback CPU sensors (M1 E-core / Intel)
        if key.hasPrefix("Tc0") || key.hasPrefix("TC0") || key.hasPrefix("TC1") {
            return .intelCPU
        }
        // Apple Silicon GPU die sensors: Tg0*..Tg4*
        if key.hasPrefix("Tg0") || key.hasPrefix("Tg1") || key.hasPrefix("Tg2")
            || key.hasPrefix("Tg3") || key.hasPrefix("Tg4") {
            return .gpu
        }
        // SoC sensors: Ts0* excluding palm rest Ts0P/Ts1P, plus ANE Ta0*
        if (key.hasPrefix("Ts0") && key != "Ts0P") || key.hasPrefix("Ta0") {
            return .soc
        }
        // SSD / NAND sensors
        if key.hasPrefix("TH0") || key.hasPrefix("TN0") {
            return .ssd
        }
        // Battery temperature sensors
        if key == "TB0T" || key == "TB1T" || key == "TB2T" {
            return .battery
        }
        return nil
    }
}
