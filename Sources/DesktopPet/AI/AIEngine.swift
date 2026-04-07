import Foundation

// MARK: - AI 供应商
enum AIProvider: Int, CaseIterable {
    case claude     = 0
    case openai     = 1
    case deepseek   = 2
    case moonshot   = 3
    case zhipu      = 4
    case qwen       = 5
    case minimax    = 6

    var displayName: String {
        switch self {
        case .claude:   return "Claude (Anthropic)"
        case .openai:   return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .moonshot: return "Moonshot (Kimi)"
        case .zhipu:    return "智谱 (GLM)"
        case .qwen:     return "通义千问"
        case .minimax:  return "MiniMax"
        }
    }

    var baseURL: String {
        switch self {
        case .claude:   return "https://api.anthropic.com/v1/messages"
        case .openai:   return "https://api.openai.com/v1/chat/completions"
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .moonshot: return "https://api.moonshot.cn/v1/chat/completions"
        case .zhipu:    return "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .qwen:     return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .minimax:  return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude:   return "claude-haiku-4-5-20251001"
        case .openai:   return "gpt-4o-mini"
        case .deepseek: return "deepseek-chat"
        case .moonshot: return "moonshot-v1-8k"
        case .zhipu:    return "glm-4-flash"
        case .qwen:     return "qwen-turbo"
        case .minimax:  return "MiniMax-Text-01"
        }
    }

    /// Claude 用独特的 API 格式，其余都兼容 OpenAI 格式
    var isClaude: Bool { self == .claude }

    var keyPlaceholder: String {
        switch self {
        case .claude:   return "sk-ant-api03-..."
        case .openai:   return "sk-..."
        case .deepseek: return "sk-..."
        case .moonshot: return "sk-..."
        case .zhipu:    return "..."
        case .qwen:     return "sk-..."
        case .minimax:  return "eyJ..."
        }
    }
}

// MARK: - AI 引擎
class AIEngine {
    static let shared = AIEngine()

    /// 记录最近生成的语录，用于避免重复
    private var recentQuotes: [String] = []
    private let maxRecentQuotes = 10

    private static let logPath = NSHomeDirectory() + "/Library/Application Support/DesktopPet/ai_debug.log"

