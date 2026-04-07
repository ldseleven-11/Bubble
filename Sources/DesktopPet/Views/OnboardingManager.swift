import AppKit
import QuartzCore

// MARK: - 新手引导管理器
class OnboardingManager {
    static let shared = OnboardingManager()
    private(set) var isOnboarding = false
    private var currentStep = 0
    private var bubble: OnboardingBubbleWindow?
    private var nameWindow: NSWindow?
    private var stepTimer: Timer?
    weak var petWindow: NSWindow?
    var onFinished: (() -> Void)?

    private let steps: [(String) -> String] = [
        { name in "嗨！我是\(name)~ 初次见面！\n右键点我可以看到更多功能哦~" },
        { _ in "在「好友」面板里添加朋友的配对码\n你们的宠物就能互相串门！" },
        { name in "去「设置」里还能换我的性格和形象！\n\(name)会一直陪着你的~" },
    ]

    func startIfNeeded(petWindow: NSWindow) {
        self.petWindow = petWindow
        guard !SettingsManager.shared.hasCompletedOnboarding else { return }
        isOnboarding = true
        showNameDialog()
    }

    // MARK: - Step 0: 取名弹窗

    private func showNameDialog() {
        let w: CGFloat = 300
        let h: CGFloat = 160
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.center()
        // 不可关闭
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h - 28))

        // 标题
        let titleLabel = NSTextField(labelWithString: "给你的宠物取个名字吧！")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = DT.textPrimary
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 72, width: w - 40, height: 24)
        container.addSubview(titleLabel)

        // 输入框
        let textField = NSTextField(frame: NSRect(x: 40, y: 40, width: w - 80, height: 24))
        textField.placeholderString = "起个名字..."
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.bezelStyle = .roundedBezel
        container.addSubview(textField)

        // 确定按钮
        let button = NSButton(frame: NSRect(x: (w - 80) / 2, y: 6, width: 80, height: 28))
        button.title = "确定"
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        container.addSubview(button)

        panel.contentView = container
        self.nameWindow = panel

        // 按钮点击
        button.target = self
        button.action = #selector(nameConfirmClicked(_:))
        // 把 textField 存到 tag 不行，用 identifier
        textField.identifier = NSUserInterfaceItemIdentifier("onboarding_name_field")

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        textField.becomeFirstResponder()
    }

    @objc private func nameConfirmClicked(_ sender: NSButton) {
        guard let panel = nameWindow else { return }
        // 找到输入框
        let textField = panel.contentView?.subviews.compactMap({ $0 as? NSTextField })
            .first(where: { $0.identifier?.rawValue == "onboarding_name_field" })
        let name = textField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            SettingsManager.shared.petName = name
        }
        // 默认名"皮皮"已经在 SettingsManager.petName getter 里
        onNameConfirmed()
    }

    private func onNameConfirmed() {
        nameWindow?.orderOut(nil)
        nameWindow = nil
        // 开始气泡引导
        currentStep = 0
        showStep(currentStep)
    }

    // MARK: - Steps 1-3: 气泡引导

    private func showStep(_ step: Int) {
        guard step < steps.count, let petWin = petWindow else {
            finish()
            return
        }

        let petName = SettingsManager.shared.petName
        let text = steps[step](petName)
        let indicator = "\(step + 1)/\(steps.count)"

        let isLast = step == steps.count - 1

        if bubble == nil {
            bubble = OnboardingBubbleWindow()
            bubble?.onTapped = { [weak self] in
                self?.advanceToNext()
            }
        }

        bubble?.show(text: text, stepIndicator: indicator, hintText: isLast ? "点击完成" : "点击下一步",
                     currentStep: step, totalSteps: steps.count, above: petWin)
    }

    private func advanceToNext() {
        currentStep += 1
        if currentStep < steps.count {
            showStep(currentStep)
        } else {
            finish()
        }
    }

    private func finish() {
        bubble?.hideBubble()
        bubble = nil
        isOnboarding = false
        SettingsManager.shared.hasCompletedOnboarding = true
        onFinished?()
    }
}

