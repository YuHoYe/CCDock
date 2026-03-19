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

        // 优先尝试 tmux 切换（适用于 tmux 环境）
        if activateViaTmux(tty: tty, projectName: session.projectName) {
            return
        }

        // 回退：尝试通过 AppleScript 匹配终端窗口
        activateViaAppleScript(session: session)
    }

    // MARK: - tmux 方式（最可靠）

    private func activateViaTmux(tty: String, projectName: String) -> Bool {
        let fullTty = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"

        // 查询 tmux 所有 pane，找到匹配 tty 的那个
        guard let tmuxOutput = runProcess("/usr/bin/env", args: [
            "tmux", "list-panes", "-a",
            "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"
        ]) else {
            return false
        }

        // 解析 tmux 输出，匹配 TTY
        for line in tmuxOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let target = String(parts[0])
            let paneTty = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            if paneTty == fullTty {
                // 切换到目标 window
                let _ = runProcess("/usr/bin/env", args: ["tmux", "select-window", "-t", target])
                // 激活终端应用到前台
                activateTerminalApp()
                print("[TerminalActivator] ✅ tmux 切换到 \(projectName) (\(target))")
                return true
            }
        }

        return false
    }

    // MARK: - AppleScript 方式（回退）

    private func activateViaAppleScript(session: Session) {
        let tty = session.tty ?? ""

        // 尝试 Terminal.app
        if tryTerminalApp(tty: tty) { return }

        // 尝试 iTerm2
        if tryITerm2(tty: tty) { return }

        // 最终回退：激活任何终端
        activateFallback()
    }

    private func tryTerminalApp(tty: String) -> Bool {
        guard isAppRunning("Terminal") else { return false }
        let script = """
            tell application "Terminal"
                activate
                set targetTTY to "/dev/\(tty)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTTY then
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
        guard isAppRunning("iTerm2") else { return false }
        let script = """
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s contains "\(tty)" then
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

    private func activateTerminalApp() {
        // 按优先级尝试激活终端应用
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
