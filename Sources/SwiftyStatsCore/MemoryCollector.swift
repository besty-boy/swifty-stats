import Darwin
import Foundation

public struct VMPageCounts: Sendable, Equatable {
    public let pageSize: UInt64
    public let internalPages: UInt64
    public let purgeablePages: UInt64
    public let wiredPages: UInt64
    public let compressedPages: UInt64
    public let externalPages: UInt64

    public init(
        pageSize: UInt64,
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        externalPages: UInt64
    ) {
        self.pageSize = pageSize
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
        self.externalPages = externalPages
    }
}

public final class MemoryCollector: Sendable {
    public let totalBytes: UInt64
    private let pageSize: UInt64

    public init() {
        self.totalBytes = Self.readTotalMemoryBytes()
        self.pageSize = Self.readHostPageSize()
    }

    public func sample(includeExtras: Bool) -> MemorySnapshot {
        guard let counts = readVMPageCounts() else {
            return MemorySnapshot(totalBytes: totalBytes)
        }
        let swap = includeExtras ? Self.readSwapUsage() : (used: UInt64(0), total: UInt64(0))
        let pressure = Self.readMemoryPressure()
        let selfFootprint = includeExtras ? Self.readSelfFootprintBytes() : 0

        return Self.computeSnapshot(
            totalBytes: totalBytes,
            counts: counts,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: pressure,
            selfFootprintBytes: selfFootprint
        )
    }

    // MARK: - Pure Calculation (Matches Activity Monitor)

    public static func computeSnapshot(
        totalBytes: UInt64,
        counts: VMPageCounts,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        pressure: MemoryPressureLevel,
        selfFootprintBytes: UInt64
    ) -> MemorySnapshot {
        let ps = counts.pageSize
        let appPages = counts.internalPages > counts.purgeablePages
            ? (counts.internalPages - counts.purgeablePages)
            : 0
        let appBytes = appPages * ps
        let wiredBytes = counts.wiredPages * ps
        let compressedBytes = counts.compressedPages * ps
        let cachedBytes = (counts.externalPages + counts.purgeablePages) * ps

        let usedBytes = min(totalBytes, appBytes + wiredBytes + compressedBytes)
        let freeBytes = totalBytes > usedBytes ? (totalBytes - usedBytes) : 0

        return MemorySnapshot(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsedBytes,
            swapTotalBytes: swapTotalBytes,
            pressure: pressure,
            selfFootprintBytes: selfFootprintBytes
        )
    }

    // MARK: - System Calls

    private static func readTotalMemoryBytes() -> UInt64 {
        var memsize: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        if sysctlbyname("hw.memsize", &memsize, &size, nil, 0) == 0, memsize > 0 {
            return memsize
        }
        return ProcessInfo.processInfo.physicalMemory
    }

    private static func readHostPageSize() -> UInt64 {
        var pageSize: vm_size_t = 0
        if host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 {
            return UInt64(pageSize)
        }
        return UInt64(max(4096, Int(getpagesize())))
    }

    private func readVMPageCounts() -> VMPageCounts? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        return VMPageCounts(
            pageSize: pageSize,
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            externalPages: UInt64(stats.external_page_count)
        )
    }

    private static func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (swap.xsu_used, swap.xsu_total)
    }

    private static func readMemoryPressure() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        if level >= 4 { return .critical }
        if level >= 2 { return .warning }
        return .normal
    }

    public static func readSelfFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }
}
