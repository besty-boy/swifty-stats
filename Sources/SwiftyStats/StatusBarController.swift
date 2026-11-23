import AppKit
import SwiftUI
import SwiftyStatsCore

// MARK: - Crisp Retina 2-Line Menu Bar Renderer

@MainActor
public enum MenuBarRenderer {
    public static let barHeight: CGFloat = 22.0

    public struct RenderOptions: Equatable {
        public let colorMode: MenuBarColorMode
        public let density: MenuBarDensity
        public let isDarkAppearance: Bool

        public init(colorMode: MenuBarColorMode, density: MenuBarDensity, isDarkAppearance: Bool) {
            self.colorMode = colorMode
            self.density = density
            self.isDarkAppearance = isDarkAppearance
        }
    }

    public static func render(
        items: [MenuBarItemDisplay],
        options: RenderOptions
    ) -> NSImage {
        guard !items.isEmpty else {
            return NSImage(size: NSSize(width: 24, height: barHeight))
        }

        let labelFont = NSFont.systemFont(ofSize: 7.0, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

        let hasAlert = items.contains { $0.severity != .normal }
        let useTemplate: Bool = {
            switch options.colorMode {
            case .monochrome:
                return true
            case .adaptive:
                return !hasAlert
            case .colored:
                return false
            }
        }()

        // Measure each slot width (using stable minimum width to prevent horizontal jitter)
        struct MeasuredSlot {
            let item: MenuBarItemDisplay
            let labelAttr: NSAttributedString
            let valueAttr: NSAttributedString
            let labelSize: NSSize
            let valueSize: NSSize
            let slotWidth: CGFloat
        }

        let baseColor: NSColor = useTemplate
            ? .black
            : (options.isDarkAppearance ? NSColor(white: 1.0, alpha: 0.96) : NSColor(white: 0.08, alpha: 0.96))

        let labelColor: NSColor = useTemplate
            ? NSColor(white: 0.0, alpha: 0.68)
            : (options.isDarkAppearance ? NSColor(white: 1.0, alpha: 0.68) : NSColor(white: 0.08, alpha: 0.62))

        var slots: [MeasuredSlot] = []
        slots.reserveCapacity(items.count)

        let labelParagraph = NSMutableParagraphStyle()
        labelParagraph.alignment = .center
        labelParagraph.lineBreakMode = .byClipping

        for item in items {
            let valColor = valueColor(
                for: item,
                baseColor: baseColor,
                colorMode: options.colorMode,
                isDark: options.isDarkAppearance,
                useTemplate: useTemplate
            )

            let labelAttr = NSAttributedString(
                string: item.label,
                attributes: [
                    .font: labelFont,
                    .foregroundColor: labelColor,
                    .kern: 0.25,
                    .paragraphStyle: labelParagraph,
                ]
            )
            let valueAttr = NSAttributedString(
                string: item.value,
                attributes: [
                    .font: valueFont,
                    .foregroundColor: valColor,
                    .paragraphStyle: labelParagraph,
                ]
            )

            let lSize = labelAttr.size()
            let vSize = valueAttr.size()
            let slotWidth = ceil(max(item.minWidth, max(lSize.width, vSize.width)))

            slots.append(
                MeasuredSlot(
                    item: item,
                    labelAttr: labelAttr,
                    valueAttr: valueAttr,
                    labelSize: lSize,
                    valueSize: vSize,
                    slotWidth: slotWidth
                )
            )
        }

        let spacing = options.density.itemSpacing
        let hPad = options.density.horizontalPadding
        let totalSlotsWidth = slots.reduce(CGFloat(0)) { $0 + $1.slotWidth }
        let totalSpacing = spacing * CGFloat(max(0, slots.count - 1))
        let totalWidth = ceil(totalSlotsWidth + totalSpacing + hPad * 2)
        let size = NSSize(width: max(20, totalWidth), height: barHeight)

        // Pre-render into an explicit 2x Retina bitmap rep so macOS menu bar replicants
        // never re-invoke drawing closures during compositing.
        let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = max(1, Int(ceil(size.width * scale)))
        let pixelH = max(1, Int(ceil(size.height * scale)))

        let image = NSImage(size: size)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                var x = hPad
                for slot in slots {
                    let labelX = x + floor((slot.slotWidth - slot.labelSize.width) / 2.0)
                    let labelY: CGFloat = 12.2
                    slot.labelAttr.draw(at: NSPoint(x: labelX, y: labelY))

                    let valueX = x + floor((slot.slotWidth - slot.valueSize.width) / 2.0)
                    let valueY: CGFloat = 0.8
                    slot.valueAttr.draw(at: NSPoint(x: valueX, y: valueY))

                    x += slot.slotWidth + spacing
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }

        image.isTemplate = useTemplate
        return image
    }

    private static func valueColor(
        for item: MenuBarItemDisplay,
        baseColor: NSColor,
        colorMode: MenuBarColorMode,
        isDark: Bool,
        useTemplate: Bool
    ) -> NSColor {
        if useTemplate {
            return baseColor
        }

        switch item.severity {
        case .critical:
            return isDark
                ? NSColor(srgbRed: 1.0, green: 0.36, blue: 0.34, alpha: 1.0)
                : NSColor(srgbRed: 0.82, green: 0.14, blue: 0.14, alpha: 1.0)
        case .elevated:
            return isDark
                ? NSColor(srgbRed: 1.0, green: 0.72, blue: 0.24, alpha: 1.0)
                : NSColor(srgbRed: 0.78, green: 0.44, blue: 0.0, alpha: 1.0)
        case .normal:
            guard colorMode == .colored else { return baseColor }
            switch item.metric {
            case .cpu:
                return isDark
                    ? NSColor(srgbRed: 0.45, green: 0.76, blue: 1.0, alpha: 1.0)
                    : NSColor(srgbRed: 0.08, green: 0.42, blue: 0.84, alpha: 1.0)
            case .ram:
                return isDark
                    ? NSColor(srgbRed: 0.72, green: 0.58, blue: 1.0, alpha: 1.0)
                    : NSColor(srgbRed: 0.44, green: 0.24, blue: 0.82, alpha: 1.0)
            case .temperature:
                return isDark
                    ? NSColor(srgbRed: 0.44, green: 0.88, blue: 0.64, alpha: 1.0)
                    : NSColor(srgbRed: 0.10, green: 0.54, blue: 0.32, alpha: 1.0)
            case .power:
                return isDark
                    ? NSColor(srgbRed: 1.0, green: 0.82, blue: 0.35, alpha: 1.0)
                    : NSColor(srgbRed: 0.74, green: 0.48, blue: 0.02, alpha: 1.0)
            }
        }
    }
}

// MARK: - StatusBarController

@MainActor
public final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let uiState = PopoverUIState()
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    private var appearanceObservation: NSKeyValueObservation?
    private var clickOutsideMonitor: Any?
    private var lastRenderSignature: RenderSignature?
    private var latestItems: [MenuBarItemDisplay] = []

