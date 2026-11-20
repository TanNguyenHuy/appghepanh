import XCTest
import UIKit
import ImageIO
@testable import GhepAnh

final class CollageTests: XCTestCase {
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

    func testPNGExportMatchesUserMeituDimensionsAndKeepsSources() throws {
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
        for count in [4, 5, 6] {
            let preview = try Collage.render(Array(repeating: source, count: count), size: CGSize(width: 300, height: 400))
            XCTAssertEqual(preview.width, 300)
            XCTAssertEqual(preview.height, 400)
        }
        let output = folder.appendingPathComponent("collage.png")
        try Collage.writePNG(Array(repeating: source, count: 4), to: output)
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 6928)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 9237)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
