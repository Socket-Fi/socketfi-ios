import XCTest
@testable import SocketFi
@preconcurrency import ReownAppKit

final class SocketFiEvmSessionTests: XCTestCase {
    private let first = "0x1111111111111111111111111111111111111111"
    private let second = "0x2222222222222222222222222222222222222222"

    private func session(addresses: [String], scoped: Bool = false, signing: Bool = true, topic: String = "fixture-topic", expiresIn: TimeInterval = 600) -> Session {
        Session(topic: topic, pairingTopic: "fixture-pairing",
                peer: AppMetadata(name: "Fixture wallet", description: "Test fixture",
                                  url: "https://example.invalid", icons: [], redirect: try! AppMetadata.Redirect(native: "fixture-wallet://", universal: nil)),
                requiredNamespaces: [:], namespaces: [
                    scoped ? "eip155:1" : "eip155": SessionNamespace(
                        accounts: addresses.map { Account("eip155:1:" + $0)! },
                        methods: signing ? ["personal_sign"] : [], events: []),
                    "solana": SessionNamespace(
                        accounts: [Account("solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp:11111111111111111111111111111111")!],
                        methods: ["solana_signMessage"], events: [])
                ], sessionProperties: nil, scopedProperties: nil,
                expiryDate: Date().addingTimeInterval(expiresIn))
    }

    @MainActor
    func testTransactionUsesOnlyAuthenticatedWalletEvenWhenAnotherHasSameOwner() throws {
        let original = session(addresses: [first], topic: "signed-in-wallet")
        let otherWallet = session(addresses: [first], topic: "other-wallet")
        let selected = try SocketFiWalletConnect.transactionSession(sessions: [otherWallet, original], topic: "signed-in-wallet", owner: first)
        XCTAssertEqual(selected.topic, "signed-in-wallet")
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [otherWallet], topic: "signed-in-wallet", owner: first))
    }

    @MainActor
    func testTransactionRejectsMissingExpiredChangedAndInvalidatedAuthority() throws {
        let connected = session(addresses: [first])
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [connected], topic: nil, owner: first))
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [connected], topic: connected.topic, owner: nil))
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [connected], topic: connected.topic, owner: second))
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [connected], topic: connected.topic, owner: first, invalidatedTopics: [connected.topic]))
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [session(addresses: [first], expiresIn: -1)], topic: connected.topic, owner: first))
        XCTAssertThrowsError(try SocketFiWalletConnect.transactionSession(sessions: [session(addresses: [first], signing: false)], topic: connected.topic, owner: first))
    }

    @MainActor
    func testWalletPairingLinksPreserveCompleteURI() throws {
        let uri = "wc:fixture@2?relay-protocol=irn&symKey=fixture"
        for link in ["metamask://", "trust:", "rainbow://", "https://wallet.example/connect"] {
            let url = try XCTUnwrap(SocketFiWalletConnect.pairingURL(link: link, uri: uri))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "uri" })?.value, uri)
            XCTAssertTrue(url.absoluteString.contains("wc?"))
        }
        let existing = try XCTUnwrap(SocketFiWalletConnect.pairingURL(link: "https://wallet.example/wc/", uri: uri))
        XCTAssertEqual(existing.path, "/wc")
        XCTAssertNil(SocketFiWalletConnect.pairingURL(link: "invalid link", uri: uri))
    }

    @MainActor
    func testMixedTrustSessionSelectsEvmEvenWhenAppKitDisplaysSolana() throws {
        let account = try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [first]),
            displayedAddress: "11111111111111111111111111111111", boundAddress: nil)
        XCTAssertEqual(account.address, first)
        XCTAssertEqual(account.blockchain.namespace, "eip155")
    }

    @MainActor
    func testChainScopedNamespaceIsAccepted() throws {
        let account = try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [first], scoped: true),
            displayedAddress: nil, boundAddress: nil)
        XCTAssertEqual(account.address, first)
    }

    @MainActor
    func testAmbiguousEvmAccountsRequireSelection() {
        XCTAssertThrowsError(try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [first, second]),
            displayedAddress: "11111111111111111111111111111111", boundAddress: nil))
    }

    @MainActor
    func testAccountSwitchCannotReplacePreparedSigner() {
        XCTAssertThrowsError(try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [first, second]),
            displayedAddress: second, boundAddress: first))
    }

    @MainActor
    func testRemovedBoundAccountFailsClosed() {
        XCTAssertThrowsError(try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [second]),
            displayedAddress: second, boundAddress: first))
    }

    @MainActor
    func testSigningPermissionIsRequired() {
        XCTAssertThrowsError(try SocketFiWalletConnect.resolveAccount(
            session: session(addresses: [first], signing: false),
            displayedAddress: first, boundAddress: nil))
    }
}
