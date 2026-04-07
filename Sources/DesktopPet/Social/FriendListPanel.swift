import AppKit

// MARK: - 好友面板
class FriendListPanel: NSWindowController {
    private var friendRows: [NSView] = []
    private var listContainer: NSView!
    private var addCodeField: NSTextField!
    private var emptyLabel: NSTextField?
    private var refreshTimer: Timer?
    private var listTopY: CGFloat = 0

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "好友"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    func showPanel() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshFriendList()
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshFriendList()
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let pad: CGFloat = 24
        var y: CGFloat = h - 28

        // ── 我的配对码 ──
        let codeTitle = NSTextField(labelWithString: "我的配对码")
        codeTitle.frame = NSRect(x: pad, y: y, width: 100, height: 14)
        codeTitle.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        codeTitle.textColor = DT.textTertiary
        contentView.addSubview(codeTitle)

        y -= 34

        let myCode = SocialManager.shared.myCode.isEmpty
            ? SettingsManager.shared.socialCode
            : SocialManager.shared.myCode

        // 配对码卡片
        let codeCard = NSView(frame: NSRect(x: pad, y: y, width: w - pad * 2, height: 40))
        codeCard.wantsLayer = true
        codeCard.layer?.cornerRadius = DT.radiusMd
        codeCard.layer?.backgroundColor = DT.bgMuted.cgColor
        contentView.addSubview(codeCard)

        let codeLabel = NSTextField(labelWithString: myCode)
        codeLabel.frame = NSRect(x: 14, y: 6, width: 160, height: 28)
        codeLabel.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        codeLabel.textColor = DT.textPrimary
        codeLabel.isSelectable = true
        codeCard.addSubview(codeLabel)

        let copyBtn = NSButton(frame: NSRect(x: codeCard.frame.width - 62, y: 8, width: 50, height: 24))
        copyBtn.title = "复制"
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .small
        copyBtn.font = NSFont.systemFont(ofSize: 11)
        copyBtn.target = self
        copyBtn.action = #selector(copyCode)
        codeCard.addSubview(copyBtn)

        y -= 20

        let sep1 = NSBox(frame: NSRect(x: pad, y: y, width: w - pad * 2, height: 1))
        sep1.boxType = .separator
        contentView.addSubview(sep1)

        y -= 22

        // ── 添加好友 ──
        let addTitle = NSTextField(labelWithString: "添加好友")
        addTitle.frame = NSRect(x: pad, y: y, width: 80, height: 14)
        addTitle.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        addTitle.textColor = DT.textTertiary
        contentView.addSubview(addTitle)

        y -= 30

        // 输入行
        let inputRow = NSView(frame: NSRect(x: pad, y: y, width: w - pad * 2, height: 30))
        contentView.addSubview(inputRow)

        let fieldW = inputRow.frame.width - 58
        let field = NSTextField(frame: NSRect(x: 0, y: 1, width: fieldW, height: 28))
        field.placeholderString = "输入对方配对码"
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.wantsLayer = true
        field.focusRingType = .none
        inputRow.addSubview(field)
        self.addCodeField = field

        let addBtn = NSButton(frame: NSRect(x: fieldW + 8, y: 0, width: 50, height: 28))
        addBtn.title = "添加"
        addBtn.bezelStyle = .rounded
        addBtn.controlSize = .small
        addBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        addBtn.target = self
        addBtn.action = #selector(addFriend)
        inputRow.addSubview(addBtn)

        y -= 16

        let sep2 = NSBox(frame: NSRect(x: pad, y: y, width: w - pad * 2, height: 1))
        sep2.boxType = .separator
        contentView.addSubview(sep2)

        y -= 22

        // ── 好友列表 ──
        let listTitle = NSTextField(labelWithString: "好友列表")
        listTitle.frame = NSRect(x: pad, y: y, width: 80, height: 14)
        listTitle.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        listTitle.textColor = DT.textTertiary
        contentView.addSubview(listTitle)

        y -= 8
        listTopY = y

