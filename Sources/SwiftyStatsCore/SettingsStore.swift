import Foundation
import Observation
import ServiceManagement

public enum MenuBarMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu
    case ram
    case temperature
    case power

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .temperature: return "TMP"
        case .power: return "PWR"
        }
    }

    public var displayName: String {
        switch self {
        case .cpu: return "CPU (%)"
        case .ram: return "RAM"
        case .temperature: return "Température CPU"
        case .power: return "Consommation (W)"
        }
    }
}

public enum RAMDisplayMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case percent
    case usedGB

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .percent: return "%"
        case .usedGB: return "Go"
        }
    }
}

public enum TemperatureUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case celsius
    case fahrenheit

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

public enum TemperatureAggregation: String, CaseIterable, Codable, Sendable, Identifiable {
    case average
    case maximum

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .average: return "Moyenne"
        case .maximum: return "Pic max"
        }
    }
}

public enum MenuBarColorMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case adaptive
    case monochrome
    case colored

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .adaptive: return "Alerte"
        case .monochrome: return "Mono"
        case .colored: return "Couleur"
        }
    }
}

public enum MenuBarDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case ultraCompact
    case standard

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .ultraCompact: return "Ultra-compact"
        case .standard: return "Standard"
        }
    }

    public var itemSpacing: CGFloat {
        switch self {
        case .ultraCompact: return 6
        case .standard: return 10
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .ultraCompact: return 2
        case .standard: return 5
        }
    }
}

@MainActor
@Observable
public final class SettingsStore {
    private enum Keys {
        static let showCPU = "settings.showCPU"
        static let showRAM = "settings.showRAM"
        static let showTemperature = "settings.showTemperature"
        static let showPower = "settings.showPower"
        static let ramDisplayMode = "settings.ramDisplayMode"
        static let temperatureUnit = "settings.temperatureUnit"
        static let temperatureAggregation = "settings.temperatureAggregation"
        static let colorMode = "settings.colorMode"
        static let density = "settings.density"
        static let refreshInterval = "settings.refreshInterval"
    }

    private let defaults: UserDefaults
    public var onChange: (@MainActor () -> Void)?

    public var showCPU: Bool {
        didSet {
            ensureAtLeastOneMetricEnabled(fallback: \.showCPU)
            defaults.set(showCPU, forKey: Keys.showCPU)
            onChange?()
        }
    }

    public var showRAM: Bool {
        didSet {
            ensureAtLeastOneMetricEnabled(fallback: \.showRAM)
            defaults.set(showRAM, forKey: Keys.showRAM)
            onChange?()
        }
    }

    public var showTemperature: Bool {
        didSet {
            ensureAtLeastOneMetricEnabled(fallback: \.showTemperature)
            defaults.set(showTemperature, forKey: Keys.showTemperature)
            onChange?()
        }
    }

    public var showPower: Bool {
        didSet {
            ensureAtLeastOneMetricEnabled(fallback: \.showPower)
            defaults.set(showPower, forKey: Keys.showPower)
            onChange?()
        }
    }

    public var ramDisplayMode: RAMDisplayMode {
        didSet {
            defaults.set(ramDisplayMode.rawValue, forKey: Keys.ramDisplayMode)
            onChange?()
        }
    }

    public var temperatureUnit: TemperatureUnit {
        didSet {
            defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit)
            onChange?()
        }
    }

    public var temperatureAggregation: TemperatureAggregation {
        didSet {
            defaults.set(temperatureAggregation.rawValue, forKey: Keys.temperatureAggregation)
            onChange?()
        }
    }

    public var colorMode: MenuBarColorMode {
        didSet {
            defaults.set(colorMode.rawValue, forKey: Keys.colorMode)
            onChange?()
        }
    }

    public var density: MenuBarDensity {
        didSet {
            defaults.set(density.rawValue, forKey: Keys.density)
            onChange?()
        }
    }

    public var refreshInterval: TimeInterval {
        didSet {
            defaults.set(refreshInterval, forKey: Keys.refreshInterval)
            onChange?()
        }
    }

    public var launchAtLoginError: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showCPU = defaults.object(forKey: Keys.showCPU) as? Bool ?? true
        self.showRAM = defaults.object(forKey: Keys.showRAM) as? Bool ?? true
        self.showTemperature = defaults.object(forKey: Keys.showTemperature) as? Bool ?? true
        self.showPower = defaults.object(forKey: Keys.showPower) as? Bool ?? false
        self.ramDisplayMode = RAMDisplayMode(rawValue: defaults.string(forKey: Keys.ramDisplayMode) ?? "") ?? .percent
        self.temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Keys.temperatureUnit) ?? "") ?? .celsius
        self.temperatureAggregation = TemperatureAggregation(rawValue: defaults.string(forKey: Keys.temperatureAggregation) ?? "") ?? .average
        self.colorMode = MenuBarColorMode(rawValue: defaults.string(forKey: Keys.colorMode) ?? "") ?? .adaptive
        self.density = MenuBarDensity(rawValue: defaults.string(forKey: Keys.density) ?? "") ?? .ultraCompact
        let savedInterval = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0
    }

    public var enabledMetrics: [MenuBarMetric] {
        var list: [MenuBarMetric] = []
        if showCPU { list.append(.cpu) }
        if showRAM { list.append(.ram) }
        if showTemperature { list.append(.temperature) }
        if showPower { list.append(.power) }
        return list.isEmpty ? [.cpu] : list
    }

    public func isEnabled(_ metric: MenuBarMetric) -> Bool {
        switch metric {
        case .cpu: return showCPU
        case .ram: return showRAM
        case .temperature: return showTemperature
        case .power: return showPower
        }
    }

    public func setEnabled(_ enabled: Bool, for metric: MenuBarMetric) {
        switch metric {
        case .cpu: showCPU = enabled
        case .ram: showRAM = enabled
        case .temperature: showTemperature = enabled
        case .power: showPower = enabled
        }
    }

    private func ensureAtLeastOneMetricEnabled(fallback keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) {
        if !showCPU && !showRAM && !showTemperature && !showPower {
            self[keyPath: keyPath] = true
        }
    }

    // MARK: - Launch at Login (SMAppService)

    public var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public var canConfigureLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        guard canConfigureLaunchAtLogin else {
            launchAtLoginError = "Installe SwiftyStats.app dans /Applications pour activer le lancement au démarrage."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Impossible de modifier l'ouverture à la session : \(error.localizedDescription)"
        }
    }
}
