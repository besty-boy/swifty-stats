import Darwin
import Foundation

public struct CoreTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public final class CPUCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: [CoreTicks] = []
    public let topology: CPUTopology

    public init() {
        self.topology = Self.readTopology()
        // Prime initial ticks so first sample already has a baseline
        self.previousTicks = Self.readRawCoreTicks()
    }

    public func sample(includeExtras: Bool) -> CPUSnapshot {
        let currentTicks = Self.readRawCoreTicks()

        let previous: [CoreTicks]
        lock.lock()
        previous = self.previousTicks
        self.previousTicks = currentTicks
        lock.unlock()

        let usage = Self.computeUsage(previous: previous, current: currentTicks)
        let load = includeExtras ? Self.readLoadAverage() : (0.0, 0.0, 0.0)
        let uptime = includeExtras ? Self.readUptime() : 0

        return CPUSnapshot(
            totalPercent: usage.total,
            userPercent: usage.user,
            systemPercent: usage.system,
            idlePercent: usage.idle,
            perCorePercent: usage.perCore,
            loadAverage: load,
            uptimeSeconds: uptime
        )
    }

    // MARK: - Pure Calculation (Unit-Testable)

    public static func computeUsage(
        previous: [CoreTicks],
        current: [CoreTicks]
    ) -> (total: Double, user: Double, system: Double, idle: Double, perCore: [Double]) {
        guard !current.isEmpty, previous.count == current.count else {
            return (0, 0, 0, 100, Array(repeating: 0, count: current.count))
        }

        var sumUser: UInt64 = 0
        var sumSystem: UInt64 = 0
        var sumNice: UInt64 = 0
        var sumIdle: UInt64 = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        for i in 0..<current.count {
            let prev = previous[i]
            let curr = current[i]
            let dUser = UInt64(curr.user &- prev.user)
            let dSystem = UInt64(curr.system &- prev.system)
            let dNice = UInt64(curr.nice &- prev.nice)
            let dIdle = UInt64(curr.idle &- prev.idle)

            sumUser += dUser
            sumSystem += dSystem
            sumNice += dNice
            sumIdle += dIdle

            let coreTotal = dUser + dSystem + dNice + dIdle
            if coreTotal > 0 {
                let busy = Double(dUser + dSystem + dNice) / Double(coreTotal) * 100.0
                perCore.append(min(100, max(0, busy)))
            } else {
                perCore.append(0)
            }
        }

        let allTicks = sumUser + sumSystem + sumNice + sumIdle
        guard allTicks > 0 else {
            return (0, 0, 0, 100, perCore)
        }

        let userPct = Double(sumUser + sumNice) / Double(allTicks) * 100.0
        let sysPct = Double(sumSystem) / Double(allTicks) * 100.0
        let idlePct = Double(sumIdle) / Double(allTicks) * 100.0
        let totalPct = min(100, max(0, userPct + sysPct))

        return (totalPct, userPct, sysPct, idlePct, perCore)
    }

    // MARK: - System Calls

    private static func readRawCoreTicks() -> [CoreTicks] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else {
            return []
        }

        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let count = Int(numCPUs)
        let stride = Int(CPU_STATE_MAX)
        var result: [CoreTicks] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let base = i * stride
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            result.append(CoreTicks(user: user, system: system, idle: idle, nice: nice))
        }
        return result
    }

    private static func readTopology() -> CPUTopology {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let total = Int(sysctlUInt64("hw.ncpu") ?? UInt64(ProcessInfo.processInfo.processorCount))

        var clusters: [CoreClusterInfo] = []
        for level in 0...2 {
            if let count = sysctlUInt64("hw.perflevel\(level).physicalcpu"), count > 0 {
                let rawName = sysctlString("hw.perflevel\(level).name") ?? "Cluster \(level)"
                clusters.append(CoreClusterInfo(name: rawName, count: Int(count)))
            }
        }
        if clusters.isEmpty && total > 0 {
            clusters.append(CoreClusterInfo(name: "Cores", count: total))
        }

        return CPUTopology(chipName: brand, totalCores: total, clusters: clusters)
    }

    private static func readLoadAverage() -> (Double, Double, Double) {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, 3)
        guard count == 3 else { return (0, 0, 0) }
        return (averages[0], averages[1], averages[2])
    }

    private static func readUptime() -> TimeInterval {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boottime, &size, nil, 0) == 0, boottime.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let now = Date().timeIntervalSince1970
        let boot = Double(boottime.tv_sec) + Double(boottime.tv_usec) / 1_000_000.0
        return max(0, now - boot)
    }

    static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return value
        }
        var value32: UInt32 = 0
        var size32 = MemoryLayout<UInt32>.stride
        if sysctlbyname(name, &value32, &size32, nil, 0) == 0 {
            return UInt64(value32)
        }
        return nil
    }
}
