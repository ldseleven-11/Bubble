import Foundation

// MARK: - 通用聊天事件

struct ChatEvent {
    let sessionKey: String
    let state: String           // "delta" | "final" | "error"
    let message: String?
    let errorMessage: String?
    let isGroupChat: Bool
    let conversationTitle: String?
    let runId: String?
}

// MARK: - OpenClaw Gateway WebSocket 客户端

class OpenClawGateway: AgentGateway {
    private let host: String
    private let port: Int
    private let token: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var reconnectDelay: TimeInterval = 2.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var shouldReconnect = false
    private var requestCounter = 0
    private let sessionPrefix = UUID().uuidString.prefix(8)

    // AgentGateway 协议
    var onMessage: ((ChatEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onIdentityLoaded: ((String, String) -> Void)?
    /// 连接被拒绝时的错误信息回调（认证失败等）
    var onConnectRejected: ((String) -> Void)?
    /// WebSocket 物理连接成功（收到 challenge，TCP 层面通了）
    var onChallengeReceived: (() -> Void)?

    init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
    }

    // MARK: - AgentGateway 连接管理

    func connect() {
        shouldReconnect = true
        reconnectDelay = 2.0
        doConnect()
    }

    func disconnect() {
        shouldReconnect = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        setConnected(false)
    }

    func send(sessionKey: String, message: String,
              completion: @escaping (Bool, String?) -> Void) {
        sendChatMessage(sessionKey: sessionKey, message: message,
                        deliver: true, completion: completion)
    }

    // MARK: - 内部连接

    private func doConnect() {
        guard shouldReconnect else { return }

        let url = URL(string: "ws://\(host):\(port)")!
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        NSLog("[OpenClaw] Connecting to ws://\(host):\(port)...")

        // 开始接收消息，等待 challenge
        receiveMessages()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // 继续监听
                self.receiveMessages()

            case .failure(let error):
                NSLog("[OpenClaw] WebSocket receive error: %@", error.localizedDescription)
                self.handleDisconnect()
            }
        }
    }

    // MARK: - 消息处理

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            NSLog("[OpenClaw] Received non-JSON: %@", String(text.prefix(200)))
            return
        }

        // 调试：记录收到的所有消息类型
        if type == "event", let event = json["event"] as? String {
            NSLog("[OpenClaw] Event: %@", event)
        } else {
            let preview = String(text.prefix(300))
            NSLog("[OpenClaw] Frame type=%@: %@", type, preview)
        }

        switch type {
        case "event":
            guard let event = json["event"] as? String else { return }
            if event == "connect.challenge" {
                // 收到 challenge = WebSocket 物理连接成功
                DispatchQueue.main.async { [weak self] in
                    self?.onChallengeReceived?()
                }
                // 发送 connect 请求进行认证握手
                sendConnect()
            } else if event == "chat" {
                handleChatEvent(json)
            }

        case "res":
            // 先检查 pendingResponses（chat.send 的回调）
            if let reqId = json["id"] as? String, let callback = pendingResponses.removeValue(forKey: reqId) {
                let ok = json["ok"] as? Bool ?? false
                let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
                DispatchQueue.main.async {
                    callback(ok, errorMsg)
                }
                return
            }
            // 握手响应
            if let payload = json["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String,
               payloadType == "hello-ok" {
                NSLog("[OpenClaw] Connected! Protocol v3 handshake OK")
                reconnectDelay = 2.0
                setConnected(true)
                loadAgentIdentity()
            } else if let ok = json["ok"] as? Bool, !ok {
                let errorMsg: String
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMsg = message
                    NSLog("[OpenClaw] Connect rejected: %@", message)
                } else {
                    errorMsg = "连接被拒绝"
                    NSLog("[OpenClaw] Connect rejected (no detail)")
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onConnectRejected?(errorMsg)
                }
                handleDisconnect()
            }

        default:
            break
        }
    }

    private func sendConnect() {
        requestCounter += 1
        let reqId = "pet-\(sessionPrefix)-\(requestCounter)"

        let connectReq: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "openclaw-macos",
                    "version": "1.0.0",
                    "platform": "macos",
                    "mode": "ui"
                ],
                "role": "operator",
                "auth": [
                    "token": token
                ]
            ]
        ]

        sendJSON(connectReq)
    }

    private func handleChatEvent(_ json: [String: Any]) {
        // 调试：打印 chat 事件的完整 payload
        if let payload = json["payload"] as? [String: Any] {
            let keys = payload.keys.sorted().joined(separator: ", ")
            let sessionKey = payload["sessionKey"] ?? "nil"
            let state = payload["state"] ?? "nil"
            let msg = payload["message"] ?? "nil"
            NSLog("[OpenClaw] chat payload keys=[%@] sessionKey=%@ state=%@ message_type=%@", keys, "\(sessionKey)", "\(state)", "\(type(of: msg))")
            // 打印 message 的前 200 字
            if let msgObj = payload["message"],
               JSONSerialization.isValidJSONObject(msgObj),
               let data = try? JSONSerialization.data(withJSONObject: msgObj, options: []),
               let str = String(data: data, encoding: .utf8) {
                NSLog("[OpenClaw] chat message=%@", String(str.prefix(300)))
            }
        } else {
            NSLog("[OpenClaw] chat event has no payload dict!")
        }

        guard let payload = json["payload"] as? [String: Any],
              let sessionKey = payload["sessionKey"] as? String,
              let state = payload["state"] as? String else {
            NSLog("[OpenClaw] chat event parse FAILED - missing sessionKey or state")
            return
        }

        // 提取消息文本
        // message 格式: {content: [{type: "text", text: "..."}], role: "assistant"}
        var messageText: String?
        if let message = payload["message"] as? [String: Any] {
            if let contentArray = message["content"] as? [[String: Any]] {
                // content 是数组，拼接所有 text 块
                let texts = contentArray.compactMap { $0["text"] as? String }
                let joined = texts.joined()
                if !joined.isEmpty { messageText = joined }
            } else if let content = message["content"] as? String {
                messageText = content
            } else if let text = message["text"] as? String {
                messageText = text
            }
        } else if let message = payload["message"] as? String {
            messageText = message
        }

        let errorMessage = payload["errorMessage"] as? String
        let runId = payload["runId"] as? String

        // 从 sessionKey 判断是否群聊
        // 格式: "agent:main:dingtalk:group:xxx" 或 "agent:main:dingtalk:private:xxx"
        let isGroup = sessionKey.contains(":group:")

        // 尝试提取会话标题
        var title: String?
        if let meta = payload["meta"] as? [String: Any] {
            title = meta["conversationTitle"] as? String
        }

        let event = ChatEvent(
            sessionKey: sessionKey,
            state: state,
            message: messageText,
            errorMessage: errorMessage,
            isGroupChat: isGroup,
            conversationTitle: title,
            runId: runId
        )

        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(event)
        }
    }

    // MARK: - Agent 身份加载

    private func loadAgentIdentity() {
        let ws = NSHomeDirectory() + "/.openclaw/workspace"
        var name = ""
        var personality = ""

        // 读 IDENTITY.md → 提取名字（文件不存在时跳过）
        if let identityData = FileManager.default.contents(atPath: ws + "/IDENTITY.md"),
           let identityText = String(data: identityData, encoding: .utf8) {
            // 从 **Name:** xxx 提取名字
            for line in identityText.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("**Name:**") || trimmed.contains("**name:**") {
                    let parts = trimmed.components(separatedBy: ":**")
                    if parts.count >= 2 {
                        name = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
                    } else {
                        // 尝试 :** 后面的内容
                        if let range = trimmed.range(of: ":**") {
                            name = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    break
                }
            }
            // 合并 identity 的核心设定到性格描述
            if let coreRange = identityText.range(of: "## 核心设定") {
                let coreSection = String(identityText[coreRange.lowerBound...])
                // 取到下一个 ## 或末尾
                if let nextSection = coreSection.dropFirst(6).range(of: "\n## ") {
                    personality += String(coreSection[coreSection.startIndex..<coreSection.index(nextSection.lowerBound, offsetBy: 6)])
                } else {
                    personality += coreSection
                }
            }
        }

        // 读 SOUL.md → 性格描述（文件不存在时跳过）
        if let soulData = FileManager.default.contents(atPath: ws + "/SOUL.md"),
           let soulText = String(data: soulData, encoding: .utf8) {
            // 提取 Vibe 和 Core Truths 部分作为性格
            var soulParts: [String] = []
            if let vibeRange = soulText.range(of: "## Vibe") {
                let vibeSection = String(soulText[vibeRange.upperBound...])
                if let nextSection = vibeSection.range(of: "\n## ") {
                    soulParts.append(String(vibeSection[vibeSection.startIndex..<nextSection.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    soulParts.append(vibeSection.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if !soulParts.isEmpty {
                personality += (personality.isEmpty ? "" : "\n") + soulParts.joined(separator: "\n")
            }
        }

        if name.isEmpty { name = "小龙虾" }
        if personality.isEmpty { personality = "靠谱、直接、该听话时听话" }

        NSLog("[OpenClaw] Agent identity loaded: name=%@, personality=%@", name, String(personality.prefix(100)))

        DispatchQueue.main.async { [weak self] in
            self?.onIdentityLoaded?(name, personality)
        }
    }

    // MARK: - 发送聊天消息

    private var pendingResponses: [String: (Bool, String?) -> Void] = [:]

    private func sendChatMessage(sessionKey: String, message: String,
                                 deliver: Bool = true,
                                 completion: ((Bool, String?) -> Void)? = nil) {
        guard isConnected else {
            completion?(false, "未连接到 OpenClaw")
            return
        }

        requestCounter += 1
        let reqId = "pet-send-\(sessionPrefix)-\(requestCounter)"

        let req: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": message,
                "deliver": deliver,
                "idempotencyKey": reqId
            ]
        ]

        if let callback = completion {
            pendingResponses[reqId] = callback
            // 10 秒超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if let cb = self?.pendingResponses.removeValue(forKey: reqId) {
                    cb(false, "发送超时")
                }
            }
        }

        sendJSON(req)
        NSLog("[OpenClaw] Sent chat.send reqId=%@ sessionKey=%@", reqId, sessionKey)
    }

    // MARK: - 发送 JSON

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                NSLog("[OpenClaw] Send error: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - 重连

    private func handleDisconnect() {
        setConnected(false)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        guard shouldReconnect else { return }

        NSLog("[OpenClaw] Reconnecting in %.0fs...", reconnectDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.doConnect()
        }

        // 指数退避
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }

    private func setConnected(_ connected: Bool) {
        guard isConnected != connected else { return }
        isConnected = connected
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(connected)
        }
    }
}
