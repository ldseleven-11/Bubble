import AppKit

// MARK: - 社交状态
enum SocialState: String {
    case idle           // 空闲
    case requesting     // 发出串门请求中
    case visitingOut    // 宠物出门串门
    case hosting        // 有来客
}

// MARK: - 好友信息
struct FriendInfo {
    let code: String
    var name: String
    var personality: String
    var thumbnail: Data?
    var hasApiKey: Bool
    var isOnline: Bool
    var deliveryMessage: String? = nil  // 带话内容
}

// MARK: - 社交管理器
class SocialManager {
    static let shared = SocialManager()

    private(set) var state: SocialState = .idle
    private(set) var myCode: String = ""
    private var onlineFriends: Set<String> = []
    private var visitingFriendCode: String? // 当前串门对象
    private var hostingFriendCode: String?  // 当前来客
    private var visitorInfo: FriendInfo?    // 来访者信息

    // 超时保护
    private var requestTimer: Timer?
    private var visitTimer: Timer?
    private var dialogueTimer: Timer?
    private var heartbeatTimer: Timer?

    // 对话
    private var currentDialogue: [(speaker: String, text: String)] = []
    private var dialogueIndex = 0

    // 来访宠物窗口
    let visitorWindow = VisitorPetWindow()

    // 回调
    var onVisitOut: (() -> Void)?          // 宠物出门了
    var onVisitBack: (() -> Void)?         // 宠物回来了
    var onVisitorArrived: (() -> Void)?    // 来客到了
    var onVisitorLeft: (() -> Void)?       // 来客走了
    var onShowBubble: ((String) -> Void)?  // 显示气泡
    var onFriendListChanged: (() -> Void)? // 好友列表/状态变化
    var getHostWindow: (() -> NSWindow?)?  // 获取主窗口

    private init() {}

    // MARK: - 启动/停止

    func start() {
        myCode = SettingsManager.shared.socialCode
        NSLog("[Social] My code: \(myCode)")

        // 设置 MQTT
        MQTTService.shared.onMessage = { [weak self] topic, data in
            self?.handleMessage(topic: topic, data: data)
        }
        MQTTService.shared.onConnectionChange = { [weak self] connected in
            guard let self = self else { return }
            NSLog("[Social] MQTT connection changed: \(connected)")
            if connected {
                // 发布上线状态
                MQTTService.shared.publishStatus(code: self.myCode, online: true)
                // 订阅好友状态
                self.subscribeAllFriends()
                NSLog("[Social] Published online status and subscribed friends: \(SettingsManager.shared.friendList.keys)")
                // 启动心跳：每 30 秒重发在线状态，确保好友能感知
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    MQTTService.shared.publishStatus(code: self.myCode, online: true)
                }
            } else {
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil
            }
        }

        // 连接 MQTT
        MQTTService.shared.connect(clientId: myCode)

