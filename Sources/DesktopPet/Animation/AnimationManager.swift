import AppKit
import QuartzCore

// MARK: - 动画管理器
class AnimationManager {
    private var frames: [PetState: [CGImage]] = [:]
    private(set) var currentState: PetState = .idle
    private var currentFrameIndex: Int = 0
    private var timer: Timer?
    private var onFrameUpdate: ((CGImage, Bool) -> Void)?

    init() {
        loadAllAnimations()
    }

    // 加载自定义单张图片，每个状态都用同一帧
    func loadCustomImage(slot: Int = 0) -> Bool {
        let s = slot > 0 ? slot : SettingsManager.shared.currentSlot()
        let path = SettingsManager.shared.customImagePath(slot: s)
        guard let image = loadImage(from: path) else { return false }
        for state in PetState.allCases {
            frames[state] = [image]
        }
        currentFrameIndex = 0
        return true
    }

    func loadAllAnimations() {
        for state in PetState.allCases {
            frames[state] = loadFrames(for: state)
        }

        // 如果没有加载到任何图片，使用默认绘制
        if frames.values.allSatisfy({ $0.isEmpty }) {
            print("未找到自定义图片，使用默认形象")
            let defaultImage = createDefaultCatImage()
            for state in PetState.allCases {
                frames[state] = defaultImage != nil ? [defaultImage!] : []
            }
        }
    }

    private func loadFrames(for state: PetState) -> [CGImage] {
        var images: [CGImage] = []

        guard let resourcePath = PetConfig.getResourcePath() else {
            return images
        }

        // 尝试加载序列帧: state_0.png, state_1.png, ...
        var index = 0
        while true {
            let framePath = "\(resourcePath)/\(state.rawValue)_\(index).png"
            if let image = loadImage(from: framePath) {
                images.append(image)
                index += 1
            } else {
                break
            }
        }

        // 如果没有序列帧，尝试加载单张图片: state.png
        if images.isEmpty {
            let singlePath = "\(resourcePath)/\(state.rawValue).png"
            if let image = loadImage(from: singlePath) {
                images.append(image)
            }
        }

        // 尝试加载 GIF
        if images.isEmpty {
            let gifPath = "\(resourcePath)/\(state.rawValue).gif"
            images = loadGIF(from: gifPath)
        }

        return images
    }

