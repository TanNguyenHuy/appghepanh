import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import GhepAnh

final class CollageTests: XCTestCase {
    @MainActor func testResolutionDefaultsTo32MPAndRemembers64MPSwitch() throws {
        let suite = "GhepAnhTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let editor = Editor(preferences: preferences)
        XCTAssertFalse(editor.use64MP)
        XCTAssertEqual(editor.exportSize, CGSize(width: 4936, height: 6581))
        editor.use64MP = true
        let reopened = Editor(preferences: preferences)
        XCTAssertTrue(reopened.use64MP)
        XCTAssertEqual(reopened.exportSize, CGSize(width: 6928, height: 9237))
        reopened.use64MP = false
        XCTAssertEqual(Editor(preferences: preferences).exportSize, Collage.standardSize)
    }

    func test32MPHEICUsesSelectedDimensions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
        let original = try XCTUnwrap(image.pngData())
        try original.write(to: source)
        let output = folder.appendingPathComponent("32mp.heic")
        try Collage.writeHEIC(Array(repeating: source, count: 4), to: output, size: Collage.standardSize)
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(encoded) as String?, UTType.heic.identifier)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 4936)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 6581)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor func testRepeatedLibraryTapsKeepOrderAndIndependentSlots() {
        let editor = Editor()
        for identifier in ["A", "B", "C", "A"] { editor.pick(identifier) }
        XCTAssertEqual(editor.photos.map(\.assetID), ["A", "B", "C", "A"])
        XCTAssertEqual(editor.count("A"), 2)
        XCTAssertEqual(Set(editor.photos.map(\.id)).count, 4)
        editor.remove(editor.photos[0].id)
        XCTAssertEqual(editor.photos.map(\.assetID), ["B", "C", "A"])
        XCTAssertEqual(editor.count("A"), 1)
        editor.move(-1)
        XCTAssertEqual(editor.photos.map(\.assetID), ["B", "A", "C"])
        editor.pick("A")
        editor.pick("A"); editor.pick("A"); editor.pick("A")
        XCTAssertEqual(editor.photos.count, 6)
        editor.busy = true
        editor.remove(editor.photos[0].id)
        editor.pick("B")
        XCTAssertEqual(editor.photos.count, 6)
    }

    func testImageOrderMatchesTopLeftThenTopRight() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let colors: [UIColor] = [.red, .green, .blue, .yellow]
        let urls = try colors.enumerated().map { index, color -> URL in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            }
            let url = folder.appendingPathComponent("\(index).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            return url
        }
        let image = try Collage.render(urls, size: CGSize(width: 300, height: 400))
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        func rgb(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y*image.bytesPerRow+x*4
            return [bytes[offset], bytes[offset+1], bytes[offset+2]]
        }
        XCTAssertEqual(rgb(75, 100), [255, 0, 0])
        XCTAssertEqual(rgb(225, 100), [0, 255, 0])
        XCTAssertEqual(rgb(75, 300), [0, 0, 255])
        XCTAssertEqual(rgb(225, 300), [255, 255, 0])
        XCTAssertEqual(rgb(150, 100), [255, 255, 255])
    }

    func testLayoutKeepsFivePhotoArrangement() throws {
        let cells = try Collage.rectangles(5)
        XCTAssertEqual(cells.count, 5)
        XCTAssertEqual(cells[0].width, 2.0/3, accuracy: 0.0001)
        XCTAssertEqual(cells[1].minY, 0.5)
        XCTAssertEqual(cells[4].minY, 2.0/3, accuracy: 0.0001)
        XCTAssertThrowsError(try Collage.rectangles(3))
    }

    func testHEICExportMatchesUserMeituDimensionsAndKeepsSources() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png")
        // Deterministic fabric-like texture, not a flat color or a personal photo.
        let width = 768, height = 1024
        var pixels = [UInt8](repeating: 255, count: width*height*4)
        var seed: UInt32 = 42
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1664525 &+ 1013904223
                let noise = Int(seed >> 27)-16
                let stripe = Int(24*sin(Double(x)*0.7+Double(y)*0.004))
                let shade = 115 + x*50/width + y*25/height + stripe + noise
                let offset = (y*width+x)*4
                pixels[offset] = UInt8(clamping: shade)
                pixels[offset+1] = UInt8(clamping: shade+12)
                pixels[offset+2] = UInt8(clamping: shade+20)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let texture = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let original = try XCTUnwrap(UIImage(cgImage: texture).pngData())
        try original.write(to: source)
        for count in [4, 5, 6] {
            let preview = try Collage.render(Array(repeating: source, count: count), size: CGSize(width: 300, height: 400))
            XCTAssertEqual(preview.width, 300)
            XCTAssertEqual(preview.height, 400)
        }
        let fullSize = try Collage.render(Array(repeating: source, count: 4), size: Collage.largeSize)
        let output = folder.appendingPathComponent("collage.heic")
        let baseline = folder.appendingPathComponent("baseline.png")
        for iteration in 1...2 {
            try autoreleasepool {
                let started = Date()
                let png = try XCTUnwrap(CGImageDestinationCreateWithURL(baseline as CFURL,
                    UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(png, fullSize, nil)
                XCTAssertTrue(CGImageDestinationFinalize(png))
                let pngSeconds = Date().timeIntervalSince(started)
                let heicStarted = Date()
                try Collage.encodeHEIC(fullSize, to: output)
                let heicSeconds = Date().timeIntervalSince(heicStarted)
                let pngBytes = try baseline.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                let heicBytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                print("EXPORT_BENCHMARK run=\(iteration) pixels=6928x9237 png_s=\(pngSeconds) heic_s=\(heicSeconds) png_bytes=\(pngBytes) heic_bytes=\(heicBytes)")
                XCTAssertLessThan(heicBytes, pngBytes)
            }
        }
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(encoded) as String?, UTType.heic.identifier)
        XCTAssertEqual(CGImageSourceGetCount(encoded), 1)
        let decoded = try Collage.thumbnail(output, maxEdge: 800)
        XCTAssertEqual(decoded.height, 800)
        func sample(_ image: CGImage) throws -> [UInt8] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 80,
                bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 80, height: 80))
            return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 80*80*4))
        }
        let reference = try sample(Collage.thumbnail(baseline, maxEdge: 800))
        let actual = try sample(decoded)
        let meanError = zip(reference, actual).reduce(0.0) { $0 + abs(Double($1.0)-Double($1.1)) } / Double(actual.count)
        XCTAssertLessThan(meanError, 5, "HEIC must preserve the fixture's overall colors and detail.")
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 6928)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 9237)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
