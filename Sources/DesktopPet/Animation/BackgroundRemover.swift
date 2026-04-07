import AppKit

// MARK: - 背景去除
class BackgroundRemover {
    /// 从边缘 flood-fill 去除背景色，只去除与边框连通的背景像素，保留前景内部同色区域
    static func removeBackground(from image: CGImage, tolerance: CGFloat = 0.08) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 采样四角 5x5 区域的像素，确定背景色
        var samples: [(r: UInt8, g: UInt8, b: UInt8)] = []
        let sampleSize = min(5, min(width, height))
        let corners = [(0, 0), (width - sampleSize, 0), (0, height - sampleSize), (width - sampleSize, height - sampleSize)]
        for (cx, cy) in corners {
            for dy in 0..<sampleSize {
                for dx in 0..<sampleSize {
                    let offset = ((cy + dy) * bytesPerRow) + ((cx + dx) * bytesPerPixel)
                    samples.append((pixelData[offset], pixelData[offset + 1], pixelData[offset + 2]))
                }
            }
        }

        let sortedR = samples.map { $0.r }.sorted()
        let sortedG = samples.map { $0.g }.sorted()
        let sortedB = samples.map { $0.b }.sorted()
        let mid = samples.count / 2
        let bgR = CGFloat(sortedR[mid]) / 255.0
        let bgG = CGFloat(sortedG[mid]) / 255.0
        let bgB = CGFloat(sortedB[mid]) / 255.0

        // 判断像素是否接近背景色
        func isBgColor(at offset: Int) -> Bool {
            let r = CGFloat(pixelData[offset]) / 255.0
            let g = CGFloat(pixelData[offset + 1]) / 255.0
            let b = CGFloat(pixelData[offset + 2]) / 255.0
            let dist = sqrt((r - bgR) * (r - bgR) + (g - bgG) * (g - bgG) + (b - bgB) * (b - bgB))
            return dist < tolerance
        }

        // BFS flood-fill：从图片四条边的所有像素开始，向内扩散
        var visited = [Bool](repeating: false, count: width * height)
        var queue: [(Int, Int)] = []

        // 将四条边上颜色接近背景的像素加入队列
        for x in 0..<width {
            for y in [0, height - 1] {
                let idx = y * width + x
                let offset = y * bytesPerRow + x * bytesPerPixel
                if !visited[idx] && isBgColor(at: offset) {
                    visited[idx] = true
                    queue.append((x, y))
                }
            }
        }
        for y in 1..<(height - 1) {
            for x in [0, width - 1] {
                let idx = y * width + x
                let offset = y * bytesPerRow + x * bytesPerPixel
                if !visited[idx] && isBgColor(at: offset) {
                    visited[idx] = true
                    queue.append((x, y))
                }
            }
        }

        // BFS 扩散
        var head = 0
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            let neighbors = [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]
            for (nx, ny) in neighbors {
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nIdx = ny * width + nx
                guard !visited[nIdx] else { continue }
                let nOffset = ny * bytesPerRow + nx * bytesPerPixel
                if isBgColor(at: nOffset) {
                    visited[nIdx] = true
                    queue.append((nx, ny))
                }
            }
        }

        // 只将 visited（从边缘连通的背景像素）设为透明
        for (x, y) in queue {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixelData[offset] = 0     // R
            pixelData[offset + 1] = 0 // G
            pixelData[offset + 2] = 0 // B
            pixelData[offset + 3] = 0 // A
        }

        return context.makeImage()
    }

    /// 处理图片文件并保存为透明背景 PNG
    static func processAndSave(from sourcePath: String, to destPath: String) -> Bool {
        guard let image = NSImage(contentsOfFile: sourcePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        // 如果图片已经有透明通道且四角已经是透明的，跳过处理
        if cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst {
            // 检查四角是否已经透明
            let width = cgImage.width, height = cgImage.height
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            var checkData = [UInt8](repeating: 0, count: height * bytesPerRow)
            if let ctx = CGContext(data: &checkData, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                let corners = [0, (width - 1) * bytesPerPixel, (height - 1) * bytesPerRow, (height - 1) * bytesPerRow + (width - 1) * bytesPerPixel]
                let allTransparent = corners.allSatisfy { checkData[$0 + 3] < 10 }
                if allTransparent {
                    // 已经是透明背景，直接拷贝
                    try? FileManager.default.removeItem(atPath: destPath)
                    try? FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
                    return true
                }
            }
        }

        guard let processed = removeBackground(from: cgImage) else { return false }

        let nsImage = NSImage(cgImage: processed, size: NSSize(width: processed.width, height: processed.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }

        try? FileManager.default.removeItem(atPath: destPath)
        return FileManager.default.createFile(atPath: destPath, contents: pngData)
    }
}
