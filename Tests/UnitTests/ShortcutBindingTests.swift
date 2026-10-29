import XCTest
import AppKit
import Carbon.HIToolbox
@testable import ScreenMint

final class ShortcutBindingTests: XCTestCase {
    private func keyEvent(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    func testShiftedDigitMatchesByKeyCode() {
        // ⇧⌘4 reports "$" as charactersIgnoringModifiers; matching must use the key code
        let binding = ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"])
        let event = keyEvent(keyCode: UInt16(kVK_ANSI_4), characters: "$", modifiers: [.command, .shift])
        XCTAssertTrue(binding.matches(event: event))
        XCTAssertFalse(binding.matches(event: keyEvent(keyCode: UInt16(kVK_ANSI_4), characters: "4", modifiers: [.command])))
    }

    func testLegacyShiftedSymbolMapsToDigit() {
        let legacy = ShortcutBinding(key: "$", modifiers: ["⇧", "⌘"])
        XCTAssertEqual(legacy.keyCode, UInt16(kVK_ANSI_4))
        XCTAssertEqual(legacy.displayString, "⇧⌘4")
    }

    func testCarbonModifiersAndValidity() {
        let binding = ShortcutBinding(key: "7", modifiers: ["⌘", "⌥"])
        XCTAssertEqual(binding.carbonModifiers, UInt32(cmdKey | optionKey))
        XCTAssertTrue(binding.isValidGlobalHotKey)
        XCTAssertFalse(ShortcutBinding(key: "A", modifiers: []).isValidGlobalHotKey)
        XCTAssertFalse(ShortcutBinding(key: "Esc", modifiers: ["⇧"]).isValidGlobalHotKey)
        XCTAssertTrue(ShortcutBinding(key: "F5", modifiers: []).isValidGlobalHotKey)
    }

    func testEscapeBindingMatchesEscKey() {
        let cancel = ShortcutBinding(key: "Esc", modifiers: [])
        XCTAssertTrue(cancel.matches(event: keyEvent(keyCode: UInt16(kVK_Escape), characters: "\u{1b}", modifiers: [])))
    }

    func testCustomActionNamesMapToCaptureActions() {
        XCTAssertEqual(CaptureActionType(customActionName: "Capture Window"), .window)
        XCTAssertEqual(CaptureActionType(customActionName: "OCR Text from Screen"), .ocr)
        XCTAssertNil(CaptureActionType(customActionName: "Copy Selection"))
    }
}
