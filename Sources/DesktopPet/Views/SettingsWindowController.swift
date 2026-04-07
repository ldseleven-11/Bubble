import AppKit

// MARK: - 设置窗口
class SettingsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow?
    var commandTextView: NSTextView?
    var modePopup: NSPopUpButton?
    var rangePopup: NSPopUpButton?
    var sizePopup: NSPopUpButton?
    var workingEffectPopup: NSPopUpButton?
    var petModePopup: NSPopUpButton?
    var pickImageButton: NSButton?
    var deleteImageButton: NSButton?
    var imageStatusLabel: NSTextField?
    var previewImageView: NSImageView?
    var petNameField: NSTextField?
    var personalityPopup: NSPopUpButton?
    var personalityTextView: NSTextView?
    var aiProviderPopup: NSPopUpButton?
    var apiKeyField: NSSecureTextField?
    var aiStatusLabel: NSTextField?
    var aiTestResultLabel: NSTextField?
    var dingtalkCheckbox: NSButton?
    var gatewayHostField: NSTextField?
    var gatewayPortField: NSTextField?
    var openclawTokenField: NSTextField?
    var dingtalkUserIdField: NSTextField?
    var dtStatusLabel: NSTextField?
    var onMonitorModeChanged: ((Int) -> Void)?
    var onPetModeChanged: ((Int) -> Void)?
    var onPetSizeChanged: (() -> Void)?
    var onDingTalkChanged: ((Bool) -> Void)?
    var onAIModeChanged: ((Int, Int) -> Void)?  // (oldMode, newMode)
    var onTestOpenClaw: ((@escaping (Bool, String?) -> Void) -> Void)?
    var chatTestResultLabel: NSTextField?
    var speechModePopup: NSPopUpButton?
    // 助手模式连接检查步骤 UI
    private var connectStepLabels: [NSTextField] = []       // 3 个步骤的状态标签
    private var connectStepIcons: [NSTextField] = []        // 3 个步骤的图标（○/⟳/✓/✗）
    private var connectStartBtn: NSButton?                  // "开始连接" 按钮
    private var testGateway: OpenClawGateway?               // 验证用的临时 gateway
    private var aiConfigViews: [NSView] = []

    // AI 能力 Tab
    private var aiCapabilityScrollView: NSScrollView?
    private var aiCardExpandedPanes: [NSView?] = [nil, nil, nil]
    private var aiCardButtons: [NSButton?] = [nil, nil, nil]
    private var aiCardStatusLabels: [NSTextField?] = [nil, nil, nil]

    private var sidebarTableView: NSTableView?
    private var contentContainer: NSView?
    private var panes: [NSView] = []
    private let sidebarItems = ["宠物", "AI 能力", "碎碎念", "高级"]
    private let sidebarSFSymbols = ["pawprint.fill", "sparkles", "bubble.left.fill", "gearshape"]

    func showSettings(selectTab: Int = 0) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // 切换到指定 Tab
            if selectTab >= 0 && selectTab < panes.count {
                sidebarTableView?.selectRowIndexes(IndexSet(integer: selectTab), byExtendingSelection: false)
            }
            return
        }

        let winW: CGFloat = 680
        let winH: CGFloat = 520

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "DesktopPet 设置"
        win.center()
        win.delegate = self
        win.level = .floating
        win.isReleasedWhenClosed = false

        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = DT.bgSurface.cgColor

        // ── 底部按钮栏 ──
        let bottomH: CGFloat = 52

        // 底部背景
        let bottomBg = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: bottomH))
        bottomBg.wantsLayer = true
        bottomBg.layer?.backgroundColor = DT.bgMuted.cgColor
        rootView.addSubview(bottomBg)

        let saveButton = NSButton(frame: NSRect(x: winW - 130, y: 10, width: 110, height: 32))
        saveButton.title = "保存设置"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        rootView.addSubview(saveButton)

        let resetButton = NSButton(frame: NSRect(x: winW - 240, y: 10, width: 100, height: 32))
        resetButton.title = "恢复默认"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetSettings)
        rootView.addSubview(resetButton)

        let sep = NSBox(frame: NSRect(x: 0, y: bottomH, width: winW, height: 1))
        sep.boxType = .separator
        rootView.addSubview(sep)

        // ── 侧边栏 + 内容区 ──
        let mainH = winH - bottomH - 1
        let sidebarW: CGFloat = 180
        let contentW = winW - sidebarW - 1

        // 侧边栏背景
        let sidebarBg = NSView(frame: NSRect(x: 0, y: bottomH + 1, width: sidebarW, height: mainH))
        sidebarBg.wantsLayer = true
        sidebarBg.layer?.backgroundColor = DT.bgMuted.cgColor
        rootView.addSubview(sidebarBg)

        let sidebarTopPad: CGFloat = 20
        let sidebarScroll = NSScrollView(frame: NSRect(x: 0, y: bottomH + 1, width: sidebarW, height: mainH - sidebarTopPad))
        sidebarScroll.hasVerticalScroller = false
        sidebarScroll.drawsBackground = false

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.gridColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.width = sidebarW - 16
        tableView.addTableColumn(column)

        sidebarScroll.documentView = tableView
        rootView.addSubview(sidebarScroll)
        self.sidebarTableView = tableView

        // 竖分隔线
        let vSep = NSBox(frame: NSRect(x: sidebarW, y: bottomH + 1, width: 1, height: mainH))
        vSep.boxType = .separator
        rootView.addSubview(vSep)

        // 内容容器
        let container = NSView(frame: NSRect(x: sidebarW + 1, y: bottomH + 1, width: contentW, height: mainH))
        rootView.addSubview(container)
        self.contentContainer = container

        // 构建 4 个分页
        panes = [
            buildPetPane(width: contentW, height: mainH),
            buildAICapabilityPane(width: contentW, height: mainH),
            buildAIPane(width: contentW, height: mainH),
            buildAdvancedPane(width: contentW, height: mainH)
        ]

        for pane in panes {
            pane.isHidden = true
            container.addSubview(pane)
        }

        // 选中指定 Tab（延迟一帧确保 rowView 已渲染，选中样式才能生效）
        let tabIndex = (selectTab >= 0 && selectTab < panes.count) ? selectTab : 0
        panes[tabIndex].isHidden = false
        DispatchQueue.main.async {
            tableView.selectRowIndexes(IndexSet(integer: tabIndex), byExtendingSelection: false)
        }

        win.contentView = rootView
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return sidebarItems.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("SidebarCell")
        var cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 164, height: 36))
            cell?.identifier = cellId
            cell?.wantsLayer = true
            cell?.layer?.cornerRadius = DT.radiusMd

            // Icon (SF Symbols)
            let iconView = NSImageView(frame: NSRect(x: 12, y: 8, width: 20, height: 20))
            iconView.imageScaling = .scaleProportionallyDown
            iconView.tag = 100
            cell?.addSubview(iconView)

            // Text
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            tf.frame = NSRect(x: 38, y: 8, width: 112, height: 20)
            cell?.addSubview(tf)
            cell?.textField = tf
        }

        // 设置内容
        cell?.textField?.stringValue = sidebarItems[row]
        if let iconView = cell?.viewWithTag(100) as? NSImageView {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let img = NSImage(systemSymbolName: sidebarSFSymbols[row], accessibilityDescription: sidebarItems[row])?
                .withSymbolConfiguration(config)
            iconView.image = img
            iconView.contentTintColor = DT.textSecondary
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return WarmSidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let idx = sidebarTableView?.selectedRow ?? 0
        switchTab(to: idx)
    }

    private func switchTab(to idx: Int) {
        guard idx >= 0 && idx < panes.count else { return }
        for (i, pane) in panes.enumerated() {
            pane.isHidden = (i != idx)
        }
    }

    // MARK: - 页面标题辅助

    private func addPageTitle(_ title: String, to pane: NSView, at y: inout CGFloat, pad: CGFloat) {
        y -= 48  // 22pt 顶部留白 + 26pt 标题高度
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: pad, y: y, width: 300, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = DT.textPrimary
        pane.addSubview(titleLabel)
        y -= 16
    }

    private func addSectionTitle(_ title: String, to pane: NSView, at y: inout CGFloat, pad: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 14)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = DT.textTertiary
        pane.addSubview(label)
        y -= 22
    }

    // MARK: - 宠物

    private func buildPetPane(width: CGFloat, height: CGFloat) -> NSView {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 28
        let labelW: CGFloat = 80
        let controlX: CGFloat = pad + labelW + 12
        var y: CGFloat = height

        addPageTitle("宠物", to: pane, at: &y, pad: pad)

        // ── 形象 ──
        addSectionTitle("形象", to: pane, at: &y, pad: pad, width: width)

        // 宠物形象
        let petLabel = NSTextField(labelWithString: "宠物形象")
        petLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        petLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        petLabel.textColor = DT.textPrimary
        pane.addSubview(petLabel)

        let pmPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 130, height: 26))
        pmPopup.addItems(withTitles: ["皮卡丘", "自定义 1", "自定义 2", "自定义 3"])
        pmPopup.selectItem(at: SettingsManager.shared.petMode)
        pmPopup.target = self
        pmPopup.action = #selector(petModeSelectionChanged)
        pane.addSubview(pmPopup)
        self.petModePopup = pmPopup

        let isCustom = SettingsManager.shared.petMode >= 1
        let currentSlot = SettingsManager.shared.petMode
        let hasImg = isCustom && SettingsManager.shared.hasCustomImage(slot: currentSlot)

        let imgBtn = NSButton(frame: NSRect(x: controlX + 138, y: y - 3, width: 80, height: 26))
        imgBtn.title = "选择图片"
        imgBtn.bezelStyle = .rounded
        imgBtn.target = self
        imgBtn.action = #selector(pickImage)
        imgBtn.isEnabled = isCustom
        pane.addSubview(imgBtn)
        self.pickImageButton = imgBtn

        let delBtn = NSButton(frame: NSRect(x: controlX + 224, y: y - 3, width: 60, height: 26))
        delBtn.title = "删除"
        delBtn.bezelStyle = .rounded
        delBtn.target = self
        delBtn.action = #selector(deleteImage)
        delBtn.isEnabled = isCustom && hasImg
        pane.addSubview(delBtn)
        self.deleteImageButton = delBtn

        let statusLabel = NSTextField(labelWithString: hasImg ? "✓ 已选择" : "")
        statusLabel.frame = NSRect(x: controlX + 290, y: y + 1, width: 70, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = hasImg ? DT.success : DT.textTertiary
        pane.addSubview(statusLabel)
        self.imageStatusLabel = statusLabel

        y -= 84

        // 预览图
        let previewBox = NSBox(frame: NSRect(x: controlX, y: y, width: 72, height: 72))
        previewBox.boxType = .custom
        previewBox.borderColor = DT.borderDefault
        previewBox.fillColor = DT.bgMuted
        previewBox.cornerRadius = DT.radiusMd
        pane.addSubview(previewBox)

        let imgView = NSImageView(frame: NSRect(x: controlX + 4, y: y + 4, width: 64, height: 64))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.imageAlignment = .alignCenter
        pane.addSubview(imgView)
        self.previewImageView = imgView

        let previewHint = NSTextField(labelWithString: "预览")
        previewHint.frame = NSRect(x: controlX + 80, y: y + 28, width: 40, height: 16)
        previewHint.font = NSFont.systemFont(ofSize: 11)
        previewHint.textColor = DT.textTertiary
        pane.addSubview(previewHint)

        updatePreview()

        y -= 36

        // ── 基本信息 ──
        addSectionTitle("基本信息", to: pane, at: &y, pad: pad, width: width)

        // 宠物名字
        let nameLabel = NSTextField(labelWithString: "宠物名字")
        nameLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = DT.textPrimary
        pane.addSubview(nameLabel)

        let nameField = NSTextField(frame: NSRect(x: controlX, y: y - 2, width: 200, height: 24))
        nameField.stringValue = SettingsManager.shared.petName
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.placeholderString = "给宠物起个名字"
        pane.addSubview(nameField)
        self.petNameField = nameField

        y -= 34

        // ── 外观 ──
        addSectionTitle("外观", to: pane, at: &y, pad: pad, width: width)

        // 宠物大小
        let sizeLabel = NSTextField(labelWithString: "宠物大小")
        sizeLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        sizeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        sizeLabel.textColor = DT.textPrimary
        pane.addSubview(sizeLabel)

        let sPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 200, height: 26))
        sPopup.addItems(withTitles: ["小 (80pt)", "中 (110pt)", "大 (140pt)", "特大 (180pt)"])
        sPopup.selectItem(at: SettingsManager.shared.petSizeIndex)
        pane.addSubview(sPopup)
        self.sizePopup = sPopup

        y -= 34

        // 工作动效
        let effectLabel = NSTextField(labelWithString: "工作效果")
        effectLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        effectLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        effectLabel.textColor = DT.textPrimary
        pane.addSubview(effectLabel)

        let wePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 200, height: 26))
        wePopup.addItems(withTitles: ["快速摇晃", "转圈圈"])
        wePopup.selectItem(at: SettingsManager.shared.workingEffect)
        pane.addSubview(wePopup)
        self.workingEffectPopup = wePopup

        y -= 34

        // 活动范围
        let rangeLabel = NSTextField(labelWithString: "活动范围")
        rangeLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        rangeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        rangeLabel.textColor = DT.textPrimary
        pane.addSubview(rangeLabel)

        let rPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 200, height: 26))
        rPopup.addItems(withTitles: ["全屏", "左半屏", "右半屏", "左 1/3", "右 1/3", "左 1/4", "右 1/4", "原地不动"])
        rPopup.selectItem(at: SettingsManager.shared.activityRange)
        pane.addSubview(rPopup)
        self.rangePopup = rPopup

        return pane
    }

    // MARK: - 碎碎念

    private func buildAIPane(width: CGFloat, height: CGFloat) -> NSView {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 28
        let labelW: CGFloat = 80
        let controlX: CGFloat = pad + labelW + 12
        var y: CGFloat = height

        addPageTitle("碎碎念", to: pane, at: &y, pad: pad)
        addSectionTitle("说话方式", to: pane, at: &y, pad: pad, width: width)

        // 说话方式选择
        let modeLabel = NSTextField(labelWithString: "说话方式")
        modeLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.textColor = DT.textPrimary
        pane.addSubview(modeLabel)

        let smPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 160, height: 26))
        smPopup.addItems(withTitles: ["语录文件", "AI 生成"])
        smPopup.selectItem(at: SettingsManager.shared.speechMode)
        smPopup.target = self
        smPopup.action = #selector(speechModeChanged)
        pane.addSubview(smPopup)
        self.speechModePopup = smPopup

        y -= 28

        // 状态提示
        let aiStatus = NSTextField(labelWithString: "")
        aiStatus.frame = NSRect(x: controlX, y: y, width: width - controlX - pad, height: 16)
        aiStatus.font = NSFont.systemFont(ofSize: 11)
        aiStatus.textColor = DT.textTertiary
        pane.addSubview(aiStatus)
        self.aiStatusLabel = aiStatus
        updateAIStatusLabel()

        y -= 28

        // "去设置 AI" 按钮（仅 AI 模式下且未配置时显示）
        let goSettingsBtn = NSButton(frame: NSRect(x: controlX, y: y, width: 160, height: 26))
        goSettingsBtn.title = "前往 AI 能力设置 →"
        goSettingsBtn.bezelStyle = .rounded
        goSettingsBtn.font = NSFont.systemFont(ofSize: 12)
        goSettingsBtn.target = self
        goSettingsBtn.action = #selector(jumpToAICapabilityTab)
        goSettingsBtn.isHidden = !(SettingsManager.shared.speechMode == 1 && SettingsManager.shared.aiMode == 0)
        goSettingsBtn.tag = 999  // 用于后续查找
        pane.addSubview(goSettingsBtn)

        y -= 16

        let speechSep = NSBox(frame: NSRect(x: pad, y: y, width: width - pad * 2, height: 1))
        speechSep.boxType = .separator
        pane.addSubview(speechSep)

        y -= 28

        addSectionTitle("语录", to: pane, at: &y, pad: pad, width: width)

        // 语录文件编辑
        let quotesLabel = NSTextField(labelWithString: "语录文件")
        quotesLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        quotesLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        quotesLabel.textColor = DT.textPrimary
        pane.addSubview(quotesLabel)

        let quotesBtn = NSButton(frame: NSRect(x: controlX, y: y - 3, width: 120, height: 26))
        quotesBtn.title = "编辑语录文件..."
        quotesBtn.bezelStyle = .rounded
        quotesBtn.font = NSFont.systemFont(ofSize: 12)
        quotesBtn.target = self
        quotesBtn.action = #selector(openQuotesFile)
        pane.addSubview(quotesBtn)

        let quotesHint = NSTextField(labelWithString: "语录模式或 AI 降级时使用")
        quotesHint.frame = NSRect(x: controlX + 128, y: y, width: 220, height: 16)
        quotesHint.font = NSFont.systemFont(ofSize: 11)
        quotesHint.textColor = DT.textTertiary
        pane.addSubview(quotesHint)

        return pane
    }

    private func updateAIStatusLabel() {
        let isAI = speechModePopup?.indexOfSelectedItem == 1
        let aiMode = SettingsManager.shared.aiMode
        if isAI {
            if aiMode == 1 {
                let provider = AIProvider(rawValue: SettingsManager.shared.aiProvider) ?? .claude
                aiStatusLabel?.stringValue = "✓ 使用聪明模式（\(provider.displayName)）生成碎碎念"
                aiStatusLabel?.textColor = DT.success
            } else if aiMode == 2 {
                aiStatusLabel?.stringValue = "✓ 使用助手模式（OpenClaw）生成碎碎念"
                aiStatusLabel?.textColor = DT.success
            } else {
                aiStatusLabel?.stringValue = "需要先启用聪明模式或助手模式"
                aiStatusLabel?.textColor = DT.warning
            }
        } else {
            aiStatusLabel?.stringValue = "从语录文件中随机说话"
            aiStatusLabel?.textColor = DT.textSecondary
        }
    }

    @objc func jumpToAICapabilityTab() {
        // 切换到 AI 能力 Tab
        sidebarTableView?.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        switchTab(to: 1)
    }

    @objc func speechModeChanged() {
        let isAI = speechModePopup?.indexOfSelectedItem == 1
        let aiMode = SettingsManager.shared.aiMode

        // 更新"前往设置"按钮的可见性
        if let pane = panes.count > 2 ? panes[2] : nil {
            for subview in pane.subviews where subview.tag == 999 {
                subview.isHidden = !(isAI && aiMode == 0)
            }
        }
        updateAIStatusLabel()
    }

    // MARK: - AI 能力

    private func buildAICapabilityPane(width: CGFloat, height: CGFloat) -> NSView {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 28
        let cardW = width - pad * 2
        let currentMode = SettingsManager.shared.aiMode
        var y: CGFloat = height

        addPageTitle("AI 能力", to: pane, at: &y, pad: pad)

        // 描述
        let descLabel = NSTextField(labelWithString: "选择宠物的智能模式，三种模式互斥，切换后立即生效")
        descLabel.frame = NSRect(x: pad, y: y, width: cardW, height: 16)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = DT.textSecondary
        pane.addSubview(descLabel)
        y -= 28

        let card0 = buildModeCard(index: 0, title: "基础模式", desc: "语料库随机说话，不能对话",
                                  badge: "免费", badgeType: 0,
                                  isActive: currentMode == 0, width: cardW)
        let card1 = buildModeCard(index: 1, title: "聪明模式", desc: "AI 生成碎碎念，可以和你聊天",
                                  badge: "API", badgeType: 1,
                                  isActive: currentMode == 1, width: cardW)
        let card2 = buildModeCard(index: 2, title: "助手模式", desc: "AI 助手，能聊天还能帮你做事",
                                  badge: "PRO", badgeType: 2,
                                  isActive: currentMode == 2, width: cardW)

        let cards = [card0, card1, card2]
        let gap: CGFloat = 12

        for card in cards {
            y -= card.frame.height
            card.frame.origin = NSPoint(x: pad, y: y)
            pane.addSubview(card)
            y -= gap
        }

        return pane
    }

    private func buildModeCard(index: Int, title: String, desc: String, badge: String, badgeType: Int, isActive: Bool, width: CGFloat) -> NSView {
        let pad: CGFloat = 16
        // 计算卡片高度
        var cardH: CGFloat = 60  // 基本高度（标题行 + 描述行 + padding）
        if isActive && (index == 1 || index == 2) {
            // 使用中且有配置项：增加状态行 + 设置按钮行
            cardH = 94
        }

        let card = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardH))
        card.wantsLayer = true
        card.layer?.cornerRadius = DT.radiusLg
        card.layer?.borderWidth = isActive ? 2 : 1.5
        card.layer?.borderColor = (isActive ? DT.primary : DT.borderDefault).cgColor
        card.layer?.backgroundColor = (isActive
            ? DT.primary.withAlphaComponent(0.03)
            : DT.bgSurface).cgColor

        let contentView = card

        // 单选圆圈
        let radioSize: CGFloat = 18
        let radioView = NSView(frame: NSRect(x: pad, y: cardH - pad - radioSize + 2, width: radioSize, height: radioSize))
        radioView.wantsLayer = true
        radioView.layer?.cornerRadius = radioSize / 2
        radioView.layer?.borderWidth = 2
        radioView.layer?.borderColor = (isActive ? DT.primary : DT.borderDefault).cgColor
        contentView.addSubview(radioView)

        if isActive {
            let innerDot = NSView(frame: NSRect(x: 5, y: 5, width: 8, height: 8))
            innerDot.wantsLayer = true
            innerDot.layer?.cornerRadius = 4
            innerDot.layer?.backgroundColor = DT.primary.cgColor
            radioView.addSubview(innerDot)
        }

        // 标题
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: pad + radioSize + 10, y: cardH - pad - 16, width: 200, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = DT.textPrimary
        contentView.addSubview(titleLabel)

        // 描述
        let descLabel = NSTextField(labelWithString: desc)
        descLabel.frame = NSRect(x: pad + radioSize + 10, y: cardH - pad - 32, width: width - pad * 2 - radioSize - 80, height: 14)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = DT.textTertiary
        contentView.addSubview(descLabel)

        // 右上角 badge
        let badgeLabel = NSTextField(labelWithString: badge)
        badgeLabel.alignment = .center
        badgeLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        badgeLabel.wantsLayer = true
        badgeLabel.isBezeled = false
        badgeLabel.isBordered = false
        badgeLabel.isEditable = false

        let badgeW: CGFloat = badge.count > 2 ? 40 : 32
        badgeLabel.frame = NSRect(x: width - pad - badgeW, y: cardH - pad - 14, width: badgeW, height: 16)
        badgeLabel.layer?.cornerRadius = 8

        switch badgeType {
        case 0: // free - green
            badgeLabel.backgroundColor = NSColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1)
            badgeLabel.textColor = NSColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
        case 1: // api - blue
            badgeLabel.backgroundColor = NSColor(red: 0.89, green: 0.95, blue: 0.99, alpha: 1)
            badgeLabel.textColor = NSColor(red: 0.08, green: 0.40, blue: 0.75, alpha: 1)
        default: // pro - orange
            badgeLabel.backgroundColor = NSColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1)
            badgeLabel.textColor = NSColor(red: 0.90, green: 0.32, blue: 0.0, alpha: 1)
        }
        contentView.addSubview(badgeLabel)

        // 已启用状态 or 启用按钮
        if isActive {
            // 有配置项的模式：提供设置入口
            if index == 1 || index == 2 {
                let editBtn = NSButton(frame: NSRect(x: width - pad - 60, y: 8, width: 60, height: 26))
                editBtn.title = "设置"
                editBtn.bezelStyle = .rounded
                editBtn.font = NSFont.systemFont(ofSize: 12)
                editBtn.tag = index
                editBtn.target = self
                editBtn.action = index == 1 ? #selector(expandSmartModeConfig(_:)) : #selector(expandAssistantModeConfig(_:))
                contentView.addSubview(editBtn)
            }
        } else {
            let btnW: CGFloat = 60
            let btn = NSButton(frame: NSRect(x: width - pad - btnW, y: cardH - pad - 20, width: btnW, height: 24))
            btn.title = "启用"
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 12)
            btn.tag = index
            btn.target = self
            contentView.addSubview(btn)
            aiCardButtons[index] = btn

            if index == 0 {
                btn.action = #selector(switchToBasicMode(_:))
            } else if index == 1 {
                btn.action = #selector(expandSmartModeConfig(_:))
            } else if index == 2 {
                btn.action = #selector(expandAssistantModeConfig(_:))
            }
        }

        // 使用中的额外状态行
        if isActive && index == 1 {
            let provider = AIProvider(rawValue: SettingsManager.shared.aiProvider) ?? .claude
            let statusLabel = NSTextField(labelWithString: "● 当前使用：\(provider.displayName)")
            statusLabel.frame = NSRect(x: pad + radioSize + 10, y: 12, width: width - pad - 80, height: 14)
            statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            statusLabel.textColor = DT.success
            contentView.addSubview(statusLabel)
        } else if isActive && index == 2 {
            let statusLabel = NSTextField(labelWithString: "● 已连接")
            statusLabel.frame = NSRect(x: pad + radioSize + 10, y: 12, width: width - pad - 80, height: 14)
            statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            statusLabel.textColor = DT.success
            contentView.addSubview(statusLabel)
            aiCardStatusLabels[2] = statusLabel
        }

        return card
    }

    // MARK: - AI 能力 Tab 操作

    @objc func switchToBasicMode(_ sender: NSButton) {
        let oldMode = SettingsManager.shared.aiMode
        if oldMode == 0 { return }
        SettingsManager.shared.aiMode = 0
        onAIModeChanged?(oldMode, 0)
        rebuildAICapabilityPane()
    }

    @objc func expandSmartModeConfig(_ sender: NSButton) {
        NSLog("[Settings] expandSmartModeConfig called, window=%@", window != nil ? "yes" : "nil")
        showSmartModeConfigSheet()
    }

    @objc func expandAssistantModeConfig(_ sender: NSButton) {
        NSLog("[Settings] expandAssistantModeConfig called, window=%@, hasSheet=%@, windowVisible=%@",
              window != nil ? "yes" : "nil",
              window?.attachedSheet != nil ? "yes" : "no",
              window?.isVisible == true ? "yes" : "no")
        showAssistantModeConfigSheet()
    }

    @objc func expandAssistantModeConfigFromTag(_ sender: Any?) {
        NSLog("[Settings] expandAssistantModeConfigFromTag called")
        showAssistantModeConfigSheet()
    }

    /// 聪明模式配置弹窗
    private func showSmartModeConfigSheet() {
        guard let parentWindow = window else { return }

        let sheetW: CGFloat = 420
        let sheetH: CGFloat = 340
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "配置聪明模式"

        let root = NSView(frame: NSRect(x: 0, y: 0, width: sheetW, height: sheetH))
        let pad: CGFloat = 24
        let labelW: CGFloat = 80
        let controlX: CGFloat = pad + labelW + 12
        var y: CGFloat = sheetH - 36

        // AI 供应商
        let providerLabel = NSTextField(labelWithString: "AI 供应商")
        providerLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        providerLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        providerLabel.textColor = DT.textPrimary
        root.addSubview(providerLabel)

        let apPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 200, height: 26))
        for provider in AIProvider.allCases {
            apPopup.addItem(withTitle: provider.displayName)
        }
        apPopup.selectItem(at: SettingsManager.shared.aiProvider)
        root.addSubview(apPopup)
        self.aiProviderPopup = apPopup

        y -= 32

        // API Key
        let apiLabel = NSTextField(labelWithString: "API Key")
        apiLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        apiLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        apiLabel.textColor = DT.textPrimary
        root.addSubview(apiLabel)

        let currentProvider = AIProvider(rawValue: SettingsManager.shared.aiProvider) ?? .claude
        let keyField = NSSecureTextField(frame: NSRect(x: controlX, y: y - 2, width: sheetW - controlX - pad, height: 24))
        keyField.stringValue = SettingsManager.shared.apiKey ?? ""
        keyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        keyField.placeholderString = currentProvider.keyPlaceholder
        root.addSubview(keyField)
        self.apiKeyField = keyField

        y -= 36

        // 宠物性格
        let personalityLabel = NSTextField(labelWithString: "宠物性格")
        personalityLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        personalityLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        personalityLabel.textColor = DT.textPrimary
        root.addSubview(personalityLabel)

        let pPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 120, height: 26))
        for preset in PersonalityPreset.allCases {
            pPopup.addItem(withTitle: preset.displayName)
        }
        pPopup.selectItem(at: SettingsManager.shared.personalityPreset)
        pPopup.target = self
        pPopup.action = #selector(personalityChanged)
        root.addSubview(pPopup)
        self.personalityPopup = pPopup

        y -= 80

        let promptScroll = NSScrollView(frame: NSRect(x: controlX, y: y, width: sheetW - controlX - pad, height: 68))
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .bezelBorder
        let promptTV = NSTextView(frame: NSRect(x: 0, y: 0, width: sheetW - controlX - pad, height: 68))
        promptTV.isEditable = true
        promptTV.isSelectable = true
        promptTV.isRichText = false
        promptTV.font = NSFont.systemFont(ofSize: 12)
        promptTV.isAutomaticQuoteSubstitutionEnabled = false
        promptTV.isAutomaticDashSubstitutionEnabled = false
        promptTV.isAutomaticTextReplacementEnabled = false
        promptTV.textContainerInset = NSSize(width: 4, height: 4)
        promptTV.string = PersonalityPreset.currentPrompt()
        promptScroll.documentView = promptTV
        root.addSubview(promptScroll)
        self.personalityTextView = promptTV

        y -= 20

        // 测试结果
        let testResult = NSTextField(labelWithString: "")
        testResult.frame = NSRect(x: controlX, y: y, width: sheetW - controlX - pad, height: 18)
        testResult.font = NSFont.systemFont(ofSize: 11)
        testResult.textColor = DT.textSecondary
        testResult.lineBreakMode = .byTruncatingTail
        root.addSubview(testResult)
        self.aiTestResultLabel = testResult

        y -= 16

        // 底部按钮
        let cancelBtn = NSButton(frame: NSRect(x: sheetW - 240, y: 14, width: 80, height: 32))
        cancelBtn.title = "取消"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target = self
        cancelBtn.action = #selector(dismissConfigSheet)
        root.addSubview(cancelBtn)

        let isAlreadyActive = SettingsManager.shared.aiMode == 1
        let activateBtn = NSButton(frame: NSRect(x: sheetW - 150, y: 14, width: 130, height: 32))
        activateBtn.title = isAlreadyActive ? "保存设置" : "验证并启用"
        activateBtn.bezelStyle = .rounded
        activateBtn.keyEquivalent = "\r"
        activateBtn.target = self
        activateBtn.action = isAlreadyActive ? #selector(saveSmartModeConfig) : #selector(validateAndActivateSmartMode)
        root.addSubview(activateBtn)

        sheet.contentView = root
        parentWindow.beginSheet(sheet)
    }

    /// 保存聪明模式配置（已激活状态下修改）
    @objc func saveSmartModeConfig() {
        let key = apiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            aiTestResultLabel?.stringValue = "API Key 不能为空"
            aiTestResultLabel?.textColor = DT.warning
            return
        }

        SettingsManager.shared.aiProvider = aiProviderPopup?.indexOfSelectedItem ?? 0
        SettingsManager.shared.apiKey = key
        SettingsManager.shared.personalityPreset = personalityPopup?.indexOfSelectedItem ?? 0
        SettingsManager.shared.customPersonality = personalityTextView?.string ?? ""

        dismissConfigSheet()
        rebuildAICapabilityPane()
    }

    /// 保存助手模式配置（已激活状态下修改）
    @objc func saveAssistantModeConfig() {
        let hostValue = gatewayHostField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hostValue.isEmpty { SettingsManager.shared.gatewayHost = hostValue }
        if let portStr = gatewayPortField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
           let portVal = Int(portStr), portVal > 0 {
            SettingsManager.shared.gatewayPort = portVal
        }
        let tokenValue = openclawTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tokenValue.isEmpty { SettingsManager.shared.openclawToken = tokenValue }
        let userIdValue = dingtalkUserIdField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        SettingsManager.shared.dingtalkUserId = userIdValue

        dismissConfigSheet()
        rebuildAICapabilityPane()
    }

    @objc func dismissConfigSheet() {
        guard let parentWindow = window,
              let sheet = parentWindow.attachedSheet else { return }
        parentWindow.endSheet(sheet)
    }

    @objc func validateAndActivateSmartMode() {
        let key = apiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            aiTestResultLabel?.stringValue = "请先填入 API Key"
            aiTestResultLabel?.textColor = DT.warning
            return
        }

        let providerIdx = aiProviderPopup?.indexOfSelectedItem ?? 0
        let oldProvider = SettingsManager.shared.aiProvider
        let oldKey = SettingsManager.shared.apiKey
        SettingsManager.shared.aiProvider = providerIdx
        SettingsManager.shared.apiKey = key

        // 保存性格设置
        SettingsManager.shared.personalityPreset = personalityPopup?.indexOfSelectedItem ?? 0
        SettingsManager.shared.customPersonality = personalityTextView?.string ?? ""

        aiTestResultLabel?.stringValue = "验证中..."
        aiTestResultLabel?.textColor = DT.textSecondary

        AIEngine.shared.generate(prompt: "用一句话打个招呼，10字以内") { [weak self] result in
            DispatchQueue.main.async {
                if let text = result, !text.isEmpty {
                    let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}"))
                    self?.aiTestResultLabel?.stringValue = "验证成功！AI 说：\(cleaned)"
                    self?.aiTestResultLabel?.textColor = DT.success

                    // 切换模式
                    let oldMode = SettingsManager.shared.aiMode
                    SettingsManager.shared.aiMode = 1
                    self?.onAIModeChanged?(oldMode, 1)

                    // 关闭 sheet 并刷新卡片
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.dismissConfigSheet()
                        self?.rebuildAICapabilityPane()
                    }
                } else {
                    self?.aiTestResultLabel?.stringValue = "验证失败，请检查供应商和 API Key"
                    self?.aiTestResultLabel?.textColor = DT.error
                    // 还原
                    SettingsManager.shared.aiProvider = oldProvider
                    SettingsManager.shared.apiKey = oldKey
                }
            }
        }
    }

    /// 助手模式配置弹窗 —— 分步连接检查流程
    private func showAssistantModeConfigSheet() {
        guard let parentWindow = window else { return }

        let settings = SettingsManager.shared
        let hasToken = !settings.openclawToken.isEmpty
        let isAlreadyActive = settings.aiMode == 2

        // 已启用时直接弹设置弹窗（保存配置）
        if isAlreadyActive {
            showAssistantModeSettingsSheet()
            return
        }

        let sheetW: CGFloat = 440
        let sheetH: CGFloat = hasToken ? 330 : 370
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "启用助手模式"

        let root = NSView(frame: NSRect(x: 0, y: 0, width: sheetW, height: sheetH))
        let pad: CGFloat = 24
        var y: CGFloat = sheetH - 36

        // --- 顶部说明 ---
        let titleLabel = NSTextField(labelWithString: "连接 OpenClaw 以启用助手模式")
        titleLabel.frame = NSRect(x: pad, y: y, width: sheetW - pad * 2, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = DT.textPrimary
        root.addSubview(titleLabel)
        y -= 24

        let descLabel = NSTextField(wrappingLabelWithString: "启用前需要验证 OpenClaw 服务是否正常运行，点击下方按钮开始检查。")
        descLabel.frame = NSRect(x: pad, y: y - 16, width: sheetW - pad * 2, height: 30)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = DT.textSecondary
        root.addSubview(descLabel)
        y -= 46

        // --- 手动输入密钥（仅无配置时显示）---
        if !hasToken {
            let labelW: CGFloat = 70
            let controlX: CGFloat = pad + labelW + 8

            let tokenLabel = NSTextField(labelWithString: "连接密钥")
            tokenLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
            tokenLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            tokenLabel.textColor = DT.textPrimary
            root.addSubview(tokenLabel)

            let tokenField = NSTextField(frame: NSRect(x: controlX, y: y - 2, width: sheetW - controlX - pad, height: 24))
            tokenField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tokenField.placeholderString = "从 OpenClaw 配置中获取"
            root.addSubview(tokenField)
            self.openclawTokenField = tokenField
            y -= 36
        }

        // --- 分步检查区域 ---
        let stepsTitle = NSTextField(labelWithString: "连接检查")
        stepsTitle.frame = NSRect(x: pad, y: y, width: 200, height: 16)
        stepsTitle.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        stepsTitle.textColor = DT.textTertiary
        root.addSubview(stepsTitle)
        y -= 20

        // 四个步骤
        let stepTexts = [
            "检查 OpenClaw 配置",
            "连接 OpenClaw 服务",
            "验证服务认证",
            "测试 AI 服务"
        ]

        connectStepIcons = []
        connectStepLabels = []

        for (i, stepText) in stepTexts.enumerated() {
            let icon = NSTextField(labelWithString: "○")
            icon.frame = NSRect(x: pad, y: y, width: 22, height: 18)
            icon.font = NSFont.systemFont(ofSize: 13)
            icon.textColor = DT.textTertiary
            icon.alignment = .center
            root.addSubview(icon)
            connectStepIcons.append(icon)

            let label = NSTextField(wrappingLabelWithString: stepText)
            label.frame = NSRect(x: pad + 26, y: y, width: sheetW - pad * 2 - 26, height: 18)
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = DT.textSecondary
            label.maximumNumberOfLines = 3
            root.addSubview(label)
            connectStepLabels.append(label)

            y -= (i < stepTexts.count - 1) ? 28 : 0
        }

        // --- 底部按钮 ---
        let cancelBtn = NSButton(frame: NSRect(x: sheetW - 280, y: 14, width: 80, height: 32))
        cancelBtn.title = "取消"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelAssistantConnect)
        root.addSubview(cancelBtn)

        let startBtn = NSButton(frame: NSRect(x: sheetW - 190, y: 14, width: 170, height: 32))
        startBtn.title = "开始连接 OpenClaw"
        startBtn.bezelStyle = .rounded
        startBtn.keyEquivalent = "\r"
        startBtn.target = self
        startBtn.action = #selector(startAssistantConnectionCheck)
        root.addSubview(startBtn)
        self.connectStartBtn = startBtn

        sheet.contentView = root
        parentWindow.beginSheet(sheet)
    }

    /// 已启用助手模式时的设置弹窗（保存配置用）
    private func showAssistantModeSettingsSheet() {
        guard let parentWindow = window else { return }
        let sheetW: CGFloat = 420
        let sheetH: CGFloat = 140
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "助手模式设置"

        let root = NSView(frame: NSRect(x: 0, y: 0, width: sheetW, height: sheetH))
        let pad: CGFloat = 24

        let settings = SettingsManager.shared
        let addrText = "\(settings.gatewayHost):\(settings.gatewayPort)"
        let infoLabel = NSTextField(labelWithString: "当前连接地址：\(addrText)")
        infoLabel.frame = NSRect(x: pad, y: sheetH - 50, width: sheetW - pad * 2, height: 18)
        infoLabel.font = NSFont.systemFont(ofSize: 13)
        infoLabel.textColor = DT.textPrimary
        root.addSubview(infoLabel)

        let statusLabel = NSTextField(labelWithString: "✓ 助手模式已启用")
        statusLabel.frame = NSRect(x: pad, y: sheetH - 74, width: sheetW - pad * 2, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = DT.success
        root.addSubview(statusLabel)

        let closeBtn = NSButton(frame: NSRect(x: sheetW - 100, y: 14, width: 80, height: 32))
        closeBtn.title = "关闭"
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.target = self
        closeBtn.action = #selector(dismissConfigSheet)
        root.addSubview(closeBtn)

        sheet.contentView = root
        parentWindow.beginSheet(sheet)
    }

    @objc func cancelAssistantConnect() {
        // 取消时清理临时 gateway
        testGateway?.disconnect()
        testGateway = nil
        dismissConfigSheet()
    }

    /// 开始分步连接检查
    @objc func startAssistantConnectionCheck() {
        // 保存手动输入的 token（如有）
        let tokenValue = openclawTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tokenValue.isEmpty { SettingsManager.shared.openclawToken = tokenValue }

        // 禁用按钮防重复点击
        connectStartBtn?.isEnabled = false
        connectStartBtn?.title = "检查中..."

        // ===== Step 1: 检查配置 =====
        updateStep(0, state: .checking)

        let settings = SettingsManager.shared
        let token = settings.openclawToken

        guard !token.isEmpty else {
            updateStep(0, state: .failed, detail: "未找到连接密钥，请填写或安装 OpenClaw")
            resetConnectButton()
            return
        }

        let host = settings.gatewayHost
        let port = settings.gatewayPort

        updateStep(0, state: .success, detail: "配置就绪 · \(host):\(port)")

        // ===== Step 2: 连接服务 =====
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.runConnectionStep(host: host, port: port, token: token)
        }
    }

    private func runConnectionStep(host: String, port: Int, token: String) {
        updateStep(1, state: .checking)

        // 创建临时 gateway 做验证连接
        let gw = OpenClawGateway(host: host, port: port, token: token)
        self.testGateway = gw

        var finished = false  // 防止多次回调

        // Step 2 完成：收到 challenge = WebSocket 物理连接成功
        gw.onChallengeReceived = { [weak self] in
            guard !finished else { return }
            self?.updateStep(1, state: .success, detail: "\(host):\(port) 已连通")
            // 进入 Step 3：等待握手认证结果
            self?.updateStep(2, state: .checking)
        }

        // Step 3 成功：hello-ok 握手认证通过 → 进入 Step 4 测试 AI
        gw.onConnectionChange = { [weak self] connected in
            guard !finished else { return }
            if connected {
                finished = true
                self?.updateStep(2, state: .success, detail: "认证通过")
                // 进入 Step 4：发测试消息验证 AI 服务
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.runAITestStep()
                }
            }
        }

        // Step 3 失败：服务返回了错误信息（认证失败等）
        gw.onConnectRejected = { [weak self] errorMsg in
            guard !finished else { return }
            finished = true
            self?.updateStep(2, state: .failed, detail: errorMsg)
            self?.testGateway?.disconnect()
            self?.testGateway = nil
            self?.resetConnectButton()
        }

        gw.connect()

        // 8 秒超时（仅覆盖 Step 2-3，Step 4 有自己的超时）
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard !finished else { return }
            finished = true
            // 判断超时发生在哪个阶段
            let step2Icon = self?.connectStepIcons.count ?? 0 > 1 ? self?.connectStepIcons[1].stringValue : nil
            if step2Icon != "✓" {
                self?.updateStep(1, state: .failed, detail: "连接超时，请确认 OpenClaw 正在运行")
            } else {
                self?.updateStep(2, state: .failed, detail: "握手超时，服务未响应")
            }
            self?.testGateway?.disconnect()
            self?.testGateway = nil
            self?.resetConnectButton()
        }
    }

    /// Step 4: 发测试消息验证 AI 服务是否真正可用
    private func runAITestStep() {
        guard let gw = testGateway else { return }
        updateStep(3, state: .checking)

        var testFinished = false

        // 监听 AI 回复：收到任何 chat event 说明 LLM 在工作
        gw.onMessage = { [weak self] event in
            guard !testFinished else { return }
            if event.state == "error" {
                // LLM 返回错误（欠费、模型不可用等）
                testFinished = true
                let errDetail = event.errorMessage ?? event.message ?? "AI 服务返回错误"
                self?.updateStep(3, state: .failed, detail: errDetail)
                self?.testGateway?.disconnect()
                self?.testGateway = nil
                self?.resetConnectButton()
            } else if event.state == "delta" || event.state == "final" {
                // 收到正常回复，AI 可用
                testFinished = true
                self?.updateStep(3, state: .success, detail: "AI 服务正常")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.activateAssistantModeAfterCheck()
                }
            }
        }

        // 发送测试消息
        let testSessionKey = "test:connectivity:\(UUID().uuidString.prefix(8))"
        gw.send(sessionKey: testSessionKey, message: "ping") { [weak self] ok, errorMsg in
            guard !testFinished else { return }
            if !ok {
                // 发送请求本身就失败了
                testFinished = true
                let detail = errorMsg ?? "发送测试消息失败"
                self?.updateStep(3, state: .failed, detail: detail)
                self?.testGateway?.disconnect()
                self?.testGateway = nil
                self?.resetConnectButton()
            }
            // ok == true 只表示请求被接受，继续等 chat event 回复
        }

        // 15 秒超时（LLM 生成可能比较慢）
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard !testFinished else { return }
            testFinished = true
            self?.updateStep(3, state: .failed, detail: "AI 响应超时")
            self?.testGateway?.disconnect()
            self?.testGateway = nil
            self?.resetConnectButton()
        }
    }

    /// 全部四步通过，正式启用助手模式
    private func activateAssistantModeAfterCheck() {
        // 断开测试连接
        testGateway?.disconnect()
        testGateway = nil

        // 切换模式（触发正式连接）
        let oldMode = SettingsManager.shared.aiMode
        SettingsManager.shared.aiMode = 2
        onAIModeChanged?(oldMode, 2)

        // 关闭弹窗，刷新卡片
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.dismissConfigSheet()
            self?.rebuildAICapabilityPane()
        }
    }

    // MARK: - 步骤 UI 更新

    private enum StepState {
        case idle, checking, success, failed
    }

    private func updateStep(_ index: Int, state: StepState, detail: String? = nil) {
        guard index < connectStepIcons.count, index < connectStepLabels.count else { return }

        let icon = connectStepIcons[index]
        let label = connectStepLabels[index]

        let stepNames = ["检查 OpenClaw 配置", "连接 OpenClaw 服务", "验证服务认证", "测试 AI 服务"]
        let baseName = stepNames[index]

        switch state {
        case .idle:
            icon.stringValue = "○"
            icon.textColor = DT.textTertiary
            label.stringValue = baseName
            label.textColor = DT.textSecondary
        case .checking:
            icon.stringValue = "◌"
            icon.textColor = DT.secondary
            label.stringValue = baseName + " ..."
            label.textColor = DT.textPrimary
        case .success:
            icon.stringValue = "✓"
            icon.textColor = DT.success
            if let detail = detail {
                label.stringValue = baseName + " — " + detail
            } else {
                label.stringValue = baseName
            }
            label.textColor = DT.success
        case .failed:
            icon.stringValue = "✗"
            icon.textColor = DT.error
            if let detail = detail {
                label.stringValue = baseName + "\n" + detail
            } else {
                label.stringValue = baseName + " — 失败"
            }
            label.textColor = DT.error
            // 扩高以显示换行内容
            let labelW = label.frame.width
            let fittingH = label.sizeThatFits(NSSize(width: labelW, height: CGFloat.greatestFiniteMagnitude)).height
            if fittingH > label.frame.height {
                let dy = fittingH - label.frame.height
                label.frame = NSRect(x: label.frame.origin.x, y: label.frame.origin.y - dy,
                                     width: labelW, height: fittingH)
                icon.frame.origin.y = label.frame.origin.y + fittingH - 18
            }
        }
    }

    private func resetConnectButton() {
        connectStartBtn?.isEnabled = true
        connectStartBtn?.title = "重新检查"
    }

    /// 重建 AI 能力 Tab 内容
    private func rebuildAICapabilityPane() {
        guard let container = contentContainer else { return }
        let width = container.frame.width
        let height = container.frame.height

        // 找到并替换 AI 能力 pane (index 1)
        if panes.count > 1 {
            let oldPane = panes[1]
            let newPane = buildAICapabilityPane(width: width, height: height)
            newPane.isHidden = oldPane.isHidden
            newPane.frame = oldPane.frame
            container.replaceSubview(oldPane, with: newPane)
            panes[1] = newPane
        }
    }

    // MARK: - 高级

    private func buildAdvancedPane(width: CGFloat, height: CGFloat) -> NSView {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 28
        let labelW: CGFloat = 90
        let controlX: CGFloat = pad + labelW + 12
        var y: CGFloat = height

        addPageTitle("高级", to: pane, at: &y, pad: pad)

        // ── 行为 ──
        addSectionTitle("行为", to: pane, at: &y, pad: pad, width: width)

        // 工作状态检测
        let modeLabel = NSTextField(labelWithString: "监控模式")
        modeLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.textColor = DT.textPrimary
        pane.addSubview(modeLabel)

        let popup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 3, width: 200, height: 26))
        popup.addItems(withTitles: ["键鼠输入检测", "Claude 进程监控"])
        popup.selectItem(at: SettingsManager.shared.monitorMode)
        pane.addSubview(popup)
        self.modePopup = popup

        y -= 20

        let modeHint = NSTextField(labelWithString: "键鼠输入：持续输入2秒触发 | Claude：检测进程CPU占用")
        modeHint.frame = NSRect(x: controlX, y: y, width: width - controlX - pad, height: 16)
        modeHint.font = NSFont.systemFont(ofSize: 10)
        modeHint.textColor = DT.textTertiary
        pane.addSubview(modeHint)

        y -= 34

        // ── 终端 ──
        addSectionTitle("终端", to: pane, at: &y, pad: pad, width: width)

        // 终端命令
        let cmdLabel = NSTextField(labelWithString: "终端命令")
        cmdLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        cmdLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cmdLabel.textColor = DT.textPrimary
        pane.addSubview(cmdLabel)

        let cmdDesc = NSTextField(labelWithString: "双击执行的终端命令")
        cmdDesc.frame = NSRect(x: controlX, y: y, width: 200, height: 18)
        cmdDesc.font = NSFont.systemFont(ofSize: 12)
        cmdDesc.textColor = DT.textSecondary
        pane.addSubview(cmdDesc)

        y -= 118

        let cmdScroll = NSScrollView(frame: NSRect(x: controlX, y: y, width: width - controlX - pad, height: 110))
        cmdScroll.hasVerticalScroller = true
        cmdScroll.borderType = .bezelBorder

        let cmdTV = NSTextView(frame: NSRect(x: 0, y: 0, width: width - controlX - pad, height: 110))
        cmdTV.isEditable = true
        cmdTV.isSelectable = true
        cmdTV.isRichText = false
        cmdTV.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cmdTV.isAutomaticQuoteSubstitutionEnabled = false
        cmdTV.isAutomaticDashSubstitutionEnabled = false
        cmdTV.isAutomaticTextReplacementEnabled = false
        cmdTV.string = SettingsManager.shared.terminalCommand
        cmdTV.textContainerInset = NSSize(width: 4, height: 4)
        cmdScroll.documentView = cmdTV
        pane.addSubview(cmdScroll)
        self.commandTextView = cmdTV

        y -= 20

        let hint = NSTextField(labelWithString: "示例: cd ~/projects && export HTTPS_PROXY=http://127.0.0.1:7897 && claude")
        hint.frame = NSRect(x: controlX, y: y, width: width - controlX - pad, height: 18)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = DT.textTertiary
        pane.addSubview(hint)

        y -= 36

        // ── 钉钉 ──
        let dtSep = NSBox(frame: NSRect(x: pad, y: y + 8, width: width - pad * 2, height: 1))
        dtSep.boxType = .separator
        pane.addSubview(dtSep)

        addSectionTitle("钉钉集成", to: pane, at: &y, pad: pad, width: width)

        let userIdLabel = NSTextField(labelWithString: "钉钉 UserId")
        userIdLabel.frame = NSRect(x: pad, y: y, width: labelW, height: 20)
        userIdLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        userIdLabel.textColor = DT.textPrimary
        pane.addSubview(userIdLabel)

        let userIdField = NSTextField(frame: NSRect(x: controlX, y: y - 2, width: width - controlX - pad, height: 24))
        userIdField.stringValue = SettingsManager.shared.dingtalkUserId
        userIdField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        userIdField.placeholderString = "可选，用于区分「我的私聊」和「别人私聊」"
        pane.addSubview(userIdField)
        self.dingtalkUserIdField = userIdField

        return pane
    }

    // MARK: - Actions

    func updatePreview() {
        let idx = petModePopup?.indexOfSelectedItem ?? 0
        if idx == 0 {
            if let path = PetConfig.getResourcePath() {
                previewImageView?.image = NSImage(contentsOfFile: path + "/idle_0.png")
            }
        } else if SettingsManager.shared.hasCustomImage(slot: idx) {
            let path = SettingsManager.shared.customImagePath(slot: idx)
            previewImageView?.image = NSImage(contentsOfFile: path)
        } else {
            previewImageView?.image = nil
        }
    }

    @objc func aiProviderChanged() {
        let idx = aiProviderPopup?.indexOfSelectedItem ?? 0
        let provider = AIProvider(rawValue: idx) ?? .claude
        apiKeyField?.placeholderString = provider.keyPlaceholder
    }

    @objc func personalityChanged() {
        let idx = personalityPopup?.indexOfSelectedItem ?? 0
        let preset = PersonalityPreset(rawValue: idx) ?? .introvert
        if preset != .custom {
            personalityTextView?.string = preset.prompt
        } else {
            personalityTextView?.string = ""
        }
    }

    @objc func petModeSelectionChanged() {
        let idx = petModePopup?.indexOfSelectedItem ?? 0
        let isCustom = idx >= 1
        pickImageButton?.isEnabled = isCustom
        if isCustom {
            let hasImg = SettingsManager.shared.hasCustomImage(slot: idx)
            imageStatusLabel?.stringValue = hasImg ? "✓ 已选择" : ""
            imageStatusLabel?.textColor = hasImg ? DT.success : DT.textTertiary
            deleteImageButton?.isEnabled = hasImg
        } else {
            imageStatusLabel?.stringValue = ""
            deleteImageButton?.isEnabled = false
        }
        updatePreview()
    }

    @objc func pickImage() {
        let slot = petModePopup?.indexOfSelectedItem ?? 1
        guard slot >= 1 else { return }

        let panel = NSOpenPanel()
        panel.title = "选择宠物图片（槽位 \(slot)）"
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .floating

        if panel.runModal() == .OK, let url = panel.url {
            let destPath = SettingsManager.shared.customImagePath(slot: slot)
            let success = BackgroundRemover.processAndSave(from: url.path, to: destPath)
            if success {
                imageStatusLabel?.stringValue = "✓ 已选择"
                imageStatusLabel?.textColor = DT.success
                deleteImageButton?.isEnabled = true
            } else {
                try? FileManager.default.removeItem(atPath: destPath)
                do {
                    try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destPath))
                    imageStatusLabel?.stringValue = "✓ 已选择"
                    imageStatusLabel?.textColor = DT.success
                    deleteImageButton?.isEnabled = true
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "图片导入失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
        updatePreview()
    }

    @objc func deleteImage() {
        let slot = petModePopup?.indexOfSelectedItem ?? 1
        guard slot >= 1 else { return }
        let path = SettingsManager.shared.customImagePath(slot: slot)
        try? FileManager.default.removeItem(atPath: path)
        imageStatusLabel?.stringValue = ""
        deleteImageButton?.isEnabled = false
        updatePreview()
        if SettingsManager.shared.petMode == slot {
            SettingsManager.shared.petMode = 0
            petModePopup?.selectItem(at: 0)
            pickImageButton?.isEnabled = false
            onPetModeChanged?(0)
            updatePreview()
        }
    }

    // dingtalkToggled and updateDingTalkStatus removed - AI mode switching handled by AI能力 tab cards

    @objc func testOpenClawConnection() {
        guard let testFn = onTestOpenClaw else {
            chatTestResultLabel?.stringValue = "未启用 OpenClaw 连接"
            chatTestResultLabel?.textColor = DT.warning
            return
        }

        chatTestResultLabel?.stringValue = "测试中..."
        chatTestResultLabel?.textColor = DT.textSecondary

        testFn { [weak self] success, errorMsg in
            DispatchQueue.main.async {
                if success {
                    self?.chatTestResultLabel?.stringValue = "✓ 连接正常，大模型响应成功"
                    self?.chatTestResultLabel?.textColor = DT.success
                } else {
                    let msg = errorMsg ?? "未知错误"
                    self?.chatTestResultLabel?.stringValue = "✗ \(msg)"
                    self?.chatTestResultLabel?.textColor = DT.error
                }
            }
        }
    }

    @objc func openQuotesFile() {
        let path = SettingsManager.shared.appSupportDir + "/quotes.txt"
        _ = WorkerQuotes.shared
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func saveSettings() {
        guard let command = commandTextView?.string, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        SettingsManager.shared.terminalCommand = command

        let name = petNameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "皮皮"
        SettingsManager.shared.petName = name.isEmpty ? "皮皮" : name

        // 说话方式
        let newSpeechMode = speechModePopup?.indexOfSelectedItem ?? 0
        if newSpeechMode == 1 && SettingsManager.shared.aiMode == 0 {
            let alert = NSAlert()
            alert.messageText = "需要先启用 AI 能力"
            alert.informativeText = "使用 AI 生成碎碎念前，请先在「AI 能力」中启用聪明模式或助手模式。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "前往设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                sidebarTableView?.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
                switchTab(to: 1)
            }
            return
        }
        SettingsManager.shared.speechMode = newSpeechMode

        let newMode = modePopup?.indexOfSelectedItem ?? 0
        let oldMode = SettingsManager.shared.monitorMode
        SettingsManager.shared.monitorMode = newMode
        if newMode != oldMode {
            onMonitorModeChanged?(newMode)
        }

        SettingsManager.shared.activityRange = rangePopup?.indexOfSelectedItem ?? 0
        SettingsManager.shared.workingEffect = workingEffectPopup?.indexOfSelectedItem ?? 0

        let newSizeIdx = sizePopup?.indexOfSelectedItem ?? 0
        let oldSizeIdx = SettingsManager.shared.petSizeIndex
        SettingsManager.shared.petSizeIndex = newSizeIdx
        if newSizeIdx != oldSizeIdx {
            onPetSizeChanged?()
        }

        // 钉钉 UserId（高级 tab）
        let userIdValue = dingtalkUserIdField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        SettingsManager.shared.dingtalkUserId = userIdValue

        let newPetMode = petModePopup?.indexOfSelectedItem ?? 0
        let oldPetMode = SettingsManager.shared.petMode
        if newPetMode >= 1 && !SettingsManager.shared.hasCustomImage(slot: newPetMode) {
            let alert = NSAlert()
            alert.messageText = "请先选择图片"
            alert.informativeText = "使用自定义形象 \(newPetMode) 前，请点击「选择图片...」按钮上传一张图片。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        SettingsManager.shared.petMode = newPetMode
        if newPetMode != oldPetMode {
            onPetModeChanged?(newPetMode)
        }

        window?.close()
    }

    @objc func resetSettings() {
        commandTextView?.string = "cd ~"
        SettingsManager.shared.terminalCommand = "cd ~"
        modePopup?.selectItem(at: 0)
        SettingsManager.shared.monitorMode = 0
        rangePopup?.selectItem(at: 0)
        SettingsManager.shared.activityRange = 0
        sizePopup?.selectItem(at: 0)
        SettingsManager.shared.petSizeIndex = 0
        workingEffectPopup?.selectItem(at: 0)
        SettingsManager.shared.workingEffect = 0
        petModePopup?.selectItem(at: 0)
        SettingsManager.shared.petMode = 0
        pickImageButton?.isEnabled = false
        petNameField?.stringValue = "皮皮"
        speechModePopup?.selectItem(at: 0)
        SettingsManager.shared.speechMode = 0
        updateAIStatusLabel()
        // 重置 AI 模式
        let oldMode = SettingsManager.shared.aiMode
        if oldMode != 0 {
            SettingsManager.shared.aiMode = 0
            onAIModeChanged?(oldMode, 0)
        }
        SettingsManager.shared.dingtalkUserId = ""
        rebuildAICapabilityPane()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.window.orderFrontRegardless()
        }
    }
}

