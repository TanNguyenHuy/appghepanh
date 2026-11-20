import XCTest

final class LibraryUITests: XCTestCase {
    func testLibraryRepeatedSelectionPreviewAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let access = app.buttons["Cho phép truy cập ảnh"]
        if access.exists && access.isHittable { access.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'All Photos'" )).firstMatch
        if allow.waitForExistence(timeout: 10) { allow.tap() }

        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'libraryPhoto-'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        photo.tap(); photo.tap(); photo.tap(); photo.tap()
        let count = app.staticTexts["selectionCount"]
        XCTAssertEqual(count.label, "4 / 6 ảnh đã chọn")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'selectedRemove-'")).count, 4)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Thu-vien-va-anh-chon-lap"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["selectedRemove-0"].tap()
        XCTAssertEqual(count.label, "3 / 6 ảnh đã chọn")
        photo.tap()
        XCTAssertEqual(count.label, "4 / 6 ảnh đã chọn")
        app.buttons["startCollage"].tap()
        XCTAssertTrue(app.images["collagePreview"].waitForExistence(timeout: 25))
        app.buttons["backToLibrary"].tap()
        XCTAssertEqual(count.label, "4 / 6 ảnh đã chọn")
        app.buttons["startCollage"].tap()
        XCTAssertTrue(app.buttons["saveCollage"].waitForExistence(timeout: 25))
        app.buttons["saveCollage"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 40))
        XCTAssertEqual(count.label, "0 / 6 ảnh đã chọn")
        XCTAssertTrue(photo.exists)
    }
}
