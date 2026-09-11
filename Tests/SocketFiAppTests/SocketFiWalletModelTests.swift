import XCTest
@testable import SocketFi
import SocketFiNativeKit

@MainActor
final class SocketFiWalletModelTests: XCTestCase {
    func testCompletedReviewCannotStartAnotherApproval() async {
        let configuration = SocketFiConfiguration(apiBaseURL: URL(string: "https://fixture.invalid")!, clientID: "fixture", applicationID: "fixture", network: .testnet, relyingPartyID: "fixture.invalid")
        let address = "CCFBZEUCDA4XT5TBSIHO6SH72P5NNQSUGFHAZTPS7YWMNXFS7KXAM5ZV"
        let session = SocketFiSession(account: .init(address: address, network: .testnet, signer: .evmWallet), accessToken: "fixture", expiresAt: Date().addingTimeInterval(60))
        let model = SocketFiWalletModel(session: session, configuration: configuration, signer: .init(configuration: configuration))
        model.unresolved = false
        model.action = .withdraw
        model.review = .init(contractID: address, functionName: "transfer", argsXDR: [], review: .init(title: "Withdraw", network: .testnet, source: address, destination: address, amount: "1 XLM", expiresAt: Date().addingTimeInterval(60)))
        model.actionResult = .init(title: "Withdraw", hash: String(repeating: "a", count: 64), confirmed: true)
        await model.approve()
        XCTAssertNil(model.actionError, "A completed review must return before trying to reconnect or authorize again")
        XCTAssertFalse(model.busy)
        XCTAssertNotNil(model.review)
        XCTAssertNotNil(model.actionResult)
        model.open(.withdraw)
        XCTAssertNil(model.actionResult)
        XCTAssertNil(model.review)
    }
}
