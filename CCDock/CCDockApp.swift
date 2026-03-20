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

    private static let isDemo = CommandLine.arguments.contains("--demo")

    let store: SessionStore = AppDelegate.isDemo ? .mock() : SessionStore()
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

        if AppDelegate.isDemo {
            // Demo 模式：直接显示 Pin 面板，不启动后台服务
            isPinned = true
            // 延迟截图，等渲染完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.capturePanel()
            }
        } else {
            startServices()
            showWelcomeIfFirstLaunch()
        }
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
        popover.behavior = .transient // 点击外部自动关闭
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: PopoverContentView(delegate: self)
        )
        // 让 popover 高度跟随内容自适应
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        self.popover = popover
    }

    // MARK: - Floating Panel (Pin 模式)

    private func setupPanel() {
        panel = FloatingPanel(rootView: PinnedContentView(delegate: self))
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
        popover?.performClose(nil)

        // 复用已有窗口
        if let existing = editorWindow {
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
        window.initialFirstResponder = nil
        // 窗口关闭时清空引用，下次重新创建
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.editorWindow = nil
        }
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

    // MARK: - Demo 截图

    private func capturePanel() {
        guard let panel = panel, let view = panel.contentView else { return }
        let bounds = view.bounds
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        // 保存到项目 docs/ 目录
        let outputPath = CommandLine.arguments.first(where: { $0.hasPrefix("--output=") })?.dropFirst("--output=".count)
            ?? "\(FileManager.default.currentDirectoryPath)/docs/screenshot-panel.png"
        let url = URL(fileURLWithPath: String(outputPath))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? pngData.write(to: url)
        print("[demo] Screenshot saved to \(url.path)")
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
