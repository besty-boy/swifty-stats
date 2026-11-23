import Foundation

// MARK: - Ring Buffer

public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element]
    private var head: Int = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    public var values: [Element] {
        guard storage.count == capacity, head != 0 else {
            return storage
        }
        return Array(storage[head...]) + Array(storage[..<head])
    }

    public var latest: Element? {
        guard !storage.isEmpty else { return nil }
        if storage.count < capacity {
            return storage.last
        }
        let idx = (head - 1 + capacity) % capacity
        return storage[idx]
    }
}

// MARK: - CPU

public struct CoreClusterInfo: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct CPUTopology: Sendable, Equatable {
    public let chipName: String
    public let totalCores: Int
    public let clusters: [CoreClusterInfo]

    public init(chipName: String, totalCores: Int, clusters: [CoreClusterInfo]) {
        self.chipName = chipName
        self.totalCores = totalCores
        self.clusters = clusters
    }
}

public struct CPUSnapshot: Sendable, Equatable {
    public let totalPercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let perCorePercent: [Double]
    public let loadAverage: (one: Double, five: Double, fifteen: Double)
    public let uptimeSeconds: TimeInterval

    public init(
        totalPercent: Double = 0,
        userPercent: Double = 0,
        systemPercent: Double = 0,
        idlePercent: Double = 100,
        perCorePercent: [Double] = [],
        loadAverage: (one: Double, five: Double, fifteen: Double) = (0, 0, 0),
        uptimeSeconds: TimeInterval = 0
    ) {
        self.totalPercent = totalPercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.perCorePercent = perCorePercent
        self.loadAverage = loadAverage
        self.uptimeSeconds = uptimeSeconds
    }

    public static func == (lhs: CPUSnapshot, rhs: CPUSnapshot) -> Bool {
        lhs.totalPercent == rhs.totalPercent &&
        lhs.userPercent == rhs.userPercent &&
        lhs.systemPercent == rhs.systemPercent &&
        lhs.idlePercent == rhs.idlePercent &&
        lhs.perCorePercent == rhs.perCorePercent &&
        lhs.loadAverage.one == rhs.loadAverage.one &&
        lhs.loadAverage.five == rhs.loadAverage.five &&
        lhs.loadAverage.fifteen == rhs.loadAverage.fifteen &&
        lhs.uptimeSeconds == rhs.uptimeSeconds
    }
}

// MARK: - Memory

public enum MemoryPressureLevel: Int, Sendable, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4

    public var label: String {
        switch self {
        case .normal: return "Normale"
        case .warning: return "Élevée"
        case .critical: return "Critique"
        }
    }
}

public struct MemorySnapshot: Sendable, Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let appBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressure: MemoryPressureLevel
    public let selfFootprintBytes: UInt64

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, (Double(usedBytes) / Double(totalBytes)) * 100.0))
    }

    public init(
        totalBytes: UInt64 = 0,
        usedBytes: UInt64 = 0,
        appBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        cachedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0,
        pressure: MemoryPressureLevel = .normal,
        selfFootprintBytes: UInt64 = 0
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
        self.selfFootprintBytes = selfFootprintBytes
    }
}

// MARK: - Sensors (Thermal, Power, Fans, Battery)

public struct NamedSensorReading: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let value: Double

    public init(id: String, name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }
}

public struct FanReading: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let currentRPM: Double
    public let minRPM: Double
    public let maxRPM: Double

    public var percent: Double {
        guard maxRPM > 0 else { return 0 }
        return min(100, max(0, (currentRPM / maxRPM) * 100.0))
    }

    public init(id: Int, name: String, currentRPM: Double, minRPM: Double, maxRPM: Double) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public struct BatterySnapshot: Sendable, Equatable {
    public let isPresent: Bool
    public let chargePercent: Int
    public let isCharging: Bool
    public let isOnACPower: Bool
    public let timeRemainingMinutes: Int?

    public init(
        isPresent: Bool = false,
        chargePercent: Int = 0,
        isCharging: Bool = false,
        isOnACPower: Bool = false,
        timeRemainingMinutes: Int? = nil
    ) {
        self.isPresent = isPresent
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isOnACPower = isOnACPower
        self.timeRemainingMinutes = timeRemainingMinutes
    }
}

public struct SensorSnapshot: Sendable, Equatable {
    public let cpuTempAverageC: Double?
    public let cpuTempMaxC: Double?
    public let cpuTempMinC: Double?
    public let gpuTempAverageC: Double?
    public let socTempAverageC: Double?
    public let ssdTempAverageC: Double?
    public let batteryTempC: Double?
    public let systemPowerWatts: Double?
    public let dcInPowerWatts: Double?
    public let batteryPowerWatts: Double?
    public let socPowerWatts: Double?
    public let fans: [FanReading]
    public let battery: BatterySnapshot
    public let temperatureGroups: [NamedSensorReading]
    public let powerRails: [NamedSensorReading]

    public init(
        cpuTempAverageC: Double? = nil,
        cpuTempMaxC: Double? = nil,
        cpuTempMinC: Double? = nil,
        gpuTempAverageC: Double? = nil,
        socTempAverageC: Double? = nil,
        ssdTempAverageC: Double? = nil,
        batteryTempC: Double? = nil,
        systemPowerWatts: Double? = nil,
        dcInPowerWatts: Double? = nil,
        batteryPowerWatts: Double? = nil,
        socPowerWatts: Double? = nil,
        fans: [FanReading] = [],
        battery: BatterySnapshot = BatterySnapshot(),
        temperatureGroups: [NamedSensorReading] = [],
        powerRails: [NamedSensorReading] = []
    ) {
        self.cpuTempAverageC = cpuTempAverageC
        self.cpuTempMaxC = cpuTempMaxC
        self.cpuTempMinC = cpuTempMinC
        self.gpuTempAverageC = gpuTempAverageC
        self.socTempAverageC = socTempAverageC
        self.ssdTempAverageC = ssdTempAverageC
        self.batteryTempC = batteryTempC
        self.systemPowerWatts = systemPowerWatts
        self.dcInPowerWatts = dcInPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.socPowerWatts = socPowerWatts
        self.fans = fans
        self.battery = battery
        self.temperatureGroups = temperatureGroups
        self.powerRails = powerRails
    }
}

// MARK: - Processes

public struct ProcessItem: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(id: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct ProcessSnapshot: Sendable, Equatable {
    public let topByCPU: [ProcessItem]
    public let topByMemory: [ProcessItem]

    public init(topByCPU: [ProcessItem] = [], topByMemory: [ProcessItem] = []) {
        self.topByCPU = topByCPU
        self.topByMemory = topByMemory
    }
}

// MARK: - Menu Bar Lightweight Payload

public enum MetricSeverity: Int, Sendable, Equatable {
    case normal = 0
    case elevated = 1
    case critical = 2
}

public struct MenuBarItemDisplay: Sendable, Equatable {
    public let label: String
    public let value: String
    public let minWidth: CGFloat
    public let severity: MetricSeverity
    public let metric: MenuBarMetric

    public init(
        label: String,
        value: String,
        minWidth: CGFloat,
        severity: MetricSeverity,
        metric: MenuBarMetric
    ) {
        self.label = label
        self.value = value
        self.minWidth = minWidth
        self.severity = severity
        self.metric = metric
    }
}