    static func debugLog(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    private var currentProvider: AIProvider {
        AIProvider(rawValue: SettingsManager.shared.aiProvider) ?? .claude
    }

    /// 调用 LLM 生成文本，无 API Key 则回调 nil
    func generate(prompt: String, completion: @escaping (String?) -> Void) {
        guard let apiKey = SettingsManager.shared.apiKey else {
            AIEngine.debugLog("no API key, skipping")
            completion(nil)
            return
        }

        let provider = currentProvider
        AIEngine.debugLog("calling \(provider.displayName) ...")
        if provider.isClaude {
            callClaude(apiKey: apiKey, model: provider.defaultModel, url: provider.baseURL, prompt: prompt, completion: completion)
        } else {
            callOpenAICompatible(apiKey: apiKey, model: provider.defaultModel, url: provider.baseURL, provider: provider, prompt: prompt, completion: completion)
        }
    }

    /// 生成日常语录（AI 模式则 50% AI + 50% 语录，否则纯语录）
    func generateQuote(ownerState: String, completion: @escaping (String) -> Void) {
        AIEngine.debugLog("generateQuote called, ownerState=\(ownerState), aiEnabled=\(SettingsManager.shared.isAISpeechEnabled)")
        guard SettingsManager.shared.isAISpeechEnabled else {
            completion(WorkerQuotes.random())
            return
        }

        // 50% 概率使用语录文件，减少 AI 调用
        if Bool.random() {
            AIEngine.debugLog("coin flip → using quotes file")
            completion(WorkerQuotes.random())
            return
        }

        let petName = SettingsManager.shared.petName
        let personality = PersonalityPreset.currentPrompt()
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let dayNames = ["", "\u{5468}\u{65e5}", "\u{5468}\u{4e00}", "\u{5468}\u{4e8c}", "\u{5468}\u{4e09}", "\u{5468}\u{56db}", "\u{5468}\u{4e94}", "\u{5468}\u{516d}"]
        let dayName = dayNames[weekday]

        // 构建避免重复/相似的提示
        var avoidRepeat = ""
        if !recentQuotes.isEmpty {
            let recent = recentQuotes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            avoidRepeat = "\n以下是你最近说过的话，请不要重复，也不要说意思相似的内容，换一个完全不同的话题和角度：\n\(recent)"
        }

        let prompt = """
        \u{4f60}\u{662f}\u{4e00}\u{53ea}\u{684c}\u{9762}\u{5ba0}\u{7269}\u{ff0c}\u{540d}\u{53eb}\(petName)\u{ff0c}\u{966a}\u{4f34}\u{4e3b}\u{4eba}\u{6253}\u{5de5}\u{3002}
        \u{4f60}\u{7684}\u{8bf4}\u{8bdd}\u{98ce}\u{683c}\u{ff1a}\(personality)
        \u{4e3b}\u{4eba}\u{5f53}\u{524d}\u{72b6}\u{6001}\u{ff1a}\(ownerState)
        \u{5f53}\u{524d}\u{65f6}\u{95f4}\u{ff1a}\(dayName) \(hour)\u{70b9}
        \(avoidRepeat)

        \u{8bf7}\u{7528}1\u{53e5}\u{7b80}\u{77ed}\u{7684}\u{8bdd}\u{ff08}15\u{5b57}\u{4ee5}\u{5185}\u{ff09}\u{8ddf}\u{4e3b}\u{4eba}\u{8bf4}\u{8bf4}\u{8bdd}\u{3002}\u{8981}\u{6c42}\u{ff1a}
        - \u{5185}\u{5bb9}\u{4ee5}\u{6253}\u{5de5}\u{4eba}\u{65e5}\u{5e38}\u{4e3a}\u{4e3b}\u{ff1a}\u{5410}\u{69fd}\u{52a0}\u{73ed}\u{3001}\u{5199}bug\u{3001}\u{5f00}\u{4f1a}\u{3001}\u{6478}\u{9c7c}\u{3001}\u{5468}\u{672b}\u{3001}\u{5de5}\u{8d44}\u{3001}\u{8001}\u{677f}\u{3001}\u{9700}\u{6c42}\u{3001}\u{4ee3}\u{7801}\u{3001}\u{5348}\u{996d}\u{3001}\u{901a}\u{52e4}\u{3001}\u{5e74}\u{5047}\u{7b49}\u{6253}\u{5de5}\u{8bdd}\u{9898}
        - \u{7528}\u{4f60}\u{7684}\u{6027}\u{683c}\u{98ce}\u{683c}\u{6765}\u{8868}\u{8fbe}\u{ff0c}\u{6bcf}\u{6b21}\u{7528}\u{4e0d}\u{540c}\u{7684}\u{89d2}\u{5ea6}\u{548c}\u{8868}\u{8fbe}
        - \u{8003}\u{8651}\u{5f53}\u{524d}\u{65f6}\u{95f4}\u{548c}\u{4e3b}\u{4eba}\u{72b6}\u{6001}\u{ff08}\u{6bd4}\u{5982}\u{5468}\u{4e00}\u{65e9}\u{4e0a}\u{5410}\u{69fd}\u{4e0a}\u{73ed}\u{3001}\u{5468}\u{4e94}\u{4e0b}\u{5348}\u{671f}\u{5f85}\u{4e0b}\u{73ed}\u{3001}\u{6df1}\u{591c}\u{52a0}\u{73ed}\u{5410}\u{69fd}\u{7b49}\u{ff09}
        - \u{53e3}\u{8bed}\u{5316}\u{3001}\u{6709}\u{68b1}\u{5b50}\u{611f}\u{3001}\u{6709}\u{5171}\u{9e23}
        - \u{4e0d}\u{8981}\u{6bcf}\u{6b21}\u{7528}\u{76f8}\u{540c}\u{7684}\u{5f00}\u{5934}\u{6216}\u{53e5}\u{5f0f}
        - \u{53ef}\u{4ee5}\u{7528} emoji \u{4f46}\u{4e0d}\u{8981}\u{592a}\u{591a}
        - \u{53ea}\u{8f93}\u{51fa}\u{8fd9}\u{4e00}\u{53e5}\u{8bdd}\u{ff0c}\u{4e0d}\u{8981}\u{52a0}\u{5f15}\u{53f7}\u{548c}\u{5176}\u{4ed6}\u{5185}\u{5bb9}
        """

        generate(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                if let text = result, !text.isEmpty {
                    let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                    // 记录最近语录，避免重复
                    self?.recentQuotes.append(cleaned)
                    if (self?.recentQuotes.count ?? 0) > (self?.maxRecentQuotes ?? 5) {
                        self?.recentQuotes.removeFirst()
                    }
                    completion(cleaned)
                } else {
                    completion(WorkerQuotes.random())
                }
            }
        }
    }

    // MARK: - 串门对话生成

