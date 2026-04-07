import AppKit

// MARK: - 配置
struct PetConfig {
    static var size: CGFloat { SettingsManager.shared.petSize }
    static var workingSize: CGFloat { SettingsManager.shared.petSize * 1.75 }
    static let animationFPS: Double = 8  // 动画帧率
    static let walkSpeed: CGFloat = 1.0

    // 图片目录路径（可自定义）
    static var customImagePath: String? = nil

    // 获取资源目录
    static func getResourcePath() -> String? {
        if let custom = customImagePath {
            print("使用自定义路径: \(custom)")
            return custom
        }

        // 尝试从 .app bundle 的 Resources 目录获取
        if let mainResourcePath = Bundle.main.resourcePath {
            // 检查 app bundle 中的 SPM 资源 bundle
            let spmBundlePath = mainResourcePath + "/DesktopPet_DesktopPet.bundle/Resources"
            if FileManager.default.fileExists(atPath: spmBundlePath) {
                print("使用 App Bundle SPM 资源路径: \(spmBundlePath)")
                return spmBundlePath
            }
            // 直接在 Resources 目录中查找
            let directPath = mainResourcePath
            let testFile = directPath + "/idle_0.png"
            if FileManager.default.fileExists(atPath: testFile) {
                print("使用 App Bundle 资源路径: \(directPath)")
                return directPath
            }
        }

        // 尝试从 SPM Bundle.module 获取（开发时）
        if let bundlePath = Bundle.module.resourcePath {
            print("使用 Bundle.module 资源路径: \(bundlePath)")
            return bundlePath
        }

        // 尝试从可执行文件同级目录获取
        let execPath = Bundle.main.bundlePath
        let resourcePath = (execPath as NSString).deletingLastPathComponent + "/Resources"
        if FileManager.default.fileExists(atPath: resourcePath) {
            print("使用本地资源路径: \(resourcePath)")
            return resourcePath
        }
        print("未找到资源路径")
        return nil
    }
}

// MARK: - 动画状态
enum PetState: String, CaseIterable {
    case idle = "idle"          // 站立
    case walk = "walk"          // 走路
    case drag = "drag"          // 被拖拽
    case fall = "fall"          // 下落
    case working = "working"    // 工作中
    case visiting = "visiting"  // 串门中（出门了）
}
