import SwiftUI
import AppKit

@main
struct CCDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var panel: FloatingPanel?
    private var editorWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var eventMonitor: Any?

    let store = SessionStore()
    private var discovery: SessionDiscovery?
    private var codexDiscovery: CodexDiscovery?
    private var geminiDiscovery: GeminiDiscovery?
    private var poller: StatusPoller?
    private var codexPoller: CodexPoller?
    let activator = TerminalActivator()

    /// 是否 Pin 到桌面
    var isPinned = false {
        didSet { handlePinChange() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupAppIcon()
        setupMenuBar()
        setupPopover()
        startServices()
        showWelcomeIfFirstLaunch()
    }

    private func setupAppIcon() {
        // Bundle.main.resourceURL → CCDock.app/Contents/Resources/
        if let iconURL = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    // MARK: - MenuBar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "CCDock")
        button.action = #selector(menuBarClicked)
        button.target = self
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.behavior = .transient // 点击外部自动关闭
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(delegate: self)
        )
        self.popover = popover
    }

    // MARK: - Floating Panel (Pin 模式)

    private func setupPanel() {
        let contentView = NSHostingView(
            rootView: PinnedContentView(delegate: self)
        )
        panel = FloatingPanel(contentView: contentView)
    }

    // MARK: - Actions

    @objc private func menuBarClicked() {
        if isPinned {
            // Pin 模式下，MenuBar 点击切换面板显示
            togglePanel()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 点击外部关闭
            startEventMonitor()
        }
    }

    private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    private func handlePinChange() {
        if isPinned {
            // 关闭 popover，打开 floating panel
            popover?.performClose(nil)
            if panel == nil { setupPanel() }
            panel?.orderFront(nil)
        } else {
            // 关闭 floating panel
            panel?.orderOut(nil)
            panel = nil
            // 清掉保存的位置，下次 Pin 重新定位
            NSWindow.removeFrame(usingName: "CCDockPanel")
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func openLayoutEditor() {
        // 关闭 popover
        popover?.performClose(nil)

        if let existing = editorWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CCDock - 自定义布局"
        window.contentView = NSHostingView(rootView: LayoutEditorView())
        window.center()
        // 避免按钮获得蓝色焦点环
        window.initialFirstResponder = nil
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editorWindow = window
    }

    // MARK: - Welcome

    private func showWelcomeIfFirstLaunch() {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.level = .floating

        window.contentView = NSHostingView(
            rootView: WelcomeView {
                window.close()
                self.isPinned = true
            }
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }

    // MARK: - Services

    private func startServices() {
        discovery = SessionDiscovery(store: store)
        discovery?.start()

        codexDiscovery = CodexDiscovery(store: store)
        codexDiscovery?.start()

        geminiDiscovery = GeminiDiscovery(store: store)
        geminiDiscovery?.start()

        poller = StatusPoller(store: store)
        poller?.start()

        codexPoller = CodexPoller(store: store)
        codexPoller?.start()
    }

    // MARK: - Event Monitor

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
