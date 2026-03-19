import Foundation

/// 监听 ~/.claude/sessions/ 目录，发现活跃的 Claude Code 会话
class SessionDiscovery {
    private let sessionsDir: String
    private let store: SessionStore
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private let fileDescriptor: Int32

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDir = "\(home)/.claude/sessions"
        self.fileDescriptor = open(sessionsDir, O_EVTONLY)
    }

    deinit {
        stop()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    func start() {
        // 首次扫描
        scan()

        // FSEvents 监听目录变化
        guard fileDescriptor >= 0 else {
            print("[SessionDiscovery] ⚠️ 无法打开 sessions 目录: \(sessionsDir)")
            startFallbackTimer()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scan()
        }
        source.resume()
        self.dispatchSource = source

        // 定时补充扫描（清理已退出的进程）
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        timer?.invalidate()
        timer = nil
    }

    private func startFallbackTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func scan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return }

        var discoveredIds = Set<String>()

        for file in files where file.hasSuffix(".json") {
            let path = "\(sessionsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let info = try? JSONDecoder().decode(SessionInfo.self, from: data) else {
                continue
            }

            // 检查进程是否存活
            guard kill(Int32(info.pid), 0) == 0 else { continue }

            var session = Session(from: info)
            session.tty = getTTY(for: info.pid)
            discoveredIds.insert(session.id)
            store.upsert(session)
        }

        // 移除已退出的 Claude 会话（不影响其他 agent 的会话）
        let staleIds = store.activeSessionIds(for: .claude).subtracting(discoveredIds)
        for id in staleIds {
            store.remove(sessionId: id)
        }
    }

    private func getTTY(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
