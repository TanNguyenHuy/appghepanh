import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum Collage {
    static let exportSize = CGSize(width: 6928, height: 9237)

    static func rectangles(_ count: Int) throws -> [CGRect] {
        switch count {
        case 4:
            return (0..<4).map { i in
                CGRect(x: Double(i % 2)/2, y: Double(i/2)/2, width: 0.5, height: 0.5)
            }
        case 5:
            return [CGRect(x: 0, y: 0, width: 2.0/3, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 2.0/3, height: 0.5)] + (0..<3).map { i in
                CGRect(x: 2.0/3, y: Double(i)/3, width: 1.0/3, height: 1.0/3)
            }
        case 6:
            return (0..<6).map { i in
                CGRect(x: Double(i % 2)/2, y: Double(i/2)/3, width: 0.5, height: 1.0/3)
            }
        default: throw Failure("Chọn đủ 4, 5 hoặc 6 ảnh; có thể nhân đôi ảnh chi tiết.")
        }
    }

    static func thumbnail(_ url: URL, maxEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure("Không đọc được ảnh \(url.lastPathComponent).") }
        return image
    }

    static func render(_ urls: [URL], size: CGSize = exportSize) throws -> CGImage {
        let cells = try rectangles(urls.count)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure("Chưa đủ bộ nhớ để ghép ảnh. Hãy đóng bớt ứng dụng rồi thử lại.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        for (url, cell) in zip(urls, cells) {
            try autoreleasepool {
                let box = CGRect(x: cell.minX*size.width, y: (1-cell.maxY)*size.height,
                                 width: cell.width*size.width, height: cell.height*size.height)
                // Decode only the pixels required for this cell, with its EXIF rotation applied.
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let h = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                    throw Failure("Không đọc được kích thước ảnh.")
                }
                let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                let width = CGFloat((5...8).contains(orientation) ? h.doubleValue : w.doubleValue)
                let height = CGFloat((5...8).contains(orientation) ? w.doubleValue : h.doubleValue)
                let factor = min(1, max(box.width/width, box.height/height))
                let image = try thumbnail(url, maxEdge: max(1, Int(ceil(max(width, height)*factor))))
                let scale = max(box.width/CGFloat(image.width), box.height/CGFloat(image.height))
                let drawSize = CGSize(width: CGFloat(image.width)*scale, height: CGFloat(image.height)*scale)
                context.saveGState()
                context.clip(to: box)
                context.draw(image, in: CGRect(x: box.midX-drawSize.width/2, y: box.midY-drawSize.height/2,
                                               width: drawSize.width, height: drawSize.height))
                context.restoreGState()
            }
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(max(1, size.width/540))
        for cell in cells {
            if cell.maxX < 0.999 {
                context.move(to: CGPoint(x: cell.maxX*size.width, y: (1-cell.minY)*size.height))
                context.addLine(to: CGPoint(x: cell.maxX*size.width, y: (1-cell.maxY)*size.height))
            }
            if cell.maxY < 0.999 {
                context.move(to: CGPoint(x: cell.minX*size.width, y: (1-cell.maxY)*size.height))
                context.addLine(to: CGPoint(x: cell.maxX*size.width, y: (1-cell.maxY)*size.height))
            }
        }
        context.strokePath()
        guard let image = context.makeImage() else { throw Failure("Chưa dựng được ảnh ghép.") }
        return image
    }

    static func writePNG(_ urls: [URL], to destination: URL) throws {
        let image = try render(urls)
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("Không tạo được file PNG.")
        }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw Failure("Chưa lưu được file PNG.") }
    }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
