import AppKit
import SwiftUI

/// 让 NSHostingView 接受首次鼠标点击，从其他窗口切过来时单击即可触发操作
private class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 毛玻璃无标题栏悬浮面板，高度跟随内容自适应
class FloatingPanel: NSPanel {
    private var sizeObservation: NSKeyValueObservation?
    private let hostingView: NSHostingView<AnyView>

    init<Content: View>(rootView: Content) {
        let wrapped = AnyView(
            rootView.background(
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            )
        )
        let hosting = FirstMouseHostingView(rootView: wrapped)
        self.hostingView = hosting

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        self.contentView = hosting

        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.animationBehavior = .utilityWindow
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true

        self.minSize = NSSize(width: 220, height: 80)
        if let screenHeight = NSScreen.main?.visibleFrame.height {
            self.maxSize = NSSize(width: 800, height: screenHeight * 0.8)
        }

        // 根据内容计算初始尺寸
        fitToContent()

        // 监听内容尺寸变化
        sizeObservation = hosting.observe(\.intrinsicContentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.fitToContent() }
        }

        NSWindow.removeFrame(usingName: "CCDockPanel")
        self.setFrameAutosaveName("CCDockPanel")
        positionAtTopRight()
    }

    private func fitToContent() {
        let fitting = hostingView.fittingSize
        guard fitting.height > 0 else { return }
        let maxH = self.maxSize.height
        let newWidth = min(max(fitting.width, self.minSize.width), self.maxSize.width)
        let newHeight = min(fitting.height, maxH)
        let newSize = NSSize(width: newWidth, height: newHeight)
        guard abs(frame.size.width - newSize.width) > 1
           || abs(frame.size.height - newSize.height) > 1 else { return }
        // 保持顶部位置不变（macOS 坐标系 origin 在左下角）
        let newY = frame.origin.y + frame.height - newHeight
        self.setFrame(NSRect(x: frame.origin.x, y: newY, width: newWidth, height: newHeight), display: true)
    }

    private func positionAtTopRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = self.frame
        let x = screenFrame.maxX - panelFrame.width - 20
        let y = screenFrame.maxY - panelFrame.height - 20
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // false: 面板不抢 key window，点击直接触发操作，无需先激活
    override var canBecomeKey: Bool { false }
}

/// NSVisualEffectView 的 SwiftUI 包装
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
