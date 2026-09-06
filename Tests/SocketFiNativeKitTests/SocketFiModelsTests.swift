import XCTest
@testable import SocketFiNativeKit

final class SocketFiModelsTests: XCTestCase {
    func testAllOwnerMethodsArePresented() {
        XCTAssertEqual(
            Set(SocketFiSignInMethod.allCases),
            [.passkey, .evmWallet, .stellarWallet]
        )
    }

    func testExpiredSessionIsDetected() {
        let account = SocketFiAccount(
            address: "GACCOUNT",
            network: .testnet,
            signer: .passkey
        )
        let session = SocketFiSession(
            account: account,
            accessToken: "token",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(session.isExpired)
    }
}