        // 订阅自己的 inbox 和 chat
        MQTTService.shared.subscribe(topic: MQTTService.shared.inboxTopic(for: myCode))
        MQTTService.shared.subscribe(topic: MQTTService.shared.chatTopic(for: myCode))
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        MQTTService.shared.publishStatus(code: myCode, online: false)
        MQTTService.shared.disconnect()
        cancelAllTimers()
    }

    // MARK: - 好友管理

    func subscribeAllFriends() {
        let friends = SettingsManager.shared.friendList
        for code in friends.keys {
            MQTTService.shared.subscribe(topic: MQTTService.shared.statusTopic(for: code))
        }
    }

    func addFriend(code: String) {
        let upperCode = code.uppercased()
        guard upperCode != myCode else { return }
        guard !SettingsManager.shared.isFriend(upperCode) else { return }

        SettingsManager.shared.addFriend(code: upperCode, name: upperCode)
        MQTTService.shared.subscribe(topic: MQTTService.shared.statusTopic(for: upperCode))
        // 重新发布自己的在线状态（retained），让对方订阅时能收到
        MQTTService.shared.publishStatus(code: myCode, online: true)
        onFriendListChanged?()
    }

    func removeFriend(code: String) {
        SettingsManager.shared.removeFriend(code: code)
        MQTTService.shared.unsubscribe(topic: MQTTService.shared.statusTopic(for: code))
        onlineFriends.remove(code)
        onFriendListChanged?()
    }

    func isFriendOnline(_ code: String) -> Bool {
        return onlineFriends.contains(code)
    }

    // MARK: - 串门

    private var pendingDeliveryMessage: String?  // 访客方暂存带话内容

    func requestVisit(to friendCode: String, message: String? = nil) {
        guard state == .idle else {
            NSLog("[Social] Cannot visit: state=\(state)")
            return
        }
        guard SettingsManager.shared.isFriend(friendCode) else { return }

        state = .requesting
        visitingFriendCode = friendCode
        pendingDeliveryMessage = message

        // 发送 visit_request
        let thumbnail = generateThumbnail()
        var innerPayload: [String: Any] = [
            "name": SettingsManager.shared.petName,
            "personality": PersonalityPreset.currentPrompt(),
            "thumbnail": thumbnail?.base64EncodedString() ?? "",
            "hasApiKey": SettingsManager.shared.apiKey != nil
        ]
        if let msg = message {
            innerPayload["deliveryMessage"] = msg
        }
        let payload: [String: Any] = [
            "type": "visit_request",
            "from": myCode,
            "ts": Int(Date().timeIntervalSince1970),
            "payload": innerPayload
        ]
        MQTTService.shared.publish(topic: MQTTService.shared.inboxTopic(for: friendCode), payload: payload)

        // 15 秒超时
        requestTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            NSLog("[Social] Visit request timeout")
            self?.onShowBubble?("对方没有回应呢...")
            self?.state = .idle
            self?.visitingFriendCode = nil
        }

        onShowBubble?("正在联系好友...")
    }

    /// 接受来访
    private func acceptVisit(from info: FriendInfo) {
        if state != .idle {
            // 冲突处理：配对码字典序小的优先
            if state == .requesting, let myVisiting = visitingFriendCode,
               info.code < myVisiting {
                // 对方优先，取消我方请求
                cancelRequest()
            } else {
                rejectVisit(from: info.code)
                return
            }
        }

        state = .hosting
        hostingFriendCode = info.code
        visitorInfo = info

        // 更新好友名字
        SettingsManager.shared.addFriend(code: info.code, name: info.name)

        // 回复 visit_accept
        let thumbnail = generateThumbnail()
        let payload: [String: Any] = [
            "type": "visit_accept",
            "from": myCode,
            "ts": Int(Date().timeIntervalSince1970),
            "payload": [
                "name": SettingsManager.shared.petName,
                "personality": PersonalityPreset.currentPrompt(),
                "thumbnail": thumbnail?.base64EncodedString() ?? "",
                "hasApiKey": SettingsManager.shared.apiKey != nil
            ]
        ]
        MQTTService.shared.publish(topic: MQTTService.shared.inboxTopic(for: info.code), payload: payload)

        // 显示来访宠物
        if let hostWin = getHostWindow?() {
            visitorWindow.showVisitor(thumbnailData: info.thumbnail, near: hostWin)
        }
        onVisitorArrived?()

        // 来访宠物入场后，如果有带话，先展示带话气泡
        if let msg = info.deliveryMessage, !msg.isEmpty {
            // 等入场动画完成后(~2秒)展示带话
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.visitorWindow.showBubble(text: "hi~ 主人让我带话过来：\(msg)", isDelivery: true)
            }
        }

        // 30 秒无消息超时
        resetVisitTimeout()
    }

    private func rejectVisit(from code: String) {
        let payload: [String: Any] = [
            "type": "visit_reject",
            "from": myCode,
            "ts": Int(Date().timeIntervalSince1970),
            "payload": [String: Any]()
        ]
        MQTTService.shared.publish(topic: MQTTService.shared.inboxTopic(for: code), payload: payload)
    }

    private func cancelRequest() {
        requestTimer?.invalidate()
        requestTimer = nil
        state = .idle
        visitingFriendCode = nil
    }

    // MARK: - 对话系统

    private func startDialogue(visitorInfo: FriendInfo, hostInfo: FriendInfo, amIVisitor: Bool) {
        // 决定谁生成对话：优先访客方；都有 Key 则访客生成
        let shouldGenerate: Bool
        if amIVisitor {
            shouldGenerate = true
        } else {
            // 我是主人，只有访客没有 Key 且我有 Key 时才我生成
            shouldGenerate = !visitorInfo.hasApiKey && (SettingsManager.shared.apiKey != nil)
        }

        if shouldGenerate {
            AIEngine.shared.generateDialogue(
                visitorName: amIVisitor ? SettingsManager.shared.petName : visitorInfo.name,
                visitorPersonality: amIVisitor ? PersonalityPreset.currentPrompt() : visitorInfo.personality,
                hostName: amIVisitor ? hostInfo.name : SettingsManager.shared.petName,
                hostPersonality: amIVisitor ? hostInfo.personality : PersonalityPreset.currentPrompt()
            ) { [weak self] dialogues in
                self?.currentDialogue = dialogues
                self?.dialogueIndex = 0
                self?.sendNextDialogueLine(amIVisitor: amIVisitor, targetCode: amIVisitor ? hostInfo.code : visitorInfo.code)
            }
        }
        // 如果不该我生成，等对方通过 chat 发过来
    }

    private func sendNextDialogueLine(amIVisitor: Bool, targetCode: String) {
        guard dialogueIndex < currentDialogue.count else {
            // 对话结束
            finishDialogue(targetCode: targetCode, amIVisitor: amIVisitor)
            return
        }

        let line = currentDialogue[dialogueIndex]
        let isLast = dialogueIndex >= currentDialogue.count - 1

        // 通过 MQTT 发送
        let payload: [String: Any] = [
            "type": "chat",
            "from": myCode,
            "ts": Int(Date().timeIntervalSince1970),
            "payload": [
                "speaker": line.speaker,
                "text": line.text,
                "turn": dialogueIndex,
                "isLast": isLast
            ]
        ]
        MQTTService.shared.publish(topic: MQTTService.shared.chatTopic(for: targetCode), payload: payload)

        // 本地也显示
        displayDialogueLine(line, amIVisitor: amIVisitor)

        dialogueIndex += 1
        resetVisitTimeout()

        // 4 秒后发下一句
        if !isLast {
            dialogueTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.sendNextDialogueLine(amIVisitor: amIVisitor, targetCode: targetCode)
            }
        } else {
            // 最后一句后 3 秒结束
            dialogueTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                self?.finishDialogue(targetCode: targetCode, amIVisitor: amIVisitor)
            }
        }
    }

    private func displayDialogueLine(_ line: (speaker: String, text: String), amIVisitor: Bool) {
        if amIVisitor {
            // 我是访客：A 是我说的（显示在主人那边的来访宠物气泡上）
            // 但我这边看不到，通过 onShowBubble 显示在自己气泡上
            if line.speaker == "A" {
                onShowBubble?(line.text)
            }
        } else {
            // 我是主人：A 是来访宠物说的，B 是我说的
            if line.speaker == "A" {
                visitorWindow.showBubble(text: line.text)
            } else {
                onShowBubble?(line.text)
            }
        }
    }

    private func finishDialogue(targetCode: String, amIVisitor: Bool) {
        dialogueTimer?.invalidate()
        dialogueTimer = nil

        if amIVisitor {
            // 我是访客，发 visit_leave
            let payload: [String: Any] = [
                "type": "visit_leave",
                "from": myCode,
                "ts": Int(Date().timeIntervalSince1970),
                "payload": [String: Any]()
            ]
            MQTTService.shared.publish(topic: MQTTService.shared.inboxTopic(for: targetCode), payload: payload)

            // 宠物回来
            state = .idle
            visitingFriendCode = nil
            visitTimer?.invalidate()
            visitTimer = nil
            onVisitBack?()
        }
        // 主人方等对方发 visit_leave
    }

    // MARK: - 消息处理

    private func handleMessage(topic: String, data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let from = json["from"] as? String else {
            NSLog("[Social] Failed to parse message on topic: \(topic)")
            return
        }

        NSLog("[Social] Received: type=\(type) from=\(from) topic=\(topic)")

        // 忽略自己的消息（但 status topic 不过滤，因为 from 可能不同）
        if !topic.hasSuffix("/status") {
            guard from != myCode else { return }
        }

        let payload = json["payload"] as? [String: Any] ?? [:]

        // 状态消息
        if topic.hasSuffix("/status") {
            // 从 topic 提取 code（更可靠，topic = desktoppet/v1/{code}/status）
            let parts = topic.components(separatedBy: "/")
            let statusCode = parts.count >= 3 ? parts[parts.count - 2] : from
            let statusName = json["name"] as? String
            handleStatusMessage(type: type, from: statusCode, name: statusName)
            return
        }

        // inbox 消息
        if topic.hasSuffix("/inbox") {
            switch type {
            case "visit_request":
                handleVisitRequest(from: from, payload: payload)
            case "visit_accept":
                handleVisitAccept(from: from, payload: payload)
            case "visit_reject":
                handleVisitReject(from: from)
            case "visit_leave":
                handleVisitLeave(from: from)
            default:
                break
            }
            return
        }

        // chat 消息
        if topic.hasSuffix("/chat") {
            handleChatMessage(from: from, payload: payload)
            return
        }
    }

    private func handleStatusMessage(type: String, from: String, name: String?) {
        NSLog("[Social] Status: \(from) is \(type), name=\(name ?? "nil")")
        if type == "online" {
            onlineFriends.insert(from)
            // 更新好友名字（如果对方携带了 name 且是好友）
            if let name = name, !name.isEmpty, SettingsManager.shared.isFriend(from) {
                let current = SettingsManager.shared.friendList[from]
                if current == nil || current == from {
                    SettingsManager.shared.addFriend(code: from, name: name)
                }
            }
        } else {
            onlineFriends.remove(from)
        }
        NSLog("[Social] Online friends: \(onlineFriends)")
        onFriendListChanged?()
    }

    private func handleVisitRequest(from: String, payload: [String: Any]) {
        // 只接受好友
        guard SettingsManager.shared.isFriend(from) else {
            rejectVisit(from: from)
            return
        }

        let info = FriendInfo(
            code: from,
            name: payload["name"] as? String ?? from,
            personality: payload["personality"] as? String ?? "",
            thumbnail: (payload["thumbnail"] as? String).flatMap { Data(base64Encoded: $0) },
            hasApiKey: payload["hasApiKey"] as? Bool ?? false,
            isOnline: true,
            deliveryMessage: payload["deliveryMessage"] as? String
        )

        acceptVisit(from: info)
    }

    private func handleVisitAccept(from: String, payload: [String: Any]) {
        guard state == .requesting, visitingFriendCode == from else { return }

        requestTimer?.invalidate()
        requestTimer = nil

        state = .visitingOut

        let hostInfo = FriendInfo(
            code: from,
            name: payload["name"] as? String ?? from,
            personality: payload["personality"] as? String ?? "",
            thumbnail: (payload["thumbnail"] as? String).flatMap { Data(base64Encoded: $0) },
            hasApiKey: payload["hasApiKey"] as? Bool ?? false,
            isOnline: true,
            deliveryMessage: nil
        )

        // 更新好友名字
        SettingsManager.shared.addFriend(code: from, name: hostInfo.name)

        // 宠物出门
        onVisitOut?()
        onShowBubble?("出门串门去了~")

        // 30 秒超时保护
        resetVisitTimeout()

        // 开始对话（我是访客）
        let myInfo = FriendInfo(
            code: myCode,
            name: SettingsManager.shared.petName,
            personality: PersonalityPreset.currentPrompt(),
            thumbnail: nil,
            hasApiKey: SettingsManager.shared.apiKey != nil,
            isOnline: true
        )

        // 延迟等入场动画(2秒) + 带话展示(8秒，如有)
        let extraDelay: TimeInterval = pendingDeliveryMessage != nil ? 8 : 0
        pendingDeliveryMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + extraDelay) { [weak self] in
            self?.startDialogue(visitorInfo: myInfo, hostInfo: hostInfo, amIVisitor: true)
        }
    }

    private func handleVisitReject(from: String) {
        guard state == .requesting, visitingFriendCode == from else { return }
        cancelRequest()
        onShowBubble?("对方现在不方便呢~")
    }

    private func handleVisitLeave(from: String) {
        guard state == .hosting, hostingFriendCode == from else { return }

        visitTimer?.invalidate()
        visitTimer = nil
        dialogueTimer?.invalidate()
        dialogueTimer = nil

        // 来访宠物离场
        visitorWindow.dismiss { [weak self] in
            self?.state = .idle
            self?.hostingFriendCode = nil
            self?.visitorInfo = nil
            self?.onVisitorLeft?()
        }
    }

    private func handleChatMessage(from: String, payload: [String: Any]) {
        guard let speaker = payload["speaker"] as? String,
              let text = payload["text"] as? String else { return }
        let isLast = payload["isLast"] as? Bool ?? false

        resetVisitTimeout()

        let line = (speaker: speaker, text: text)

        if state == .hosting {
            // 我是主人，收到访客发来的对话
            displayDialogueLine(line, amIVisitor: false)
            if isLast {
                // 对话结束，等 visit_leave
            }
        } else if state == .visitingOut {
            // 我是访客，收到主人发来的对话（如果主人生成的话）
            displayDialogueLine(line, amIVisitor: true)
        }
    }

    // MARK: - 超时

    private func resetVisitTimeout() {
        visitTimer?.invalidate()
        visitTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            NSLog("[Social] Visit timeout, auto cleanup")
            self?.forceEndVisit()
        }
    }

    private func forceEndVisit() {
        dialogueTimer?.invalidate()
        dialogueTimer = nil
        visitTimer?.invalidate()
        visitTimer = nil

        if state == .visitingOut {
            if let code = visitingFriendCode {
                let payload: [String: Any] = [
                    "type": "visit_leave",
                    "from": myCode,
                    "ts": Int(Date().timeIntervalSince1970),
                    "payload": [String: Any]()
                ]
                MQTTService.shared.publish(topic: MQTTService.shared.inboxTopic(for: code), payload: payload)
            }
            state = .idle
            visitingFriendCode = nil
            onVisitBack?()
        } else if state == .hosting {
            visitorWindow.dismiss { [weak self] in
                self?.state = .idle
                self?.hostingFriendCode = nil
                self?.visitorInfo = nil
                self?.onVisitorLeft?()
            }
        }
    }

    private func cancelAllTimers() {
        requestTimer?.invalidate()
        requestTimer = nil
        visitTimer?.invalidate()
        visitTimer = nil
        dialogueTimer?.invalidate()
        dialogueTimer = nil
    }

    // MARK: - 缩略图

    /// 生成当前宠物 64x64 缩略图
    private func generateThumbnail() -> Data? {
        // 尝试加载当前宠物图像
        let petMode = SettingsManager.shared.petMode
        var imagePath: String?

        if petMode >= 1 {
            let slot = petMode
            if SettingsManager.shared.hasCustomImage(slot: slot) {
                imagePath = SettingsManager.shared.customImagePath(slot: slot)
            }
        }

        if imagePath == nil, let resourcePath = PetConfig.getResourcePath() {
            // 使用 idle_0.png 作为缩略图源
            let path = resourcePath + "/idle_0.png"
            if FileManager.default.fileExists(atPath: path) {
                imagePath = path
            } else {
                let fallback = resourcePath + "/idle.png"
                if FileManager.default.fileExists(atPath: fallback) {
                    imagePath = fallback
                }
            }
        }

        guard let path = imagePath, let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        // 缩放到 64x64
        let targetSize = NSSize(width: 64, height: 64)
        let resized = NSImage(size: targetSize, flipped: false) { rect in
            image.draw(in: rect, from: NSRect(origin: .zero, size: image.size),
                      operation: .copy, fraction: 1.0)
            return true
        }

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData
    }
}