        // 好友列表区域（scrollable）
        let listScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: y))
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.drawsBackground = false
        contentView.addSubview(listScroll)

        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: y))
        listScroll.documentView = container
        self.listContainer = container

        refreshFriendList()

        SocialManager.shared.onFriendListChanged = { [weak self] in
            self?.refreshFriendList()
        }
    }

    func refreshFriendList() {
        guard let container = listContainer else { return }
        let w = container.bounds.width
        let pad: CGFloat = 24

        // 清除旧行
        for row in friendRows { row.removeFromSuperview() }
        friendRows.removeAll()
        emptyLabel?.removeFromSuperview()
        emptyLabel = nil

        let friends = SettingsManager.shared.friendList

        if friends.isEmpty {
            let empty = NSTextField(labelWithString: "还没有好友，输入配对码添加吧~")
            empty.frame = NSRect(x: pad, y: 12, width: w - pad * 2, height: 18)
            empty.font = NSFont.systemFont(ofSize: 12)
            empty.textColor = DT.textTertiary
            container.addSubview(empty)
            self.emptyLabel = empty
            container.frame = NSRect(x: 0, y: 0, width: w, height: 42)
            return
        }

        var y: CGFloat = 8
        let rowH: CGFloat = 44

        for (code, name) in friends.sorted(by: { $0.key < $1.key }) {
            let row = NSView(frame: NSRect(x: pad, y: y, width: w - pad * 2, height: rowH))
            row.wantsLayer = true
            row.layer?.cornerRadius = DT.radiusSm
            row.layer?.backgroundColor = DT.bgMuted.cgColor

            let isOnline = SocialManager.shared.isFriendOnline(code)

            // 在线圆点
            let dot = NSView(frame: NSRect(x: 12, y: (rowH - 8) / 2, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = (isOnline ? DT.success : DT.textTertiary).cgColor
            row.addSubview(dot)

            // 名字
            let displayName = name == code ? code : name
            let nameLabel = NSTextField(labelWithString: displayName)
            nameLabel.frame = NSRect(x: 28, y: rowH / 2, width: 100, height: 18)
            nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            nameLabel.textColor = DT.textPrimary
            nameLabel.lineBreakMode = .byTruncatingTail
            row.addSubview(nameLabel)

            // 配对码
            let codeLabel = NSTextField(labelWithString: code)
            codeLabel.frame = NSRect(x: 28, y: rowH / 2 - 16, width: 80, height: 14)
            codeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            codeLabel.textColor = DT.textTertiary
            row.addSubview(codeLabel)

            let rowW = row.frame.width

            // 串门
            let visitBtn = NSButton(frame: NSRect(x: rowW - 78, y: (rowH - 24) / 2, width: 44, height: 24))
            visitBtn.title = "串门"
            visitBtn.bezelStyle = .rounded
            visitBtn.controlSize = .mini
            visitBtn.font = NSFont.systemFont(ofSize: 11)
            visitBtn.target = self
            visitBtn.action = #selector(visitFriend(_:))
            visitBtn.identifier = NSUserInterfaceItemIdentifier(code)
            visitBtn.isEnabled = isOnline && SocialManager.shared.state == .idle
            row.addSubview(visitBtn)

            // 删除
            let delBtn = NSButton(frame: NSRect(x: rowW - 28, y: (rowH - 24) / 2, width: 24, height: 24))
            delBtn.title = "×"
            delBtn.bezelStyle = .rounded
            delBtn.controlSize = .mini
            delBtn.font = NSFont.systemFont(ofSize: 12)
            delBtn.target = self
            delBtn.action = #selector(deleteFriend(_:))
            delBtn.identifier = NSUserInterfaceItemIdentifier(code)
            row.addSubview(delBtn)

            container.addSubview(row)
            friendRows.append(row)

            y += rowH + 6
        }

        container.frame = NSRect(x: 0, y: 0, width: w, height: max(y + 4, listTopY))
    }

    // MARK: - Actions

    @objc private func copyCode() {
        let code = SocialManager.shared.myCode.isEmpty
            ? SettingsManager.shared.socialCode
            : SocialManager.shared.myCode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        let alert = NSAlert()
        alert.messageText = "已复制"
        alert.informativeText = "配对码已复制到剪贴板"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if let win = window {
            alert.beginSheetModal(for: win)
        }
    }

    @objc private func addFriend() {
        let code = addCodeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        guard code.count >= 4 else {
            showError("配对码太短了")
            return
        }
        guard code != SettingsManager.shared.socialCode else {
            showError("不能添加自己哦")
            return
        }
        guard !SettingsManager.shared.isFriend(code) else {
            showError("已经是好友了")
            return
        }

        SocialManager.shared.addFriend(code: code)
        addCodeField.stringValue = ""
        refreshFriendList()
    }

    @objc private func visitFriend(_ sender: NSButton) {
        guard let code = sender.identifier?.rawValue else { return }
        SocialManager.shared.requestVisit(to: code)
        window?.orderOut(nil)
    }

    @objc private func deleteFriend(_ sender: NSButton) {
        guard let code = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "删除好友"
        alert.informativeText = "确定要删除好友 \(code) 吗？"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning

        if let win = window {
            alert.beginSheetModal(for: win) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    SocialManager.shared.removeFriend(code: code)
                    self?.refreshFriendList()
                }
            }
        }
    }

    private func showError(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if let win = window {
            alert.beginSheetModal(for: win)
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

// 翻转坐标系，内容从顶部开始排列
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
