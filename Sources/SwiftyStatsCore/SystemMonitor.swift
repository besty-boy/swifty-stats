import Foundation
import Observation

@MainActor
@Observable
public final class SystemMonitor {
    public let settings: SettingsStore
    public let topology: CPUTopology
    public let totalMemoryBytes: UInt64

    // Popover-observed telemetry state
    public private(set) var cpu: CPUSnapshot = CPUSnapshot()
    public private(set) var memory: MemorySnapshot = MemorySnapshot()
    public private(set) var sensors: SensorSnapshot = SensorSnapshot()
    public private(set) var processes: ProcessSnapshot = ProcessSnapshot()

    public private(set) var cpuHistory: [Double] = []
    public private(set) var memoryHistory: [Double] = []
    public private(set) var temperatureHistory: [Double] = []
    public private(set) var powerHistory: [Double] = []

    public private(set) var menuBarItems: [MenuBarItemDisplay] = []

    /// Callback invoked on MainActor whenever menu bar items or display settings change.
    public var onMenuBarChange: (@MainActor ([MenuBarItemDisplay]) -> Void)?

    // Collectors (background-safe)
    private let cpuCollector: CPUCollector
    private let memoryCollector: MemoryCollector
    private let sensorCollector: SensorCollector
    private let processCollector: ProcessCollector

    private let samplingQueue = DispatchQueue(label: "com.swiftystats.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isPopoverOpen = false
    private var isSampling = false

    private var cpuRing = RingBuffer<Double>(capacity: 60)
    private var memRing = RingBuffer<Double>(capacity: 60)
    private var tempRing = RingBuffer<Double>(capacity: 60)
    private var powerRing = RingBuffer<Double>(capacity: 60)

    public init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let cpuCollector = CPUCollector()
        let memoryCollector = MemoryCollector()
        let sensorCollector = SensorCollector()
        let processCollector = ProcessCollector()

        self.cpuCollector = cpuCollector
        self.memoryCollector = memoryCollector
        self.sensorCollector = sensorCollector
        self.processCollector = processCollector
        self.topology = cpuCollector.topology
        self.totalMemoryBytes = memoryCollector.totalBytes

        settings.onChange = { [weak self] in
            guard let self else { return }
            self.restartTimer()
            self.rebuildMenuBarItems(forceNotify: true)
            // If user just enabled power or temp in menu bar, trigger an immediate refresh
            self.triggerSample(includeProcesses: self.isPopoverOpen)
        }
    }

    public func start() {
        restartTimer()
        triggerSample(includeProcesses: false)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func setPopoverOpen(_ open: Bool) {
        guard isPopoverOpen != open else { return }
        isPopoverOpen = open
        if open {
            // Sync ring buffers to observable properties immediately before the first full tick arrives
            cpuHistory = cpuRing.values
            memoryHistory = memRing.values
            temperatureHistory = tempRing.values
            powerHistory = powerRing.values
            triggerSample(includeProcesses: true)
        }
    }

    public func refreshNow() {
        triggerSample(includeProcesses: isPopoverOpen)
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = max(1.0, settings.refreshInterval)
        let source = DispatchSource.makeTimerSource(queue: samplingQueue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.triggerSample(includeProcesses: self.isPopoverOpen)
            }
        }
        source.resume()
        self.timer = source
    }

