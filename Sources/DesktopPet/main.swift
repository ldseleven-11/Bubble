import AppKit
import QuartzCore
import Carbon

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, PetViewDelegate {
    var window: PetWindow!
    var petView: PetView!
    var statusItem: NSStatusItem?
    var walkTimer: Timer?
    var stateTimer: Timer?
    var isWalking = false
    var facingLeft = false
    var isClaudeWorking = false
    let settingsController = SettingsWindowController()
    var bubbleWindow: BubbleWindow!
    var bubbleTimer: Timer?

    // 主动关怀
    private var careTimer: Timer?
    private var lastCareTime: Date = .distantPast
    private var workingStartTime: Date?

    // 社交
    let friendPanel = FriendListPanel()
    private var isVisitingOut = false

    // 钉钉通知
    var gateway: AgentGateway?
    var notificationBubble: NotificationBubbleWindow!
    private var dingtalkMenuItem: NSMenuItem?
    private var autoTalkPaused = false
    private var pendingTestCompletion: ((Bool, String?) -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查命令行参数
        let args = CommandLine.arguments
        if let pathIndex = args.firstIndex(of: "--images"), pathIndex + 1 < args.count {
            PetConfig.customImagePath = args[pathIndex + 1]
            print("使用自定义图片目录: \(args[pathIndex + 1])")
        }

        guard let screen = NSScreen.main else { return }
        let winSize = PetConfig.workingSize  // 窗口用最大状态尺寸
        let x = screen.visibleFrame.minX + 10
        let y = screen.visibleFrame.minY + 10

        window = PetWindow(contentRect: NSRect(x: x, y: y, width: winSize, height: winSize))
        petView = PetView(frame: NSRect(x: 0, y: 0, width: winSize, height: winSize))
        petView.delegate = self
        window.contentView = petView
        window.orderFrontRegardless()

        // 状态栏图标
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        if let button = item.button {
            button.title = " BubblePet "
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "编辑语录...", action: #selector(openQuotesFile), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "打开图片目录", action: #selector(openImageFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "好友...", action: #selector(openFriendPanel), keyEquivalent: "f"))

        let dtItem = NSMenuItem(title: "钉钉通知", action: #selector(toggleDingTalk), keyEquivalent: "d")
        dtItem.state = SettingsManager.shared.dingtalkEnabled ? .on : .off
        menu.addItem(dtItem)
        self.dingtalkMenuItem = dtItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        item.menu = menu

        // 添加隐藏的 Edit 菜单，让文本框支持 ⌘C/⌘V/⌘X/⌘A
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu

        // LSUIElement=true in Info.plist handles hiding from Dock
        if Bundle.main.object(forInfoDictionaryKey: "LSUIElement") == nil {
            NSApp.setActivationPolicy(.accessory)
        }

        // 气泡窗口
        bubbleWindow = BubbleWindow()
        notificationBubble = NotificationBubbleWindow()

        startBehavior()
        startBubbleTimer()
        startCareTimer()


        // 设置监控回调
        ClaudeMonitor.shared.onStateChange = { [weak self] isWorking in
            self?.handleWorkingStateChange(isWorking)
        }
        InputMonitor.shared.onStateChange = { [weak self] isWorking in
            self?.handleWorkingStateChange(isWorking)
        }

        // 设置模式切换回调
        settingsController.onMonitorModeChanged = { [weak self] mode in
            self?.switchMonitorMode(mode)
        }
        settingsController.onPetModeChanged = { [weak self] mode in
            self?.switchPetMode(mode)
        }
        settingsController.onPetSizeChanged = { [weak self] in
            self?.resizePet()
        }

        // 根据设置启动对应的监控
        switchMonitorMode(SettingsManager.shared.monitorMode)

        // 根据设置启动对应的宠物形象
        let savedPetMode = SettingsManager.shared.petMode
        if savedPetMode >= 1 && SettingsManager.shared.hasCustomImage(slot: savedPetMode) {
            switchPetMode(savedPetMode)
        }

        // 启动社交功能
        setupSocial()

        // 启动钉钉监控（如果已启用）
        setupDingTalk()

        // 新手引导
        OnboardingManager.shared.onFinished = { [weak self] in
            self?.settingsController.showSettings()
        }
        OnboardingManager.shared.startIfNeeded(petWindow: window)
    }

    // MARK: - 社交

    func setupSocial() {
        let social = SocialManager.shared

        social.getHostWindow = { [weak self] in
            return self?.window
        }

        social.onShowBubble = { [weak self] text in
            guard let self = self else { return }
            self.bubbleWindow.show(text: text, above: self.window)
        }

        social.onVisitOut = { [weak self] in
            guard let self = self else { return }
            self.isVisitingOut = true
            // 宠物半透明，行为暂停
            self.stopWalking()
            self.stateTimer?.invalidate()
            self.stateTimer = nil
            self.stopBubbleTimer()
            self.petView.alphaValue = 0.3
            self.petView.switchState(.visiting, layerSize: PetConfig.size)
        }

        social.onVisitBack = { [weak self] in
            guard let self = self else { return }
            self.isVisitingOut = false
            // 恢复宠物
            self.petView.alphaValue = 1.0
            self.petView.switchState(.idle, layerSize: PetConfig.size)
            self.startBehavior()
            self.startBubbleTimer()
            self.bubbleWindow.show(text: "回来啦~", above: self.window)
        }

        social.onVisitorArrived = { [weak self] in
            NSLog("[Social] Visitor arrived!")
            _ = self // keep reference
        }

        social.onVisitorLeft = { [weak self] in
            NSLog("[Social] Visitor left!")
            _ = self
        }

        social.start()
    }

    @objc func openFriendPanel() {
        friendPanel.showPanel()
    }

    // MARK: - 钉钉通知

    func setupDingTalk() {
        let monitor = DingTalkMonitor.shared

        // 注入用户工作状态
        monitor.getIsWorking = { [weak self] in
            return self?.isClaudeWorking ?? false
        }

        // 通知回调：错误 → 弹 Alert 引导去设置；正常 → 弹气泡
        monitor.onNotification = { [weak self] notification in
            guard let self = self else { return }
            self.autoTalkPaused = true
            self.stopBubbleTimer()
            self.stopWalking()
            self.petView.switchState(.idle, layerSize: PetConfig.size)

            if notification.isError {
                let alert = NSAlert()
                alert.messageText = "消息发送失败"
                let mode = SettingsManager.shared.aiMode
                if mode == 1 {
                    alert.informativeText = "\(notification.summary)\n\n请检查 API Key 设置是否正确。"
                } else {
                    alert.informativeText = "\(notification.summary)\n\n请检查 OpenClaw 连接设置是否正确。"
                }
                alert.addButton(withTitle: "去设置")
                alert.addButton(withTitle: "关闭")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.settingsController.showSettings(selectTab: 1)
                }
                self.autoTalkPaused = false
                self.startBubbleTimer()
            } else {
                self.notificationBubble.showNotification(
                    summary: notification.summary,
                    sessionKey: notification.sessionKey,
                    isError: notification.isError,
                    above: self.window,
                    scene: notification.scene,
                    originalMessage: notification.originalMessage
                )
            }
        }

        // 通知气泡自然消失（非点击）且队列空 → 恢复自动说话
        notificationBubble.onAutoHideComplete = { [weak self] in
            guard let self = self else { return }
            // 如果回复面板还开着，等面板关了再恢复
            if !ReplyInputPanel.shared.isVisible {
                self.autoTalkPaused = false
                self.startBubbleTimer()
            }
        }

        // 点击气泡回调：错误 → 引导去设置；正常 → 打开回复面板
        notificationBubble.onTapWithContext = { [weak self] sessionKey, scene, originalMessage, isError in
            guard let self = self else { return }
            if isError {
                self.settingsController.showSettings(selectTab: 1)
            } else {
                ReplyInputPanel.shared.show(
                    sessionKey: sessionKey,
                    scene: scene,
                    originalMessage: originalMessage,
                    above: self.window
                )
            }
        }

        // 回复面板关闭但没发送（Esc / ×）→ 恢复自动说话
        ReplyInputPanel.shared.onDismissWithoutSend = { [weak self] in
            self?.autoTalkPaused = false
            self?.startBubbleTimer()
        }

        // 注入发送回调
        ReplyInputPanel.shared.onSendMessage = { [weak self] sessionKey, message, completion in
            let mode = SettingsManager.shared.aiMode
            if mode == 1 {
                // 聪明模式：直接调 LLM API
                let petName = SettingsManager.shared.petName
                let personality = PersonalityPreset.currentPrompt()
                let prompt = """
                你是一只桌面宠物，名叫\(petName)，陪伴主人打工。
                你的说话风格：\(personality)
                主人对你说："\(message)"
                请用简短口语化的方式回复（50字以内），要符合你的性格。只输出回复内容。
                """
                AIEngine.shared.generate(prompt: prompt) { result in
                    DispatchQueue.main.async {
                        if let reply = result, !reply.isEmpty {
                            completion(true, nil)
                            // 构造回复通知
                            let cleaned = reply.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                            let notification = DingTalkNotification(
                                summary: cleaned,
                                sessionKey: sessionKey,
                                isError: false,
                                timestamp: Date(),
                                originalMessage: cleaned,
                                scene: .myDirectChat
                            )
                            DingTalkMonitor.shared.onNotification?(notification)
                        } else {
                            completion(false, "AI 未返回结果，请检查 API Key")
                        }
                    }
                }
            } else if mode == 2 {
                // 助手模式：走 OpenClaw Gateway
                guard let gw = self?.gateway else {
                    completion(false, "未连接")
                    return
                }
                gw.send(sessionKey: sessionKey, message: message, completion: completion)
            } else {
                completion(false, "未启用 AI 能力")
            }
        }

        // 测试 OpenClaw 连接回调：测试全链路（OpenClaw → 大模型 → 响应）
        settingsController.onTestOpenClaw = { [weak self] completion in
            guard let self = self, let gw = self.gateway else {
                completion(false, "OpenClaw 未连接，请先启用并保存设置")
                return
            }

            self.pendingTestCompletion = completion

            // 15 秒超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                if let cb = self?.pendingTestCompletion {
                    self?.pendingTestCompletion = nil
                    cb(false, "测试超时，大模型未响应")
                }
            }

            gw.send(sessionKey: "__connection_test__", message: "ping") { [weak self] success, errorMsg in
                if !success {
                    // OpenClaw 拒绝请求
                    if let cb = self?.pendingTestCompletion {
                        self?.pendingTestCompletion = nil
                        cb(false, errorMsg ?? "OpenClaw 拒绝请求")
                    }
                }
                // send 成功只代表 OpenClaw 收到，等 chat 事件回来才知道大模型结果
            }
        }

        // AI 模式切换回调
        settingsController.onAIModeChanged = { [weak self] oldMode, newMode in
            // 离开助手模式：断开 OpenClaw
            if oldMode == 2 && newMode != 2 {
                self?.gateway?.disconnect()
                self?.gateway = nil
                DingTalkMonitor.shared.stop()
                SettingsManager.shared.petNameOverride = nil
                SettingsManager.shared.personalityOverride = nil
            }
            // 进入助手模式：连接 OpenClaw
            if newMode == 2 {
                self?.connectGateway()
                DingTalkMonitor.shared.start()
            }
            self?.dingtalkMenuItem?.state = newMode == 2 ? .on : .off
        }

        // 如果助手模式已启用，立即启动
        if SettingsManager.shared.aiMode == 2 {
            connectGateway()
            monitor.start()
        }
    }

    /// 创建网关实例并连接
    private func connectGateway() {
        let settings = SettingsManager.shared
        let token = settings.openclawToken
        guard !token.isEmpty else {
            NSLog("[AppDelegate] No gateway token configured")
            return
        }

        // 断开旧连接
        gateway?.disconnect()

        let gw = OpenClawGateway(
            host: settings.gatewayHost,
            port: settings.gatewayPort,
            token: token
        )
        self.gateway = gw

        // 事件路由（拦截测试会话）
        let monitor = DingTalkMonitor.shared
        gw.onMessage = { [weak self] event in
            if event.sessionKey == "__connection_test__" {
                if event.state == "error", let cb = self?.pendingTestCompletion {
                    self?.pendingTestCompletion = nil
                    cb(false, event.errorMessage ?? "大模型返回错误")
                } else if event.state == "final", let cb = self?.pendingTestCompletion {
                    self?.pendingTestCompletion = nil
                    cb(true, nil)
                }
                return
            }
            monitor.handleChatEvent(event)
        }
        gw.onIdentityLoaded = { name, personality in
            SettingsManager.shared.petNameOverride = name
            SettingsManager.shared.personalityOverride = personality
            NSLog("[DingTalk] Agent identity applied: name=%@", name)
        }
        gw.onConnectionChange = { connected in
            NSLog("[AppDelegate] Gateway connected: %@", connected ? "true" : "false")
        }

        gw.connect()
    }

    func openChat() {
        let mode = SettingsManager.shared.aiMode
        if mode == 0 {
            let alert = NSAlert()
            alert.messageText = "需要先启用 AI 能力"
            alert.informativeText = "在设置中选择「聪明模式」或「助手模式」后，才能和宠物对话哦~"
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                settingsController.showSettings(selectTab: 1)
            }
            return
        }
        if mode == 2 && gateway == nil {
            let alert = NSAlert()
            alert.messageText = "OpenClaw 未连接"
            alert.informativeText = "助手模式需要 OpenClaw 连接，请检查设置。"
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                settingsController.showSettings(selectTab: 1)
            }
            return
        }

        // 暂停自动说话（同通知逻辑）
        autoTalkPaused = true
        stopBubbleTimer()
        stopWalking()
        petView.switchState(.idle, layerSize: PetConfig.size)

        ReplyInputPanel.shared.show(
            sessionKey: "agent:main:main",
            scene: .myDirectChat,
            originalMessage: nil,
            above: window
        )
    }

    @objc func toggleDingTalk() {
        let enabled = !SettingsManager.shared.dingtalkEnabled
        SettingsManager.shared.dingtalkEnabled = enabled
        dingtalkMenuItem?.state = enabled ? .on : .off

        if enabled {
            connectGateway()
            DingTalkMonitor.shared.start()
        } else {
            gateway?.disconnect()
            gateway = nil
            DingTalkMonitor.shared.stop()
            SettingsManager.shared.petNameOverride = nil
            SettingsManager.shared.personalityOverride = nil
        }
    }

    func openDingTalkConversation(sessionKey: String) {
        // 已知的钉钉 Mac 版 bundle ID
        let bundleIDs = [
            "com.alibaba.DingTalkMac",
            "com.alibaba.DingTalk",
            "com.alibaba.dingtalk.mac"
        ]

        // 先找已经在运行的钉钉
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased() else { continue }
            if bid.contains("dingtalk") || bid.contains("ding") {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                return
            }
        }

        // 没运行，尝试启动
        for bid in bundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                return
            }
        }

        // 最后尝试 URL scheme
        if let url = URL(string: "dingtalk://") {
            NSWorkspace.shared.open(url)
        }
    }

    func switchMonitorMode(_ mode: Int) {
        // 先停掉两个
        ClaudeMonitor.shared.stopMonitoring()
        InputMonitor.shared.stopMonitoring()
        // 重置工作状态
        handleWorkingStateChange(false)

        if mode == 1 {
            ClaudeMonitor.shared.startMonitoring()
        } else {
            InputMonitor.shared.startMonitoring()
        }
    }

    func resizePet() {
        let winSize = PetConfig.workingSize
        let origin = window.frame.origin
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: winSize, height: winSize), display: true)
        petView.frame = NSRect(x: 0, y: 0, width: winSize, height: winSize)
        // 刷新当前图层尺寸
        let isCustom = petView.isCustomMode
        if isClaudeWorking && !isCustom {
            petView.setLayerSize(PetConfig.workingSize)
        } else {
            petView.setLayerSize(PetConfig.size)
        }
    }

    func switchPetMode(_ mode: Int) {
        if mode >= 1 {
            // 自定义图片模式（槽位 1/2/3）
            let slot = mode
            guard SettingsManager.shared.hasCustomImage(slot: slot) else {
                SettingsManager.shared.petMode = 0
                switchPetMode(0)
                return
            }
            petView.isCustomMode = true
            petView.stopCustomAnimations()
            _ = petView.animationManager.loadCustomImage(slot: slot)
            petView.setLayerSize(PetConfig.size)
            let currentState: PetState = isClaudeWorking ? .working : .idle
            petView.setState(currentState)
            petView.applyCustomAnimation(for: currentState)
        } else {
            // 皮卡丘模式
            petView.isCustomMode = false
            petView.stopCustomAnimations()
            petView.animationManager.loadAllAnimations()
            let currentState: PetState = isClaudeWorking ? .working : .idle
            let layerSize = isClaudeWorking ? PetConfig.workingSize : PetConfig.size
            petView.switchState(currentState, layerSize: layerSize)
        }
    }

    func handleWorkingStateChange(_ isWorking: Bool) {
        let wasWorking = isClaudeWorking
        isClaudeWorking = isWorking
        let isCustom = petView.isCustomMode

        // 记录工作开始时间
        if isWorking && !wasWorking {
            workingStartTime = Date()
        } else if !isWorking {
            workingStartTime = nil
        }

        // 通知钉钉监控用户活跃状态变化
        if wasWorking != isWorking {
            DingTalkMonitor.shared.userActivityChanged(isWorking: isWorking)
        }

        if !isWalking {
            if isWorking {
                if isCustom {
                    petView.switchState(.working, layerSize: PetConfig.size)
                } else {
                    petView.switchState(.working, layerSize: PetConfig.workingSize)
                }
            } else {
                petView.switchState(.idle, layerSize: PetConfig.size)
            }
        }
    }

    // MARK: - 主动关怀

    func startCareTimer() {
        careTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkCare()
        }
    }

    private func checkCare() {
        let now = Date()
        // 防止频繁提醒（至少间隔30分钟）
        guard now.timeIntervalSince(lastCareTime) > 1800 else { return }
        guard isClaudeWorking else { return }

        let hour = Calendar.current.component(.hour, from: now)

        // 晚归提醒
        if hour >= 22 {
            lastCareTime = now
            showCareBubble("都这么晚了还在干活…早点休息吧")
            return
        }
        if hour >= 21 {
            lastCareTime = now
            showCareBubble("已经9点多了，差不多可以收工了吧？")
            return
        }

        // 连续工作提醒
        if let start = workingStartTime, now.timeIntervalSince(start) > 7200 {
            lastCareTime = now
            workingStartTime = now // 重置，避免持续提醒
            showCareBubble("你已经连续干了2个小时了，站起来走走吧")
            return
        }
    }

    private func showCareBubble(_ text: String) {
        guard !autoTalkPaused else { return }
        if SettingsManager.shared.apiKey != nil {
            // 有 API Key 时用 LLM 生成更自然的关怀语
            let petName = SettingsManager.shared.petName
            let personality = PersonalityPreset.currentPrompt()
            let hour = Calendar.current.component(.hour, from: Date())

            let prompt = """
            你是一只桌面宠物，名叫\(petName)。
            你的性格：\(personality)
            主人在深夜\(hour)点还在工作，或者已经连续工作很久了。
            请用1句简短的话（15字以内）关心一下主人，让主人休息。
            要求符合你的性格，口语化。只输出这一句话。
            """

            AIEngine.shared.generate(prompt: prompt) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, !self.autoTalkPaused else { return }
                    if let generated = result, !generated.isEmpty {
                        let cleaned = generated.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                        self.bubbleWindow.show(text: cleaned, above: self.window)
                    } else {
                        self.bubbleWindow.show(text: text, above: self.window)
                    }
                }
            }
        } else {
            bubbleWindow.show(text: text, above: window)
        }
    }

    // MARK: - 气泡

    func startBubbleTimer() {
        guard bubbleTimer == nil else { return }
        showRandomBubble()
        scheduleBubble()
    }

    func stopBubbleTimer() {
        bubbleTimer?.invalidate()
        bubbleTimer = nil
        bubbleWindow.hideBubble()
    }

    private func scheduleBubble() {
        let interval = Double.random(in: 8...15)
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.showRandomBubble()
            self.scheduleBubble()
        }
    }

    func showRandomBubble() {
        guard !OnboardingManager.shared.isOnboarding else { return }
        guard !autoTalkPaused else { return }
        let ownerState = isClaudeWorking ? "正在工作" : "空闲"

        AIEngine.shared.generateQuote(ownerState: ownerState) { [weak self] quote in
            guard let self = self, !self.autoTalkPaused else { return }
            self.bubbleWindow.show(text: quote, above: self.window)
        }
    }

    @objc func openSettings() {
        settingsController.showSettings()
    }

    @objc func openQuotesFile() {
        let path = SettingsManager.shared.appSupportDir + "/quotes.txt"
        _ = WorkerQuotes.shared
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func openImageFolder() {
        let resourcePath: String
        if let custom = PetConfig.customImagePath {
            resourcePath = custom
        } else {
            let execPath = Bundle.main.bundlePath
            resourcePath = (execPath as NSString).deletingLastPathComponent + "/Resources"
        }

        if !FileManager.default.fileExists(atPath: resourcePath) {
            try? FileManager.default.createDirectory(atPath: resourcePath, withIntermediateDirectories: true)
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: resourcePath))
    }

    func startBehavior() {
        stateTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.randomBehavior()
        }
    }

    func randomBehavior() {
        guard !petView.isDragging else { return }
        guard !isVisitingOut else { return }
        guard !autoTalkPaused else { return }  // 有通知/回复面板时站住不动

        let rand = Int.random(in: 0...2)
        if rand >= 1 {
            stopWalking()
            if isClaudeWorking {
                let workSize = petView.isCustomMode ? PetConfig.size : PetConfig.workingSize
                petView.switchState(.working, layerSize: workSize)
                startBubbleTimer()
            } else {
                petView.switchState(.idle, layerSize: PetConfig.size)
                stopBubbleTimer()
            }
        } else {
            stopWalking()
            facingLeft = Bool.random()
            petView.setFacingLeft(facingLeft)
            petView.switchState(.walk, layerSize: PetConfig.size)
            startWalking()
            startBubbleTimer()
        }
    }

    func startWalking() {
        guard !isWalking else { return }
        isWalking = true
        walkTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            self?.walk()
        }
    }

    func stopWalking() {
        isWalking = false
        walkTimer?.invalidate()
        walkTimer = nil
    }

    func getActivityBounds() -> (minX: CGFloat, maxX: CGFloat) {
        guard let screen = NSScreen.main else { return (0, 0) }
        let sf = screen.visibleFrame
        let mode = SettingsManager.shared.activityRange
        switch mode {
        case 1: return (sf.minX, sf.midX)
        case 2: return (sf.midX, sf.maxX)
        case 3: return (sf.minX, sf.minX + sf.width / 3)
        case 4: return (sf.minX + sf.width * 2 / 3, sf.maxX)
        case 5: return (sf.minX, sf.minX + sf.width / 4)
        case 6: return (sf.minX + sf.width * 3 / 4, sf.maxX)
        case 7:
            let x = window.frame.origin.x
            return (x, x + window.frame.width)  // 原地踏步：bounds=窗口宽度，walk动画播放但不位移
        default: return (sf.minX, sf.maxX)
        }
    }

    func walk() {
        guard !petView.isDragging else { return }

        // 原地踏步：只播放走路动画，不位移
        if SettingsManager.shared.activityRange == 7 { return }

        let bounds = getActivityBounds()
        var frame = window.frame
        let speed = PetConfig.walkSpeed

        frame.origin.x += facingLeft ? -speed : speed

        if frame.minX <= bounds.minX {
            frame.origin.x = bounds.minX
            facingLeft = false
            petView.setFacingLeft(false)
        } else if frame.maxX >= bounds.maxX {
            frame.origin.x = bounds.maxX - frame.width
            facingLeft = true
            petView.setFacingLeft(true)
        }

        window.setFrameOrigin(frame.origin)
    }

    // MARK: - PetViewDelegate
    func petDidStartDrag() {
        stopWalking()
    }

    func petDidEndDrag() {
        if isClaudeWorking {
            petView.setState(.working)
        }
    }

    func petDidHover(_ hovering: Bool) {
        // 不因 hover 停止走路
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
