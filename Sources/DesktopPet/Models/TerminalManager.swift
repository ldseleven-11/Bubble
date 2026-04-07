import AppKit

// MARK: - 终端窗口信息
struct TerminalWindowInfo {
    let id: Int
    let name: String
    let index: Int
}

// MARK: - 终端管理器
class TerminalManager {
    static let shared = TerminalManager()

    // 获取所有终端窗口
    func getTerminalWindows() -> [TerminalWindowInfo] {
        var windows: [TerminalWindowInfo] = []

        let script = """
        tell application "Terminal"
            set windowList to {}
            repeat with i from 1 to count of windows
                set w to window i
                set windowName to name of w
                set windowId to id of w
                set end of windowList to {windowId, windowName, i}
            end repeat
            return windowList
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)

            if error == nil, result.numberOfItems > 0 {
                for i in 1...result.numberOfItems {
                    if let item = result.atIndex(i) {
                        let windowId = item.atIndex(1)?.int32Value ?? 0
                        let windowName = item.atIndex(2)?.stringValue ?? "Terminal"
                        let windowIndex = item.atIndex(3)?.int32Value ?? 0
                        windows.append(TerminalWindowInfo(
                            id: Int(windowId),
                            name: windowName,
                            index: Int(windowIndex)
                        ))
                    }
                }
            }
        }

        return windows
    }

    // 激活指定终端窗口
    func activateWindow(index: Int) {
        let script = """
        tell application "Terminal"
            activate
            set index of window \(index) to 1
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // 新建终端窗口并执行用户自定义命令
    func newWindow() {
        let commands = SettingsManager.shared.terminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if commands.isEmpty {
            // 命令为空，只打开终端
            let script = """
            tell application "Terminal"
                do script ""
                activate
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            return
        }

        let escapedCommands = commands.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            do script "\(escapedCommands)"
            activate
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                NSLog("[DesktopPet] 终端命令执行失败: %@", error)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "终端命令执行失败"
                    alert.informativeText = "无法打开终端执行命令。请检查终端应用是否可用。\n\n错误: \(error["NSAppleScriptErrorMessage"] ?? "未知错误")"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }
}
