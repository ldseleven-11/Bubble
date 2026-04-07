import Foundation

// MARK: - 钉钉消息通知

enum ChatScene {
    case myDirectChat       // 我自己跟 agent 单聊
    case groupChat(String)  // 群聊里 @agent，参数是群名
    case othersPrivate      // 别人私聊 agent
}

struct DingTalkNotification {
    let summary: String
    let sessionKey: String
    let isError: Bool
    let timestamp: Date
    let originalMessage: String?   // 原始消息（回复面板用）
    let scene: ChatScene           // 聊天场景
}

struct ChatRecord {
    let userMessage: String
    let agentReply: String
    let timestamp: Date
    let sessionKey: String
}

class DingTalkMonitor {
    static let shared = DingTalkMonitor()

    var onNotification: ((DingTalkNotification) -> Void)?

    /// 外部注入：获取用户当前是否正在工作
    var getIsWorking: (() -> Bool)?

    /// 外部注入：监听用户从不活跃变为活跃
    var onUserReturned: (() -> Void)?

    /// 最近对话记录（最多 5 条）
    private(set) var recentChats: [ChatRecord] = []
    private let maxChatRecords = 5

    /// 待配对的用户消息（sessionKey → message）
    private var pendingUserMessages: [String: String] = [:]

    private var isRunning = false
    private var pendingQueue: [DingTalkNotification] = []
    private let maxQueueSize = 5

    /// 跟踪每个 session 的最新消息（用于判断"用户自己 vs 别人"）
    /// key: sessionKey, value: 最近的用户输入 runId
    private var sessionTracker: [String: SessionInfo] = [:]

    /// 用户长时间不活跃的阈值（5分钟）
    private let longAbsenceThreshold: TimeInterval = 300
    private var lastActiveTime: Date = Date()
    private var wasLongAbsent = false

    /// 工作中时的检查定时器
    private var deliveryTimer: Timer?

    private struct SessionInfo {
        var lastUserMessageTime: Date?
        var isWaitingReply: Bool = false
        var senderName: String?
        var accumulatedMessage: String = ""  // 累积 delta 消息
    }

