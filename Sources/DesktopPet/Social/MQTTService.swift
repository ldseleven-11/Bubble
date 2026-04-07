import Foundation
import CocoaMQTT

// MARK: - MQTT 服务
class MQTTService: NSObject {
    static let shared = MQTTService()

    private var mqtt: CocoaMQTT?
    private let broker = "broker.emqx.io"
    private let port: UInt16 = 1883
    private let topicPrefix = "desktoppet/v1"

    private(set) var isConnected = false
    private var reconnectTimer: Timer?
    private var subscribedTopics: Set<String> = []

    /// 收到消息的回调
    var onMessage: ((String, Data) -> Void)?
    /// 连接状态变化
    var onConnectionChange: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - 主题路径

    func statusTopic(for code: String) -> String {
        return "\(topicPrefix)/\(code)/status"
    }

    func inboxTopic(for code: String) -> String {
        return "\(topicPrefix)/\(code)/inbox"
    }

    func chatTopic(for code: String) -> String {
        return "\(topicPrefix)/\(code)/chat"
    }

    // MARK: - 连接

    func connect(clientId: String) {
        let mqtt = CocoaMQTT(clientID: "desktoppet-\(clientId)-\(Int.random(in: 1000...9999))",
                             host: broker,
                             port: port)
        mqtt.keepAlive = 60
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 5
        mqtt.cleanSession = true

        // LWT（遗嘱消息）：掉线自动发离线状态
        let lwtPayload: [String: Any] = [
            "type": "offline",
            "from": clientId,
            "ts": Int(Date().timeIntervalSince1970)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: lwtPayload),
           let str = String(data: data, encoding: .utf8) {
            mqtt.willMessage = CocoaMQTTMessage(topic: statusTopic(for: clientId),
                                                 string: str,
                                                 qos: .qos1,
                                                 retained: true)
        }

        mqtt.delegate = self
        self.mqtt = mqtt
        _ = mqtt.connect()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        mqtt?.disconnect()
        mqtt = nil
        isConnected = false
    }

    // MARK: - 订阅

    func subscribe(topic: String) {
        subscribedTopics.insert(topic)
        if isConnected {
            mqtt?.subscribe(topic, qos: .qos1)
        }
    }

    func unsubscribe(topic: String) {
        subscribedTopics.remove(topic)
        if isConnected {
            mqtt?.unsubscribe(topic)
        }
    }

    // MARK: - 发布

    func publish(topic: String, payload: [String: Any], retained: Bool = false) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        mqtt?.publish(topic, withString: str, qos: .qos1, retained: retained)
    }

    func publishStatus(code: String, online: Bool) {
        let payload: [String: Any] = [
            "type": online ? "online" : "offline",
            "from": code,
            "ts": Int(Date().timeIntervalSince1970)
        ]
        publish(topic: statusTopic(for: code), payload: payload, retained: true)
    }

    private func resubscribeAll() {
        for topic in subscribedTopics {
            mqtt?.subscribe(topic, qos: .qos1)
        }
    }
}

// MARK: - CocoaMQTTDelegate
extension MQTTService: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            isConnected = true
            resubscribeAll()
            onConnectionChange?(true)
            NSLog("[MQTT] Connected to \(broker)")
        } else {
            NSLog("[MQTT] Connection rejected: \(ack)")
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        guard let data = message.string?.data(using: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message.topic, data)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        NSLog("[MQTT] Subscribed: \(success.allKeys)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}

    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnected = false
        onConnectionChange?(false)
        NSLog("[MQTT] Disconnected: \(err?.localizedDescription ?? "clean")")
    }

    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        NSLog("[MQTT] State: \(state)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