    private func loadImage(from path: String) -> CGImage? {
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    private func loadGIF(from path: String) -> [CGImage] {
        var frames: [CGImage] = []
        guard let url = URL(string: "file://\(path)"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return frames
        }

        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
                frames.append(image)
            }
        }
        return frames
    }

    func setState(_ state: PetState) {
        guard state != currentState else { return }
        currentState = state
        currentFrameIndex = 0

        // 如果当前状态没有帧，尝试使用 idle
        if frames[state]?.isEmpty ?? true {
            if let idleFrames = frames[.idle], !idleFrames.isEmpty {
                // 使用 idle 作为后备
            }
        }
    }

    func start(onFrameUpdate: @escaping (CGImage, Bool) -> Void) {
        self.onFrameUpdate = onFrameUpdate
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / PetConfig.animationFPS, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        updateFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateFrame() {
        var currentFrames = frames[currentState] ?? []

        // 后备到 idle
        if currentFrames.isEmpty {
            currentFrames = frames[.idle] ?? []
        }

        guard !currentFrames.isEmpty else { return }

        currentFrameIndex = currentFrameIndex % currentFrames.count
        let image = currentFrames[currentFrameIndex]

        // 检查是否需要翻转（根据文件名判断是否自带方向）
        let needsFlip = true  // 默认支持翻转

        onFrameUpdate?(image, needsFlip)
        currentFrameIndex += 1
    }

    // 默认猫咪绘制
    private func createDefaultCatImage() -> CGImage? {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            // 身体 - 橙色椭圆
            NSColor.orange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 4, width: 48, height: 40)).fill()

            // 左耳
            let leftEar = NSBezierPath()
            leftEar.move(to: NSPoint(x: 12, y: 38))
            leftEar.line(to: NSPoint(x: 6, y: 58))
            leftEar.line(to: NSPoint(x: 24, y: 44))
            leftEar.close()
            NSColor.orange.setFill()
            leftEar.fill()
            let leftInnerEar = NSBezierPath()
            leftInnerEar.move(to: NSPoint(x: 14, y: 40))
            leftInnerEar.line(to: NSPoint(x: 10, y: 52))
            leftInnerEar.line(to: NSPoint(x: 20, y: 43))
            leftInnerEar.close()
            NSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1).setFill()
            leftInnerEar.fill()

            // 右耳
            let rightEar = NSBezierPath()
            rightEar.move(to: NSPoint(x: 52, y: 38))
            rightEar.line(to: NSPoint(x: 58, y: 58))
            rightEar.line(to: NSPoint(x: 40, y: 44))
            rightEar.close()
            NSColor.orange.setFill()
            rightEar.fill()
            let rightInnerEar = NSBezierPath()
            rightInnerEar.move(to: NSPoint(x: 50, y: 40))
            rightInnerEar.line(to: NSPoint(x: 54, y: 52))
            rightInnerEar.line(to: NSPoint(x: 44, y: 43))
            rightInnerEar.close()
            NSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1).setFill()
            rightInnerEar.fill()

            // 眼睛
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18, y: 22, width: 12, height: 14)).fill()
            NSBezierPath(ovalIn: NSRect(x: 34, y: 22, width: 12, height: 14)).fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 26, width: 5, height: 7)).fill()
            NSBezierPath(ovalIn: NSRect(x: 38, y: 26, width: 5, height: 7)).fill()

            // 鼻子
            NSColor(red: 1, green: 0.6, blue: 0.6, alpha: 1).setFill()
            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: 32, y: 20))
            nose.line(to: NSPoint(x: 28, y: 14))
            nose.line(to: NSPoint(x: 36, y: 14))
            nose.close()
            nose.fill()

            // 嘴巴
            NSColor(red: 0.3, green: 0.2, blue: 0.2, alpha: 1).setStroke()
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 32, y: 14))
            mouth.line(to: NSPoint(x: 32, y: 10))
            mouth.move(to: NSPoint(x: 32, y: 10))
            mouth.curve(to: NSPoint(x: 26, y: 8), controlPoint1: NSPoint(x: 30, y: 8), controlPoint2: NSPoint(x: 28, y: 7))
            mouth.move(to: NSPoint(x: 32, y: 10))
            mouth.curve(to: NSPoint(x: 38, y: 8), controlPoint1: NSPoint(x: 34, y: 8), controlPoint2: NSPoint(x: 36, y: 7))
            mouth.lineWidth = 1.5
            mouth.stroke()

            // 胡须
            NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1).setStroke()
            let whiskers = NSBezierPath()
            whiskers.lineWidth = 1
            whiskers.move(to: NSPoint(x: 20, y: 16))
            whiskers.line(to: NSPoint(x: 4, y: 20))
            whiskers.move(to: NSPoint(x: 20, y: 14))
            whiskers.line(to: NSPoint(x: 4, y: 14))
            whiskers.move(to: NSPoint(x: 20, y: 12))
            whiskers.line(to: NSPoint(x: 4, y: 8))
            whiskers.move(to: NSPoint(x: 44, y: 16))
            whiskers.line(to: NSPoint(x: 60, y: 20))
            whiskers.move(to: NSPoint(x: 44, y: 14))
            whiskers.line(to: NSPoint(x: 60, y: 14))
            whiskers.move(to: NSPoint(x: 44, y: 12))
            whiskers.line(to: NSPoint(x: 60, y: 8))
            whiskers.stroke()

            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
