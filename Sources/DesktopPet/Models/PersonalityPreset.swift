import Foundation

// MARK: - 性格预设
enum PersonalityPreset: Int, CaseIterable {
    case introvert  = 0  // 社恐
    case talkative  = 1  // 话痨
    case tsundere   = 2  // 傲娇
    case foodie     = 3  // 吃货
    case chill      = 4  // 佛系
    case custom     = 5  // 自定义

    var displayName: String {
        switch self {
        case .introvert: return "社恐"
        case .talkative: return "话痨"
        case .tsundere:  return "傲娇"
        case .foodie:    return "吃货"
        case .chill:     return "佛系"
        case .custom:    return "自定义"
        }
    }

    var prompt: String {
        switch self {
        case .introvert:
            return "性格内向害羞，不善言辞，说话简短，有时会用省略号，遇到热情的人会想躲，但其实内心渴望交朋友"
        case .talkative:
            return "话特别多，热情外向，喜欢用感叹号，会主动找话题，对什么都好奇，停不下来"
        case .tsundere:
            return "嘴上说不要身体很诚实，偶尔说反话，表面嫌弃实际很在乎主人"
        case .foodie:
            return "一切话题都能扯到吃的上面，用食物比喻一切，最大的爱好是吃，交朋友的标准是对方有没有好吃的"
        case .chill:
            return "佛系淡定，随遇而安，说话慢悠悠的，不急不躁，觉得什么都还不错"
        case .custom:
            return SettingsManager.shared.customPersonality
        }
    }

    /// 获取当前用户设置的性格 prompt（OpenClaw override > 自定义 > 预设）
    static func currentPrompt() -> String {
        // Priority 1: OpenClaw agent 性格（连接时有效）
        if let override = SettingsManager.shared.personalityOverride, !override.isEmpty {
            return override
        }
        // Priority 2: 用户自定义
        let custom = SettingsManager.shared.customPersonality
        if !custom.isEmpty { return custom }
        // Priority 3: 预设
        let idx = SettingsManager.shared.personalityPreset
        let preset = PersonalityPreset(rawValue: idx) ?? .introvert
        return preset.prompt
    }

    /// 获取当前用户设置的性格名称
    static func currentName() -> String {
        let idx = SettingsManager.shared.personalityPreset
        let preset = PersonalityPreset(rawValue: idx) ?? .introvert
        if preset == .custom {
            let custom = SettingsManager.shared.customPersonality
            return custom.isEmpty ? "社恐" : "自定义"
        }
        return preset.displayName
    }
}
