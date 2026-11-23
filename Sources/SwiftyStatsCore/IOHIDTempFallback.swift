import Darwin
import Foundation

/// Fallback temperature reader via Apple's IOHIDEventSystem private C APIs.
/// Only used if SMCReader discovers no CPU thermal sensors.
public final class IOHIDTempFallback: @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> CFArray?
    private typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString) -> CFTypeRef?
    private typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double

    private let lock = NSLock()
    private let createFn: CreateFn?
    private let setMatchingFn: SetMatchingFn?
    private let copyServicesFn: CopyServicesFn?
    private let copyPropertyFn: CopyPropertyFn?
    private let copyEventFn: CopyEventFn?
    private let getFloatFn: GetFloatValueFn?

    public init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            self.createFn = nil
            self.setMatchingFn = nil
            self.copyServicesFn = nil
            self.copyPropertyFn = nil
            self.copyEventFn = nil
            self.getFloatFn = nil
            return
        }

        func load<T>(_ symbol: String) -> T? {
            guard let ptr = dlsym(handle, symbol) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        self.createFn = load("IOHIDEventSystemClientCreate")
        self.setMatchingFn = load("IOHIDEventSystemClientSetMatching")
        self.copyServicesFn = load("IOHIDEventSystemClientCopyServices")
        self.copyPropertyFn = load("IOHIDServiceClientCopyProperty")
        self.copyEventFn = load("IOHIDServiceClientCopyEvent")
        self.getFloatFn = load("IOHIDEventGetFloatValue")
    }

    public func readDieTemperatures() -> [Double] {
        lock.lock()
        defer { lock.unlock() }

        guard
            let createFn,
            let setMatchingFn,
            let copyServicesFn,
            let copyPropertyFn,
            let copyEventFn,
            let getFloatFn,
            let client = createFn(kCFAllocatorDefault)
        else {
            return []
        }

        defer {
            Unmanaged<AnyObject>.fromOpaque(client).release()
        }

        let matching: [String: Any] = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5]
        setMatchingFn(client, matching as CFDictionary)

        guard let services = copyServicesFn(client) as? [AnyObject] else {
            return []
        }

        var readings: [Double] = []
        for service in services {
            let raw = Unmanaged.passUnretained(service).toOpaque()
            let product = (copyPropertyFn(raw, "Product" as CFString) as? String) ?? ""
            guard product.lowercased().contains("tdie") else { continue }
            if let event = copyEventFn(raw, 15, 0, 0) {
                let value = getFloatFn(event, 15 << 16)
                Unmanaged<AnyObject>.fromOpaque(event).release()
                if (10.0...125.0).contains(value) {
                    readings.append(value)
                }
            }
        }
        return readings
    }
}