    private func triggerSample(includeProcesses: Bool) {
        guard !isSampling else { return }
        isSampling = true

        let popoverOpen = isPopoverOpen
        let needTemp = popoverOpen || settings.showTemperature
        let needPower = popoverOpen || settings.showPower
        let cpuCollector = self.cpuCollector
        let memoryCollector = self.memoryCollector
        let sensorCollector = self.sensorCollector
        let processCollector = self.processCollector

        samplingQueue.async { [weak self] in
            let cpuSnap = cpuCollector.sample(includeExtras: popoverOpen)
            let memSnap = memoryCollector.sample(includeExtras: popoverOpen)
            let sensorSnap = popoverOpen
                ? sensorCollector.sampleFull()
                : sensorCollector.sampleCompact(includeTemperature: needTemp, includePower: needPower)
            let procSnap = includeProcesses ? processCollector.sample(limit: 6) : nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applySample(
                    cpu: cpuSnap,
                    memory: memSnap,
                    sensors: sensorSnap,
                    processes: procSnap,
                    popoverOpen: popoverOpen
                )
                self.isSampling = false
            }
        }
    }

    private func applySample(
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        sensors: SensorSnapshot,
        processes: ProcessSnapshot?,
        popoverOpen: Bool
    ) {
        self.cpuRing.append(cpu.totalPercent)
        self.memRing.append(memory.usedPercent)
        if let temp = selectedTemperatureC(from: sensors) {
            self.tempRing.append(temp)
        }
        if let watts = sensors.systemPowerWatts {
            self.powerRing.append(watts)
        }

        // Always update latest values for menu bar computation; only publish heavy history arrays when popover is open
        self.cpu = cpu
        self.memory = memory
        self.sensors = sensors
        if let processes {
            self.processes = processes
        }
        if popoverOpen {
            self.cpuHistory = cpuRing.values
            self.memoryHistory = memRing.values
            self.temperatureHistory = tempRing.values
            self.powerHistory = powerRing.values
        }

        rebuildMenuBarItems(forceNotify: false)
    }

    public func selectedTemperatureC(from sensors: SensorSnapshot) -> Double? {
        switch settings.temperatureAggregation {
        case .average:
            return sensors.cpuTempAverageC ?? sensors.cpuTempMaxC
        case .maximum:
            return sensors.cpuTempMaxC ?? sensors.cpuTempAverageC
        }
    }

    private func rebuildMenuBarItems(forceNotify: Bool) {
        let items = buildMenuBarItems(cpu: cpu, memory: memory, sensors: sensors)
        if forceNotify || items != menuBarItems {
            menuBarItems = items
            onMenuBarChange?(items)
        }
    }

    public func buildMenuBarItems(
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        sensors: SensorSnapshot
    ) -> [MenuBarItemDisplay] {
        var result: [MenuBarItemDisplay] = []
        for metric in settings.enabledMetrics {
            switch metric {
            case .cpu:
                result.append(
                    MenuBarItemDisplay(
                        label: metric.shortLabel,
                        value: StatsFormatter.percentInt(cpu.totalPercent),
                        minWidth: 25,
                        severity: StatsFormatter.cpuSeverity(cpu.totalPercent),
                        metric: .cpu
                    )
                )

            case .ram:
                let value: String
                let minW: CGFloat
                switch settings.ramDisplayMode {
                case .percent:
                    value = StatsFormatter.percentInt(memory.usedPercent)
                    minW = 25
                case .usedGB:
                    value = StatsFormatter.compactGB(memory.usedBytes)
                    minW = 31
                }
                result.append(
                    MenuBarItemDisplay(
                        label: metric.shortLabel,
                        value: value,
                        minWidth: minW,
                        severity: StatsFormatter.ramSeverity(memory.usedPercent, pressure: memory.pressure),
                        metric: .ram
                    )
                )

            case .temperature:
                let tempC = selectedTemperatureC(from: sensors)
                result.append(
                    MenuBarItemDisplay(
                        label: metric.shortLabel,
                        value: StatsFormatter.temperatureCompact(tempC, unit: settings.temperatureUnit),
                        minWidth: 23,
                        severity: StatsFormatter.tempSeverity(tempC),
                        metric: .temperature
                    )
                )

            case .power:
                result.append(
                    MenuBarItemDisplay(
                        label: metric.shortLabel,
                        value: StatsFormatter.wattsCompact(sensors.systemPowerWatts),
                        minWidth: 26,
                        severity: StatsFormatter.powerSeverity(sensors.systemPowerWatts),
                        metric: .power
                    )
                )
            }
        }
        return result
    }
}
