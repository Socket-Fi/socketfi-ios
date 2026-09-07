import XCTest
@testable import SocketFiNativeKit

final class SocketFiUsernameTests: XCTestCase {
    func testNormalization() {
        XCTAssertEqual(SocketFiUsername.normalize("Shola Otitoju"), "shola_otitoju")
    }

    func testServerCompatibleBoundaries() {
        for value in ["abc", "shola_2", "shola-two", String(repeating: "a", count: 30)] {
            XCTAssertTrue(SocketFiUsername.isValid(value), value)
        }
        for value in ["ab", "_shola", "shola-", "Shola", "shola@test", "shola\n", String(repeating: "a", count: 31)] {
            XCTAssertFalse(SocketFiUsername.isValid(value), value)
        }
    }

    func testSuggestionsAreShortAndValid() {
        for _ in 0..<100 {
            let name = SocketFiUsername.suggested()
            XCTAssertTrue(name.hasPrefix("socketfi_"))
            XCTAssertLessThanOrEqual(name.count, 16)
            XCTAssertTrue(SocketFiUsername.isValid(name))
        }
    }
}