// MARK: - 引导专用气泡窗口
class OnboardingBubbleWindow: NSWindow {
    private var textField: NSTextField!
    private var stepLabel: NSTextField!
    private var hintLabel: NSTextField!
    private weak var followingWindow: NSWindow?
    private var followTimer: Timer?
    var onTapped: (() -> Void)?

    // 进度指示器
    private var dotLayers: [CALayer] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = false  // 可点击跳过

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        container.wantsLayer = true

        textField = NSTextField(labelWithString: "")
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textField.textColor = DT.textPrimary
        textField.maximumNumberOfLines = 3
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        container.addSubview(textField)

        stepLabel = NSTextField(labelWithString: "")
        stepLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        stepLabel.textColor = DT.textTertiary
        stepLabel.alignment = .center
        stepLabel.wantsLayer = true
        stepLabel.layer?.backgroundColor = DT.bgMuted.cgColor
        stepLabel.layer?.cornerRadius = 7
        container.addSubview(stepLabel)

        hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = DT.primary
        hintLabel.alignment = .right
        container.addSubview(hintLabel)

        contentView = container
    }

    func show(text: String, stepIndicator: String, hintText: String, currentStep: Int, totalSteps: Int, above petWindow: NSWindow) {
        followingWindow = petWindow
        textField.stringValue = text
        stepLabel.stringValue = " \(stepIndicator) "
        hintLabel.stringValue = hintText + " →"

        // 计算多行文字所需高度
        let maxWidth: CGFloat = 240
        let font = textField.font ?? NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )

        let bubbleWidth: CGFloat = 280
        let textHeight = ceil(textSize.height) + 4
        let progressH: CGFloat = 20
        let bubbleHeight = max(50, textHeight + 16 + progressH + 8) // 上下留 padding

        setContentSize(NSSize(width: bubbleWidth, height: bubbleHeight))
        if let container = contentView {
            container.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
            container.layer?.sublayers?.filter({ $0 is CAShapeLayer }).forEach({ $0.removeFromSuperlayer() })

            let bubbleLayer = CAShapeLayer()
            let cornerRadius: CGFloat = DT.radiusLg
            let bubbleRect = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
            bubbleLayer.path = CGPath(roundedRect: bubbleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            bubbleLayer.fillColor = DT.bgSurface.cgColor
            DT.applyShadowLg(to: bubbleLayer)
            container.layer?.insertSublayer(bubbleLayer, at: 0)

            // 清除旧的进度点
            dotLayers.forEach { $0.removeFromSuperlayer() }
            dotLayers.removeAll()

            // 绘制进度指示器（底部居左）
            let dotSize: CGFloat = 6
            let activeDotW: CGFloat = 18
            let dotGap: CGFloat = 5
            var totalDotsW: CGFloat = 0
            for i in 0..<totalSteps {
                totalDotsW += (i == currentStep) ? activeDotW : dotSize
                if i < totalSteps - 1 { totalDotsW += dotGap }
            }

            var dotX: CGFloat = 20
            let dotY: CGFloat = 8 + (progressH - dotSize) / 2
            for i in 0..<totalSteps {
                let dot = CALayer()
                let isActive = (i == currentStep)
                let w = isActive ? activeDotW : dotSize
                dot.frame = NSRect(x: dotX, y: dotY, width: w, height: dotSize)
                dot.cornerRadius = dotSize / 2
                dot.backgroundColor = isActive ? DT.primary.cgColor : DT.borderDefault.cgColor
                container.layer?.addSublayer(dot)
                dotLayers.append(dot)
                dotX += w + dotGap
            }
        }

        textField.frame = NSRect(x: 20, y: progressH + 10, width: bubbleWidth - 40, height: textHeight)
        stepLabel.frame = NSRect(x: bubbleWidth - 48, y: bubbleHeight - 22, width: 36, height: 16)
        hintLabel.frame = NSRect(x: bubbleWidth - 100, y: 8, width: 80, height: progressH)

        updatePosition()

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1
        }

        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTapped?()
    }

    private func updatePosition() {
        guard let petWindow = followingWindow else { return }
        let petFrame = petWindow.frame
        let bubbleWidth = frame.width
        let x = petFrame.midX - bubbleWidth / 2
        let y = petFrame.maxY - 45
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hideBubble() {
        followTimer?.invalidate()
        followTimer = nil
        followingWindow = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
