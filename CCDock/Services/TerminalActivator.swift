import Foundation
import AppKit

/// 通过 tmux + AppleScript 激活对应终端窗口/tab
class TerminalActivator {

    func activate(session: Session) {
        guard let tty = session.tty, !tty.isEmpty else {
            print("[TerminalActivator] ⚠️ 会话 \(session.projectName) 没有 TTY 信息")
            activateFallback()
            return
        }

        // 优先尝试 tmux 切换
        if activateViaTmux(tty: tty, projectName: session.projectName) {
            return
        }

        // 找到拥有这个 session PID 的终端应用，只激活它
        let ownerApp = findTerminalOwner(pid: session.pid)
        print("[TerminalActivator] 终端应用: \(ownerApp ?? "未知"), TTY: \(tty)")

        switch ownerApp {
        case "com.apple.Terminal":
            if tryTerminalApp(tty: tty) { return }
        case "com.googlecode.iterm2":
            if tryITerm2(tty: tty) { return }
        default:
            break
        }

        // Ghostty / Warp / kitty 等：直接激活对应终端应用
        if let app = ownerApp {
            activateAppByBundleId(app)
        } else {
            activateFallback()
        }
    }

    // MARK: - 查找 PID 所属终端应用

    /// 沿进程树向上找到终端应用的 bundle ID
    private func findTerminalOwner(pid: Int) -> String? {
        var currentPid = pid
        let terminalBundleIds: Set<String> = [
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty",
            "io.alacritty",
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        let bundleIdByPid = Dictionary(
            uniqueKeysWithValues: runningApps.compactMap { app in
                app.bundleIdentifier.map { (app.processIdentifier, $0) }
            }
        )

        // 向上遍历进程树（最多 20 层防死循环）
        for _ in 0..<20 {
            if currentPid <= 1 { break }

            if let bundleId = bundleIdByPid[Int32(currentPid)],
               terminalBundleIds.contains(bundleId) {
                return bundleId
            }

            // 获取父进程 PID
            guard let ppid = getParentPid(currentPid) else { break }
            if ppid == currentPid { break }
            currentPid = ppid
        }

        return nil
    }

    private func getParentPid(_ pid: Int) -> Int? {
        guard let output = runProcess("/bin/ps", args: ["-o", "ppid=", "-p", "\(pid)"]) else {
            return nil
        }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - tmux 方式

    /// tmux 可能在 /opt/homebrew/bin 或 /usr/local/bin，.app 的 PATH 找不到
    private lazy var tmuxPath: String? = {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private func activateViaTmux(tty: String, projectName: String) -> Bool {
        guard let tmux = tmuxPath else { return false }
        let fullTty = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"

        guard let tmuxOutput = runProcess(tmux, args: [
            "list-panes", "-a",
            "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"
        ]) else {
            return false
        }

        for line in tmuxOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let target = String(parts[0])
            let paneTty = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            if paneTty == fullTty {
                let _ = runProcess(tmux, args: ["select-window", "-t", target])
                activateTerminalApp()
                print("[TerminalActivator] ✅ tmux 切换到 \(projectName) (\(target))")
                return true
            }
        }

        return false
    }

    // MARK: - AppleScript 方式

    private func tryTerminalApp(tty: String) -> Bool {
        // 先匹配，确认找到后再 activate
        let script = """
            tell application "Terminal"
                set targetTTY to "/dev/\(tty)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTTY then
                            activate
                            set selected of t to true
                            set index of w to 1
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
        """
        return runAppleScript(script) == "true"
    }

    private func tryITerm2(tty: String) -> Bool {
        let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s contains "\(tty)" then
                                activate
                                select t
                                select s
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
        """
        return runAppleScript(script) == "true"
    }

    // MARK: - 通用终端激活

    private func activateAppByBundleId(_ bundleId: String) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            app.activate()
            print("[TerminalActivator] ✅ 激活 \(bundleId)")
        }
    }

    private func activateTerminalApp() {
        let terminalApps = ["ghostty", "iTerm2", "Terminal", "Warp", "kitty", "Alacritty"]
        for app in terminalApps {
            if isAppRunning(app) {
                let script = "tell application \"\(app)\" to activate"
                let _ = runAppleScript(script)
                return
            }
        }
    }

    private func activateFallback() {
        activateTerminalApp()
    }

    // MARK: - Helpers

    private func isAppRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName?.lowercased() == name.lowercased()
                || ($0.bundleIdentifier ?? "").lowercased().contains(name.lowercased())
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            print("[TerminalActivator] ⚠️ AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }

    private func runProcess(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
