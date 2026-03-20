import Foundation

/// 监听 ~/.claude/sessions/ 目录，发现活跃的 Claude Code 会话
/// 如果 sessions 目录不存在（旧版 Claude Code），回退到进程扫描
class SessionDiscovery {
    private let sessionsDir: String
    private let projectsDir: String
    private let store: SessionStore
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var fileDescriptor: Int32 = -1

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDir = "\(home)/.claude/sessions"
        self.projectsDir = "\(home)/.claude/projects"
    }

    deinit {
        stop()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    func start() {
        // 首次扫描
        scan()

        // 尝试打开 sessions 目录进行 FSEvents 监听
        fileDescriptor = open(sessionsDir, O_EVTONLY)

        if fileDescriptor >= 0 {
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
        } else {
            print("[SessionDiscovery] sessions 目录不存在，使用进程扫描模式")
        }

        // 定时扫描（清理已退出进程 + 兼容无 sessions 目录的情况）
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

    func scan() {
        let fm = FileManager.default
        var discoveredIds = Set<String>()

        // 方式 1：从 sessions 目录读取（新版 Claude Code）
        if let files = try? fm.contentsOfDirectory(atPath: sessionsDir) {
            for file in files where file.hasSuffix(".json") {
                let path = "\(sessionsDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let info = try? JSONDecoder().decode(SessionInfo.self, from: data) else {
                    continue
                }
                guard kill(Int32(info.pid), 0) == 0 else { continue }

                var session = Session(from: info)
                session.tty = getTTY(for: info.pid)
                discoveredIds.insert(session.id)
                store.upsert(session)
            }
        }

        // 方式 2：进程扫描回退（旧版 Claude Code 或 sessions 目录为空）
        if discoveredIds.isEmpty {
            discoverViaProcessScan(into: &discoveredIds)
        }

        // 移除已退出的 Claude 会话
        let staleIds = store.activeSessionIds(for: .claude).subtracting(discoveredIds)
        for id in staleIds {
            store.remove(sessionId: id)
        }
    }

    // MARK: - 进程扫描回退

    /// 通过 pgrep + lsof 发现 claude 进程，再匹配 projects 下的 jsonl
    private func discoverViaProcessScan(into discoveredIds: inout Set<String>) {
        guard let pids = getClaudePids(), !pids.isEmpty else { return }

        for pid in pids {
            guard let cwd = getCwd(for: pid) else { continue }

            // 在 projects 目录下找到对应 cwd 的 jsonl 文件
            let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
            let projectDir = "\(projectsDir)/\(encodedCwd)"

            guard let sessionId = findActiveSessionId(in: projectDir) else { continue }

            let session = Session(
                id: sessionId,
                pid: pid,
                cwd: cwd,
                startedAt: getProcessStartTime(pid: pid) ?? Date(),
                agentType: .claude
            )
            var mutableSession = session
            mutableSession.tty = getTTY(for: pid)
            discoveredIds.insert(sessionId)
            store.upsert(mutableSession)
        }
    }

    /// 在 project 目录下找最近修改的 jsonl 文件的 sessionId
    private func findActiveSessionId(in projectDir: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }

        var bestFile: (name: String, date: Date)?
        for file in files where file.hasSuffix(".jsonl") {
            let path = "\(projectDir)/\(file)"
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                if bestFile == nil || modDate > bestFile!.date {
                    bestFile = (file, modDate)
                }
            }
        }

        // 返回文件名去掉 .jsonl 就是 sessionId
        guard let best = bestFile else { return nil }
        return String(best.name.dropLast(6)) // remove ".jsonl"
    }

    private func getClaudePids() -> [Int]? {
        guard let output = runProcess("/usr/bin/pgrep", args: ["-x", "claude"]) else { return nil }
        return output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func getCwd(for pid: Int) -> String? {
        guard let output = runProcess("/usr/sbin/lsof", args: ["-p", "\(pid)", "-Fn"]) else { return nil }
        // lsof 输出格式：每行 f(fd) 或 n(name)，找 cwd 对应的 name
        var foundCwd = false
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s == "fcwd" { foundCwd = true; continue }
            if foundCwd && s.hasPrefix("n") {
                return String(s.dropFirst()) // 去掉 "n" 前缀
            }
            if s.hasPrefix("f") { foundCwd = false }
        }
        return nil
    }

    private func getProcessStartTime(pid: Int) -> Date? {
        guard let output = runProcess("/bin/ps", args: ["-o", "lstart=", "-p", "\(pid)"]) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        return formatter.date(from: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Helpers

    private func getTTY(for pid: Int) -> String? {
        guard let output = runProcess("/bin/ps", args: ["-o", "tty=", "-p", "\(pid)"]) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
