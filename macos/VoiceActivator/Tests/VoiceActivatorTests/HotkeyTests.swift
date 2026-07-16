import XCTest
@testable import VoiceActivator

final class HotkeyTests: XCTestCase {
    func testHotkeyRoundTripAndValidation() throws {
        XCTAssertEqual(try Hotkey.parse("cmd+shift+space").encode(), "cmd+shift+space")
        XCTAssertEqual(try Hotkey.parse("cmd+shift+space").displayName, "⇧⌘Space")
        XCTAssertThrowsError(try Hotkey.parse("space"))
        XCTAssertThrowsError(try Hotkey.parse("cmd"))
    }

    func testTransientStatesShowOverlay() {
        XCTAssertFalse(MenuState.idle.showsOverlay)
        XCTAssertTrue(MenuState.listening.showsOverlay)
        XCTAssertTrue(MenuState.transcribing.showsOverlay)
        XCTAssertTrue(MenuState.success.showsOverlay)
        XCTAssertTrue(MenuState.error("boom").showsOverlay)
        XCTAssertTrue(MenuState.success.isTransient)
        XCTAssertTrue(MenuState.error("boom").isTransient)
        XCTAssertFalse(MenuState.listening.isTransient)
        XCTAssertEqual(MenuState.success.label, "Copied to clipboard")
        XCTAssertEqual(BackendSettings.default.action, "clipboard")
    }
}
