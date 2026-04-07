import Foundation

/// 宠物与 Agent 后端的通信协议
/// 具体实现：OpenClawGateway（当前）、未来可扩展其他网关
protocol AgentGateway: AnyObject {
    /// 连接到网关
    func connect()
    /// 断开连接
    func disconnect()
    /// 发送消息
    func send(sessionKey: String, message: String,
              completion: @escaping (Bool, String?) -> Void)

    /// 收到 agent 消息（delta/final/error）
    var onMessage: ((ChatEvent) -> Void)? { get set }
    /// 连接状态变化
    var onConnectionChange: ((Bool) -> Void)? { get set }
    /// Agent 身份加载完成 (name, personality)
    var onIdentityLoaded: ((String, String) -> Void)? { get set }
}
