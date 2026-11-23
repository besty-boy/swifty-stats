import AppKit
import SwiftyStatsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SystemMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore()
        let monitor = SystemMonitor(settings: settings)
        let controller = StatusBarController(monitor: monitor)

        self.monitor = monitor
        self.statusBarController = controller

        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }
}

@main
struct SwiftyStatsMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