    /// 静态对话回退（无 API Key 时使用）
    private static let fallbackDialogues: [[String]] = [
        ["你好呀~来找你玩啦！", "欢迎欢迎~快进来坐！",
         "你这里好温馨啊", "谢谢，随便看看~",
         "下次你也来我那儿玩！", "好的好的，一定去！",
         "那我先回去啦，拜拜~", "慢走啊，下次见！",
         "嗯嗯，回见！", "期待下次见面~",
         "走啦走啦~", "路上小心呀！"],
        ["嘿！好久不见！", "是啊，最近忙吗？",
         "还行，摸鱼中", "哈哈我也是",
         "主人在加班呢", "我主人也在干活",
         "真辛苦啊我们", "就是说嘛",
         "好了我该回去了", "好的，有空再来",
         "拜拜！", "再见~"],
        ["来啦来啦~", "哟，稀客啊！",
         "今天天气真好", "是呀，适合串门",
         "你吃了吗？", "刚吃过~",
         "我也刚吃饱", "吃饱了就开心",
         "时间不早了，我走了", "好的，路上注意",
         "回见咯~", "下次再聊！"],
    ]

    /// 生成串门对话（6轮12句）
    /// - Returns: [(speaker: "A"/"B", text: String)]
    func generateDialogue(
        visitorName: String, visitorPersonality: String,
        hostName: String, hostPersonality: String,
        completion: @escaping ([(speaker: String, text: String)]) -> Void
    ) {
        guard SettingsManager.shared.apiKey != nil else {
            // 无 Key，使用静态对话
            let lines = AIEngine.fallbackDialogues.randomElement()!
            var result: [(speaker: String, text: String)] = []
            for i in stride(from: 0, to: lines.count, by: 2) {
                result.append((speaker: "A", text: lines[i]))
                if i + 1 < lines.count {
                    result.append((speaker: "B", text: lines[i + 1]))
                }
            }
            completion(result)
            return
        }

        let prompt = """
        你是两只桌面宠物的对话编剧。
        宠物A名叫\(visitorName)，性格：\(visitorPersonality)
        宠物B名叫\(hostName)，性格：\(hostPersonality)
        A去B家做客。请生成6轮对话（A说B说交替），每句15字以内，口语化。
        格式：A: xxx（换行）B: xxx，最后一句是A的告别。
        只输出对话。
        """

        generate(prompt: prompt) { result in
            DispatchQueue.main.async {
                guard let text = result, !text.isEmpty else {
                    // LLM 失败，回退静态对话
                    let lines = AIEngine.fallbackDialogues.randomElement()!
                    var fallback: [(speaker: String, text: String)] = []
                    for i in stride(from: 0, to: lines.count, by: 2) {
                        fallback.append((speaker: "A", text: lines[i]))
                        if i + 1 < lines.count {
                            fallback.append((speaker: "B", text: lines[i + 1]))
                        }
                    }
                    completion(fallback)
                    return
                }

                // 解析 "A: xxx\nB: xxx" 格式
                var dialogues: [(speaker: String, text: String)] = []
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("A:") || trimmed.hasPrefix("A：") {
                        let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        if !content.isEmpty { dialogues.append((speaker: "A", text: content)) }
                    } else if trimmed.hasPrefix("B:") || trimmed.hasPrefix("B：") {
                        let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        if !content.isEmpty { dialogues.append((speaker: "B", text: content)) }
                    }
                }

                if dialogues.isEmpty {
                    // 解析失败，回退
                    let fallbackLines = AIEngine.fallbackDialogues.randomElement()!
                    var fallback: [(speaker: String, text: String)] = []
                    for i in stride(from: 0, to: fallbackLines.count, by: 2) {
                        fallback.append((speaker: "A", text: fallbackLines[i]))
                        if i + 1 < fallbackLines.count {
                            fallback.append((speaker: "B", text: fallbackLines[i + 1]))
                        }
                    }
                    completion(fallback)
                } else {
                    completion(dialogues)
                }
            }
        }
    }

    // MARK: - Claude API (独特格式)

    private func callClaude(apiKey: String, model: String, url: String, prompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: url) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "temperature": 1.0,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                NSLog("[AIEngine] Claude API error: %@", error?.localizedDescription ?? "unknown")
                completion(nil)
                return
            }
            completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
    }

    // MARK: - OpenAI 兼容格式（OpenAI / DeepSeek / Moonshot / 智谱 / 通义 / MiniMax）

    private func callOpenAICompatible(apiKey: String, model: String, url: String, provider: AIProvider, prompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: url) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "temperature": 1.0,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else {
                if let data = data, let raw = String(data: data, encoding: .utf8) {
                    AIEngine.debugLog("\(provider.displayName) ERROR: \(raw)")
                } else {
                    AIEngine.debugLog("\(provider.displayName) ERROR: \(error?.localizedDescription ?? "unknown")")
                }
                completion(nil)
                return
            }
            let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            AIEngine.debugLog("\(provider.displayName) OK: \(result)")
            completion(result)
        }.resume()
    }
}
