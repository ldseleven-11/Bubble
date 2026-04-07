import AppKit
import CryptoKit

// MARK: - 用户设置管理
class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    private let kTerminalCommand = "DesktopPet_TerminalCommand"
    private let kMonitorMode = "DesktopPet_MonitorMode"
    private let kActivityRange = "DesktopPet_ActivityRange"
    private let kPetMode = "DesktopPet_PetMode"
    private let kPetSize = "DesktopPet_PetSize"
    private let kWorkingEffect = "DesktopPet_WorkingEffect"
    private let kPetName = "DesktopPet_PetName"
    private let kPersonalityPreset = "DesktopPet_PersonalityPreset"
    private let kCustomPersonality = "DesktopPet_CustomPersonality"
    private let kApiKey = "DesktopPet_ApiKey"
    private let kAiProvider = "DesktopPet_AiProvider"
    private let kSocialCode = "DesktopPet_SocialCode"
    private let kFriendList = "DesktopPet_FriendList"
    private let kOnboardingDone = "DesktopPet_OnboardingDone"
    private let kDingTalkEnabled = "DesktopPet_DingTalkEnabled"
    private let kOpenClawToken = "DesktopPet_OpenClawToken"
    private let kDingTalkUserId = "DesktopPet_DingTalkUserId"
    private let kGatewayHost = "DesktopPet_GatewayHost"
    private let kGatewayPort = "DesktopPet_GatewayPort"
    private let kSpeechMode = "DesktopPet_SpeechMode"
    private let kAIMode = "DesktopPet_AIMode"  // 0=基础, 1=聪明(LLM), 2=助手(OpenClaw)

    // 0=全屏 1=左半屏 2=右半屏 3=左1/3 4=右1/3
    var activityRange: Int {
        get {
            if defaults.object(forKey: kActivityRange) == nil { return 0 }
            return defaults.integer(forKey: kActivityRange)
        }
        set { defaults.set(newValue, forKey: kActivityRange) }
    }

    // 0 = 键鼠输入检测, 1 = Claude 进程监控
    var monitorMode: Int {
        get {
            if defaults.object(forKey: kMonitorMode) == nil { return 0 }
            return defaults.integer(forKey: kMonitorMode)
        }
        set { defaults.set(newValue, forKey: kMonitorMode) }
    }

    // 0 = 皮卡丘, 1 = 自定义1, 2 = 自定义2, 3 = 自定义3
    var petMode: Int {
        get {
            if defaults.object(forKey: kPetMode) == nil { return 0 }
            return defaults.integer(forKey: kPetMode)
        }
        set { defaults.set(newValue, forKey: kPetMode) }
    }

    var appSupportDir: String {
        let dir = NSHomeDirectory() + "/Library/Application Support/DesktopPet"
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // 兼容旧版
    var customImageStorePath: String { customImagePath(slot: 1) }
    var hasCustomImage: Bool { hasCustomImage(slot: 1) }

    func customImagePath(slot: Int) -> String {
        return appSupportDir + "/custom_pet_\(slot).png"
    }

    func hasCustomImage(slot: Int) -> Bool {
        FileManager.default.fileExists(atPath: customImagePath(slot: slot))
    }

    // 当前选中的槽位 (petMode 1->slot1, 2->slot2, 3->slot3)
    func currentSlot() -> Int {
        return max(1, petMode)
    }

    // 0=小(80) 1=中(110) 2=大(140) 3=特大(180)
    static let petSizes: [CGFloat] = [80, 110, 140, 180]

    var petSizeIndex: Int {
        get {
            if defaults.object(forKey: kPetSize) == nil { return 0 }
            return defaults.integer(forKey: kPetSize)
        }
        set { defaults.set(newValue, forKey: kPetSize) }
    }

    var petSize: CGFloat {
        let idx = min(petSizeIndex, SettingsManager.petSizes.count - 1)
        return SettingsManager.petSizes[max(0, idx)]
    }

    // 0=快速摇晃, 1=转圈圈
    var workingEffect: Int {
        get {
            if defaults.object(forKey: kWorkingEffect) == nil { return 0 }
            return defaults.integer(forKey: kWorkingEffect)
        }
        set { defaults.set(newValue, forKey: kWorkingEffect) }
    }

    var terminalCommand: String {
        get { defaults.string(forKey: kTerminalCommand) ?? "cd ~" }
        set { defaults.set(newValue, forKey: kTerminalCommand) }
    }

    // 宠物名字（override 优先，不影响 UserDefaults）
    var petName: String {
        get {
            if let override = petNameOverride { return override }
            return defaults.string(forKey: kPetName) ?? "皮皮"
        }
        set { defaults.set(newValue, forKey: kPetName) }
    }

    // 性格预设 index (0=社恐 1=话痨 2=傲娇 3=吃货 4=佛系 5=自定义)
    var personalityPreset: Int {
        get {
            if defaults.object(forKey: kPersonalityPreset) == nil { return 0 }
            return defaults.integer(forKey: kPersonalityPreset)
        }
        set { defaults.set(newValue, forKey: kPersonalityPreset) }
    }

    // 自定义性格描述
    var customPersonality: String {
        get { defaults.string(forKey: kCustomPersonality) ?? "" }
        set { defaults.set(newValue, forKey: kCustomPersonality) }
    }

    // 0 = 语录文件, 1 = AI 生成
    var speechMode: Int {
        get {
            if defaults.object(forKey: kSpeechMode) == nil { return 0 }
            return defaults.integer(forKey: kSpeechMode)
        }
        set { defaults.set(newValue, forKey: kSpeechMode) }
    }

    /// 是否启用 AI 说话（聪明模式用 LLM，助手模式用 OpenClaw）
    var isAISpeechEnabled: Bool {
        if aiMode == 2 { return speechMode == 1 }  // 助手模式：AI 生成走 OpenClaw
        return speechMode == 1 && apiKey != nil     // 聪明模式：需要 API Key
    }

    // AI 供应商 index
    var aiProvider: Int {
        get {
            if defaults.object(forKey: kAiProvider) == nil { return 0 }
            return defaults.integer(forKey: kAiProvider)
        }
        set { defaults.set(newValue, forKey: kAiProvider) }
    }

    // API Key
    var apiKey: String? {
        get {
            let key = defaults.string(forKey: kApiKey) ?? ""
            return key.isEmpty ? nil : key
        }
        set { defaults.set(newValue ?? "", forKey: kApiKey) }
    }

    // MARK: - AI 能力模式 (0=基础, 1=聪明, 2=助手)

    var aiMode: Int {
        get {
            if defaults.object(forKey: kAIMode) == nil { return 0 }
            return defaults.integer(forKey: kAIMode)
        }
        set { defaults.set(newValue, forKey: kAIMode) }
    }

    // MARK: - Runtime overrides（不存 UserDefaults，断联自动清除）
    var personalityOverride: String?   // OpenClaw agent 性格
    var petNameOverride: String?       // OpenClaw agent 名字

    // MARK: - 钉钉通知 (OpenClaw)

    var dingtalkEnabled: Bool {
        get { aiMode == 2 }
        set {
            if newValue { aiMode = 2 } else if aiMode == 2 { aiMode = 0 }
        }
    }

    var openclawToken: String {
        get {
            let saved = defaults.string(forKey: kOpenClawToken) ?? ""
            if saved.isEmpty {
                // 默认读取 openclaw.json 中的 token
                return SettingsManager.readOpenClawToken() ?? ""
            }
            return saved
        }
        set { defaults.set(newValue, forKey: kOpenClawToken) }
    }

    /// 钉钉 userId（用于识别"我的"私聊 session）
    var dingtalkUserId: String {
        get { defaults.string(forKey: kDingTalkUserId) ?? "" }
        set { defaults.set(newValue, forKey: kDingTalkUserId) }
    }

    var gatewayHost: String {
        get { defaults.string(forKey: kGatewayHost) ?? "127.0.0.1" }
        set { defaults.set(newValue, forKey: kGatewayHost) }
    }

    var gatewayPort: Int {
        get {
            if defaults.object(forKey: kGatewayPort) == nil { return 18789 }
            return defaults.integer(forKey: kGatewayPort)
        }
        set { defaults.set(newValue, forKey: kGatewayPort) }
    }

    // MARK: - OpenClaw 检测

    struct OpenClawDetection {
        var cliInstalled: Bool = false
        var configPath: String?
        var configExists: Bool = false
        var token: String?
        var host: String = "127.0.0.1"
        var port: Int = 18789

        var statusMessage: String {
            if !cliInstalled { return "not_installed" }
            if !configExists { return "no_config" }
            if token == nil || token!.isEmpty { return "no_token" }
            return "ready"
        }
    }

    /// 检测 OpenClaw 安装状态和配置
    static func detectOpenClaw() -> OpenClawDetection {
        var result = OpenClawDetection()

        // 1. which openclaw
        guard let clawPath = runShellCommand("/usr/bin/which", ["openclaw"]),
              !clawPath.isEmpty else {
            return result
        }
        result.cliInstalled = true

        // 2. openclaw config file → 获取配置文件路径
        if let configFile = runShellCommand(clawPath.trimmingCharacters(in: .whitespacesAndNewlines), ["config", "file"]) {
            let path = configFile.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "~", with: NSHomeDirectory())
            result.configPath = path
            result.configExists = FileManager.default.fileExists(atPath: path)
        }

        // 3. 读取配置
        if let configPath = result.configPath, result.configExists {
            if let parsed = readOpenClawConfig(path: configPath) {
                result.token = parsed.token
                result.host = parsed.host
                result.port = parsed.port
            }
        }

        return result
    }

    /// 从指定路径读取 OpenClaw 配置
    private static func readOpenClawConfig(path: String) -> (token: String?, host: String, port: Int)? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var token: String?
        var host = "127.0.0.1"
        var port = 18789

        if let gateway = json["gateway"] as? [String: Any] {
            if let auth = gateway["auth"] as? [String: Any],
               let t = auth["token"] as? String {
                token = t
            }
            if let mode = gateway["mode"] as? String, mode != "local" {
                host = gateway["host"] as? String ?? "127.0.0.1"
            }
            if let p = gateway["port"] as? Int {
                port = p
            }
        }
        return (token, host, port)
    }

    /// 运行 shell 命令并返回 stdout
    private static func runShellCommand(_ command: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// 从 ~/.openclaw/openclaw.json 读取 gateway token (兜底方法)
    private static func readOpenClawToken() -> String? {
        // 先尝试 CLI 检测
        let detection = detectOpenClaw()
        if let token = detection.token, !token.isEmpty {
            return token
        }
        // 兜底：直接读默认路径
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = json["gateway"] as? [String: Any],
              let auth = gateway["auth"] as? [String: Any],
              let token = auth["token"] as? String else {
            return nil
        }
        return token
    }

    // MARK: - 新手引导
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: kOnboardingDone) }
        set { defaults.set(newValue, forKey: kOnboardingDone) }
    }

    // MARK: - 社交功能

    /// 配对码（6位字母数字，去除易混淆字符 0/O/1/I/L）
    var socialCode: String {
        get {
            // 命令行参数覆盖
            if let idx = CommandLine.arguments.firstIndex(of: "--social-code"),
               idx + 1 < CommandLine.arguments.count {
                return CommandLine.arguments[idx + 1]
            }
            if let saved = defaults.string(forKey: kSocialCode), !saved.isEmpty {
                return saved
            }
            let code = SettingsManager.generateSocialCode()
            defaults.set(code, forKey: kSocialCode)
            return code
        }
    }

    /// 好友列表：[配对码: 昵称]
    var friendList: [String: String] {
        get {
            return defaults.dictionary(forKey: kFriendList) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: kFriendList)
        }
    }

    func addFriend(code: String, name: String) {
        var list = friendList
        list[code] = name
        friendList = list
    }

    func removeFriend(code: String) {
        var list = friendList
        list.removeValue(forKey: code)
        friendList = list
    }

    func isFriend(_ code: String) -> Bool {
        return friendList[code] != nil
    }

    /// 基于硬件 UUID 的 SHA256 前 4 字节生成 6 位配对码
    private static func generateSocialCode() -> String {
        let uuid = getHardwareUUID() ?? UUID().uuidString
        let hash = SHA256.hash(data: Data(uuid.utf8))
        let bytes = Array(hash.prefix(4))
        let charset = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789") // 去掉 0/O/1/I/L
        var code = ""
        var value = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        for _ in 0..<6 {
            let idx = Int(value % UInt32(charset.count))
            code.append(charset[idx])
            value /= UInt32(charset.count)
        }
        return code
    }

    private static func getHardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        if let uuidCF = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) {
            return uuidCF.takeRetainedValue() as? String
        }
        return nil
    }
}