    private struct RenderSignature: Equatable {
        let items: [MenuBarItemDisplay]
        let options: MenuBarRenderer.RenderOptions
    }

    public init(monitor: SystemMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 344, height: 500)
        popover.delegate = self

        configureButton()

        monitor.onMenuBarChange = { [weak self] items in
            self?.latestItems = items
            self?.renderStatusItem(force: false)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(handleStatusButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "SwiftyStats — Clic gauche : détails, clic droit : menu rapide"

        // Observe system/app appearance (NOT button.effectiveAppearance, which AppKit
        // mutates transiently during NSStatusItem replicant snapshots).
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.renderStatusItem(force: false)
            }
        }
    }

    private func renderStatusItem(force: Bool) {
        guard let button = statusItem.button else { return }
        let items = latestItems.isEmpty
            ? monitor.buildMenuBarItems(cpu: monitor.cpu, memory: monitor.memory, sensors: monitor.sensors)
            : latestItems

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let options = MenuBarRenderer.RenderOptions(
            colorMode: monitor.settings.colorMode,
            density: monitor.settings.density,
            isDarkAppearance: isDark
        )
        let sig = RenderSignature(items: items, options: options)
        guard force || sig != lastRenderSignature else { return }
        lastRenderSignature = sig

        let image = MenuBarRenderer.render(items: items, options: options)
        button.image = image
        let targetLength = image.size.width + 6
        if abs(statusItem.length - targetLength) > 0.5 {
            statusItem.length = targetLength
        }
    }

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type
        if eventType == .rightMouseUp {
            showContextMenu(for: sender)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: button)
        }
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        uiState.launchAtLogin = monitor.settings.isLaunchAtLoginEnabled
        let rootView = PopoverRootView(
            monitor: monitor,
            uiState: uiState,
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        monitor.setPopoverOpen(true)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        installClickOutsideMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        removeClickOutsideMonitor()
        monitor.setPopoverOpen(false)
        // Release SwiftUI hosting view hierarchy when closed to keep idle RAM minimal
        popover.contentViewController = nil
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.closePopover()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitorRef = clickOutsideMonitor {
            NSEvent.removeMonitor(monitorRef)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Right-Click Context Menu

    private func showContextMenu(for button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Ouvrir SwiftyStats", action: #selector(menuOpenPopover), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Afficher dans la barre", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for metric in MenuBarMetric.allCases {
            let item = NSMenuItem(title: metric.displayName, action: #selector(menuToggleMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = monitor.settings.isEnabled(metric) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter SwiftyStats", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenPopover() {
        guard let button = statusItem.button else { return }
        openPopover(relativeTo: button)
    }

    @objc private func menuToggleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let metric = MenuBarMetric(rawValue: raw) else { return }
        let current = monitor.settings.isEnabled(metric)
        monitor.settings.setEnabled(!current, for: metric)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