// MARK: - 自定义侧边栏行视图（暖色选中态）
class WarmSidebarRowView: NSTableRowView {
    private lazy var selectionLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = DT.radiusMd
        layer.backgroundColor = DT.bgSurface.cgColor
        layer.borderWidth = 0.5
        layer.borderColor = NSColor(white: 0, alpha: 0.04).cgColor
        return layer
    }()

    override func layout() {
        super.layout()
        applySelectionStyle()
    }

    override func drawSelection(in dirtyRect: NSRect) {}

    override var isSelected: Bool {
        didSet { applySelectionStyle() }
    }

    private func applySelectionStyle() {
        wantsLayer = true
        if isSelected {
            if selectionLayer.superlayer == nil {
                layer?.insertSublayer(selectionLayer, at: 0)
            }
            selectionLayer.frame = bounds.insetBy(dx: 8, dy: 1)
        } else {
            selectionLayer.removeFromSuperlayer()
        }

        if let cellView = subviews.first as? NSTableCellView {
            cellView.textField?.textColor = isSelected ? DT.primary : DT.textSecondary
            cellView.textField?.font = isSelected
                ? NSFont.systemFont(ofSize: 13, weight: .semibold)
                : NSFont.systemFont(ofSize: 13, weight: .medium)
            if let iconView = cellView.viewWithTag(100) as? NSImageView {
                iconView.contentTintColor = isSelected ? DT.primary : DT.textSecondary
            }
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