    // MARK: - 启动/停止

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // 启动投递检查（每2秒检查一次是否可以投递队列中的通知）
        deliveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkDelivery()
        }

        NSLog("[DingTalk] Monitor started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        deliveryTimer?.invalidate()
        deliveryTimer = nil
        pendingQueue.removeAll()
        sessionTracker.removeAll()
        pendingUserMessages.removeAll()

        NSLog("[DingTalk] Monitor stopped")
    }

    // MARK: - 聊天记录

    /// 由 ReplyInputPanel 调用，记录用户发送的消息（等待 agent 回复后配对）
    func recordUserMessage(sessionKey: String, message: String) {
        pendingUserMessages[sessionKey] = message
        NSLog("[DingTalk] Recorded user message for session: %@", sessionKey)
    }

    private func addChatRecord(userMessage: String, agentReply: String, sessionKey: String) {
        let record = ChatRecord(
            userMessage: userMessage,
            agentReply: agentReply,
            timestamp: Date(),
            sessionKey: sessionKey
        )
        recentChats.append(record)
        if recentChats.count > maxChatRecords {
            recentChats.removeFirst()
        }
        NSLog("[DingTalk] Chat record added, total: %d", recentChats.count)
    }

    // MARK: - 用户状态感知

    /// 由 AppDelegate 调用，通知用户活跃状态变化
    func userActivityChanged(isWorking: Bool) {
        let now = Date()
        if isWorking {
            // 从不活跃变为活跃
            let absenceDuration = now.timeIntervalSince(lastActiveTime)
            if absenceDuration >= longAbsenceThreshold && !pendingQueue.isEmpty {
                // 用户刚回来，合并发送汇总
                wasLongAbsent = true
                deliverSummary()
            }
            lastActiveTime = now
        } else {
            // 变为不活跃 → 尝试投递队列
            if !pendingQueue.isEmpty {
                deliverAll()
            }
            lastActiveTime = now
        }
    }

    // MARK: - 场景判断

    private func detectScene(_ event: ChatEvent) -> ChatScene {
        let key = event.sessionKey
        // agent:main:dingtalk:group:xxx → 群聊
        if key.contains(":group:") {
            let groupName = event.conversationTitle ?? "群聊"
            return .groupChat(groupName)
        }
        // 用 dingtalkUserId 识别"我的"私聊
        let myUserId = SettingsManager.shared.dingtalkUserId
        if !myUserId.isEmpty && key.contains(myUserId) {
            return .myDirectChat
        }
        // agent:main:main 也算我自己的直接会话（兜底）
        if key == "agent:main:main" {
            return .myDirectChat
        }
        // 其他 → 别人私聊
        return .othersPrivate
    }

    // MARK: - 事件处理

    func handleChatEvent(_ event: ChatEvent) {
        let key = event.sessionKey
        NSLog("[DingTalk] handleChatEvent: sessionKey=%@ state=%@ msg=%@", key, event.state, event.message?.prefix(50).description ?? "nil")

        // 初始化 session 追踪
        if sessionTracker[key] == nil {
            sessionTracker[key] = SessionInfo()
        }

        // delta 事件：累积流式消息内容
        if event.state == "delta" {
            sessionTracker[key]?.isWaitingReply = false
            if let msg = event.message {
                sessionTracker[key]?.accumulatedMessage += msg
            }
            return
        }

        let scene = detectScene(event)

        // error 事件：agent 回复失败（第一人称）
        if event.state == "error" {
            let errorMsg = event.errorMessage ?? "未知错误"
            let summary: String
            switch scene {
            case .myDirectChat:
                summary = "你问的那个我没答上来…(\(errorMsg))"
            case .groupChat(let group):
                summary = "我在\(group)没回上来…你帮我看看？"
            case .othersPrivate:
                summary = "有人找我但我没答上来…你帮我看看？"
            }

            let notification = DingTalkNotification(
                summary: summary,
                sessionKey: key,
                isError: true,
                timestamp: Date(),
                originalMessage: event.errorMessage,
                scene: scene
            )
            scheduleNotification(notification)
            return
        }

        // final 事件：一轮对话完成
        if event.state == "final" {
            // 优先用 final 自带的 message，否则用累积的 delta 消息
            let message = event.message ?? sessionTracker[key]?.accumulatedMessage
            // 清空累积
            sessionTracker[key]?.accumulatedMessage = ""
            guard let message = message, !message.isEmpty else { return }

            // 配对聊天记录：如果有待配对的用户消息，生成一条 ChatRecord
            if let userMsg = pendingUserMessages.removeValue(forKey: key) {
                addChatRecord(userMessage: userMsg, agentReply: message, sessionKey: key)
            }

            generateNotification(message: message, sessionKey: key, scene: scene)
        }
    }

    private func generateNotification(message: String, sessionKey: String, scene: ChatScene) {
        // myDirectChat：直接显示原文，不做 AI 总结
        if case .myDirectChat = scene {
            let truncated = message.count > 80 ? String(message.prefix(80)) + "…" : message
            let notification = DingTalkNotification(
                summary: truncated,
                sessionKey: sessionKey,
                isError: false,
                timestamp: Date(),
                originalMessage: message,
                scene: scene
            )
            scheduleNotification(notification)
            return
        }

        let petName = SettingsManager.shared.petName

        if message.count < 30 {
            // 短消息，第一人称展示
            let summary: String
            switch scene {
            case .myDirectChat:
                summary = message // 不会走到这里，上面已 return
            case .groupChat(let group):
                summary = "我在\(group)回了：\(message)"
            case .othersPrivate:
                summary = "有人找我，我回了：\(message)"
            }

            let notification = DingTalkNotification(
                summary: summary,
                sessionKey: sessionKey,
                isError: false,
                timestamp: Date(),
                originalMessage: message,
                scene: scene
            )
            scheduleNotification(notification)
        } else {
            // 长消息，调 AI 生成摘要（第一人称）
            let personality = PersonalityPreset.currentPrompt()
            let sceneHint: String
            switch scene {
            case .myDirectChat:
                sceneHint = "回复主人" // 不会走到这里
            case .groupChat(let group):
                sceneHint = "在\(group)中回复"
            case .othersPrivate:
                sceneHint = "回复别人私聊"
            }

            let prompt = """
            你是\(petName)，你刚在钉钉\(sceneHint)了一条消息，内容如下：
            「\(message)」
            你的性格：\(personality)

            请用第一人称、1句话（20字以内）简短转述你刚回复的核心意思。
            要求：说意图不说原文，口语化，自然。只输出这一句话。
            """

            AIEngine.shared.generate(prompt: prompt) { [weak self] result in
                DispatchQueue.main.async {
                    let summary: String
                    if let generated = result, !generated.isEmpty {
                        summary = generated.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                    } else {
                        let truncated = String(message.prefix(25))
                        summary = "我刚回了：\(truncated)…"
                    }

                    let notification = DingTalkNotification(
                        summary: summary,
                        sessionKey: sessionKey,
                        isError: false,
                        timestamp: Date(),
                        originalMessage: message,
                        scene: scene
                    )
                    self?.scheduleNotification(notification)
                }
            }
        }
    }

    // MARK: - 通知调度

    private func scheduleNotification(_ notification: DingTalkNotification) {
        let isWorking = getIsWorking?() ?? false
        NSLog("[DingTalk] scheduleNotification: isWorking=%@ summary=%@", isWorking ? "true" : "false", notification.summary.prefix(30).description)

        if isWorking {
            // 用户正在工作，进队列
            pendingQueue.append(notification)
            if pendingQueue.count > maxQueueSize {
                pendingQueue.removeFirst()
            }
            NSLog("[DingTalk] queued (pendingQueue=%d)", pendingQueue.count)
        } else {
            // 用户空闲，立即投递
            NSLog("[DingTalk] delivering immediately")
            deliverNotification(notification)
        }
    }

    /// 定时检查是否可以投递
    private func checkDelivery() {
        let isWorking = getIsWorking?() ?? false
        if !isWorking && !pendingQueue.isEmpty {
            deliverAll()
        }
    }

    private func deliverAll() {
        let notifications = pendingQueue
        pendingQueue.removeAll()

        if notifications.count == 1 {
            deliverNotification(notifications[0])
        } else if notifications.count > 1 {
            // 多条消息合并为汇总
            deliverBatch(notifications)
        }
    }

    private func deliverSummary() {
        let notifications = pendingQueue
        pendingQueue.removeAll()
        wasLongAbsent = false

        guard !notifications.isEmpty else { return }

        if notifications.count == 1 {
            deliverNotification(notifications[0])
        } else {
            deliverBatch(notifications)
        }
    }

    private func deliverBatch(_ notifications: [DingTalkNotification]) {
        let count = notifications.count
        let hasError = notifications.contains { $0.isError }
        let lastNotification = notifications.last

        let petName = SettingsManager.shared.petName
        let personality = PersonalityPreset.currentPrompt()

        // 构建批量内容
        let items = notifications.map { $0.summary }.joined(separator: "；")

        if SettingsManager.shared.apiKey != nil {
            let prompt = """
            你是\(petName)。性格：\(personality)
            主人刚回来，你要用第一人称汇报你不在时处理的\(count)条钉钉消息：
            \(items)
            请用1句话（30字以内）汇总。只输出这一句话。
            """

            AIEngine.shared.generate(prompt: prompt) { [weak self] result in
                DispatchQueue.main.async {
                    let summary: String
                    if let generated = result, !generated.isEmpty {
                        summary = generated.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                    } else {
                        summary = "你不在的时候我处理了\(count)条消息~"
                    }

                    let notification = DingTalkNotification(
                        summary: summary,
                        sessionKey: lastNotification?.sessionKey ?? "",
                        isError: hasError,
                        timestamp: Date(),
                        originalMessage: lastNotification?.originalMessage,
                        scene: lastNotification?.scene ?? .othersPrivate
                    )
                    self?.deliverNotification(notification)
                }
            }
        } else {
            let summary = "你不在的时候我处理了\(count)条消息~"
            let notification = DingTalkNotification(
                summary: summary,
                sessionKey: lastNotification?.sessionKey ?? "",
                isError: hasError,
                timestamp: Date(),
                originalMessage: lastNotification?.originalMessage,
                scene: lastNotification?.scene ?? .othersPrivate
            )
            deliverNotification(notification)
        }
    }

    private func deliverNotification(_ notification: DingTalkNotification) {
        DispatchQueue.main.async { [weak self] in
            self?.onNotification?(notification)
        }
    }
}
