import AppKit

// MARK: - Claude 进程监控
class ClaudeMonitor {
    static let shared = ClaudeMonitor()
    private var timer: Timer?
    private var isClaudeActive = false
    var onStateChange: ((Bool) -> Void)?

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClaudeActivity()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClaudeActivity() {
        // 检查 claude 相关进程的 CPU 使用率
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps aux | grep -i '[c]laude' | awk '{sum += $3} END {print sum+0}'"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let cpuUsage = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let newState = cpuUsage > 5.0  // CPU 使用率超过 5% 认为在工作
                if newState != isClaudeActive {
                    isClaudeActive = newState
                    DispatchQueue.main.async {
                        self.onStateChange?(newState)
                    }
                }
            }
        } catch {
            // 忽略错误
        }
    }
}

// MARK: - 键鼠输入监控
class InputMonitor {
    static let shared = InputMonitor()
    private var globalMonitors: [Any] = []
    private var checkTimer: Timer?
    private var lastInputTime: Date = .distantPast
    private var continuousStartTime: Date?
    private var isActive = false
    var onStateChange: ((Bool) -> Void)?

    private let activateThreshold: TimeInterval = 2.0   // 持续输入2秒触发
    private let deactivateThreshold: TimeInterval = 4.0  // 停止输入4秒恢复

    // 连续工作开始时间（用于主动关怀）
    private(set) var workingStartTime: Date?

    func startMonitoring() {
        stopMonitoring()

        // 检查并请求辅助功能权限
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            NSLog("[DesktopPet] 需要辅助功能权限才能监听键鼠输入，已弹出授权提示")
        }

        let eventMask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            self?.handleInput()
        }
        if let monitor = monitor {
            globalMonitors.append(monitor)
        }

        // 也监听本地事件（当自己的窗口在前台时）
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleInput()
            return event
        }
        if let localMonitor = localMonitor {
            globalMonitors.append(localMonitor)
        }

        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkState()
        }
    }

    func stopMonitoring() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()
        checkTimer?.invalidate()
        checkTimer = nil
        if isActive {
            isActive = false
            onStateChange?(false)
        }
        continuousStartTime = nil
        workingStartTime = nil
    }

    private func handleInput() {
        let now = Date()
        // 如果距离上次输入超过1秒，重置连续计时
        if now.timeIntervalSince(lastInputTime) > 1.0 {
            continuousStartTime = now
        }
        lastInputTime = now
    }

    private func checkState() {
        let now = Date()
        let timeSinceLastInput = now.timeIntervalSince(lastInputTime)

        if !isActive {
            // 检查是否持续输入超过阈值
            if let start = continuousStartTime, timeSinceLastInput < 1.0 {
                if now.timeIntervalSince(start) >= activateThreshold {
                    isActive = true
                    workingStartTime = now
                    DispatchQueue.main.async {
                        self.onStateChange?(true)
                    }
                }
            }
        } else {
            // 检查是否停止输入超过冷却时间
            if timeSinceLastInput >= deactivateThreshold {
                isActive = false
                continuousStartTime = nil
                workingStartTime = nil
                DispatchQueue.main.async {
                    self.onStateChange?(false)
                }
            }
        }
    }
}
