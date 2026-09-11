import XCTest
@testable import SocketFiNativeKit

private final class WalletFixtureProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var replies: [[String: Any]] = []
        var paths: [String] = []
        var lastRequest: URLRequest?
    }
    private static let state = State()
    static var lastRequest: URLRequest? { state.lock.withLock { state.lastRequest } }
    static var replies: [[String: Any]] {
        get { state.lock.withLock { state.replies } }
        set { state.lock.withLock { state.replies = newValue } }
    }
    static var paths: [String] {
        get { state.lock.withLock { state.paths } }
        set { state.lock.withLock { state.paths = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.lock.withLock { Self.state.lastRequest = request }
        Self.paths.append(request.url!.path)
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let reply = Self.replies.removeFirst()
        let data = try! JSONSerialization.data(withJSONObject: reply)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor
final class SocketFiWalletAPITests: XCTestCase {
    let wallet = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    let token = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    let owner = "0x1111111111111111111111111111111111111111"
    var configuration: SocketFiConfiguration {
        .init(apiBaseURL: URL(string: "https://fixture.invalid")!, clientID: "fixture", applicationID: "fixture", network: .testnet, relyingPartyID: "fixture.invalid")
    }
    func transport() -> URLSession {
        WalletFixtureProtocol.paths = []; WalletFixtureProtocol.replies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WalletFixtureProtocol.self]
        return URLSession(configuration: config)
    }
    func session() -> SocketFiSession {
        let payload = Data(#"{"username":"fixture"}"#.utf8).base64URLEncodedString
        return .init(account: .init(address: wallet, network: .testnet, signer: .evmWallet), accessToken: "fixture.\(payload).fixture", expiresAt: Date().addingTimeInterval(600), evmOwnerAddress: owner, evmWalletSessionTopic: "fixture-wallet-topic")
    }
    func request() -> SocketFiTransactionRequest {
        .init(contractID: token, functionName: "transfer", argsXDR: [], review: .init(title: "Fixture withdrawal", network: .testnet, source: wallet, destination: token, amount: "1 XLM", expiresAt: Date().addingTimeInterval(60)))
    }

    func testHistoryLoadsAuthenticatedPageAndRejectsWrongAccountNetworkAndCursor() async throws {
        let transport = transport()
        let client = SocketFiHistoryClient(configuration: configuration, urlSession: transport)
        let item: [String: Any] = ["id": "indexed-event", "network": "TESTNET", "walletAddress": wallet,
            "txHash": String(repeating: "a", count: 64), "ledger": "4621493", "status": "SUCCESS", "successful": true,
            "actionType": "TRANSFER", "amountAtomic": "90071992547409930000001", "assetDecimals": 7, "assetSymbol": "XLM", "direction": "outgoing"]
        let page: [String: Any] = ["success": true, "network": "TESTNET", "walletAddress": wallet,
            "count": 1, "hasMore": false, "transactions": [item]]
        WalletFixtureProtocol.replies = [page]
        let loaded = try await client.load(session: session())
        XCTAssertEqual(loaded.transactions[0].amountText, "9007199254740993.0000001")
        XCTAssertEqual(loaded.transactions[0].title, "Sent")
        XCTAssertEqual(loaded.transactions[0].explorerURL.host, "stellar.expert")
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/wallet/history"])
        let sent = try XCTUnwrap(WalletFixtureProtocol.lastRequest)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer " + session().accessToken)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-SocketFi-Client-ID"), configuration.clientID)
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-API-Key"))
        let query = URLComponents(url: sent.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "network" })?.value, "TESTNET")
        XCTAssertEqual(query.first(where: { $0.name == "walletAddress" })?.value, wallet)
        for change: [String: Any] in [["network": "PUBLIC"], ["walletAddress": token], ["count": 2],
                                     ["hasMore": true], ["hasMore": true, "nextCursor": "repeated"]] {
            WalletFixtureProtocol.replies = [page.merging(change) { _, new in new }]
            do { _ = try await client.load(session: session(), cursor: "repeated"); XCTFail("Unbound or malformed history must be rejected") }
            catch SocketFiNativeError.invalidResponse { }
        }
        for change: [String: Any] in [["network": "PUBLIC"], ["walletAddress": token], ["txHash": "invalid"], ["successful": false], ["amountAtomic": "1.5"]] {
            WalletFixtureProtocol.replies = [page.merging(["transactions": [item.merging(change) { _, new in new }]]) { _, new in new }]
            do { _ = try await client.load(session: session()); XCTFail("Invalid indexed event must be rejected") }
            catch SocketFiNativeError.invalidResponse { }
        }
    }
    func testTokenTransferPolicySupportsCustomAssetsWithoutOtherPermissions() throws {
        func policy(functions: [String] = ["transfer"]) throws -> SocketFiProjectCapabilities {
            let data = try JSONSerialization.data(withJSONObject: ["clientId": "fixture", "networks": ["TESTNET"],
                "allowedInvocations": [["network": "TESTNET", "contractId": "*", "functions": functions]]])
            return try JSONDecoder().decode(SocketFiProjectCapabilities.self, from: data)
        }
        let capabilities = try policy()
        for contract in [token, wallet, "CCZGLAUBDKJSQK72QOZHVU7CUWKW45OZWYWCLL27AEK74U2OIBK6LXF2"] {
            XCTAssertTrue(capabilities.allows(network: .testnet, contract: contract, function: "transfer"))
            XCTAssertFalse(capabilities.allows(network: .public, contract: contract, function: "transfer"))
            for function in ["mint", "approve", "transfer_from", "upgrade"] {
                XCTAssertFalse(capabilities.allows(network: .testnet, contract: contract, function: function))
            }
        }
        XCTAssertFalse(capabilities.allows(network: .testnet, contract: "*", function: "transfer"))
        XCTAssertFalse(capabilities.allows(network: .testnet, contract: String(token.dropLast()) + "A", function: "transfer"))
        XCTAssertFalse(try policy(functions: ["transfer", "mint"]).allows(network: .testnet, contract: token, function: "transfer"))
    }

    func preparedReply() -> [String: Any] {
        ["success": true, "sessionId": "fixture", "network": "TESTNET", "walletAddress": wallet,
         "evmAddress": owner, "signingMethod": "personal_sign", "expiresInMs": 60000,
         "signaturePayloadHex": "0x" + String(repeating: "a", count: 64)]
    }
    func testEvmConfirmedSubmissionUsesTransactionEndpoint() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let store = SocketFiSessionStore(service: "fi.socket.fixture.\(UUID().uuidString)")
        try await store.save(session())
        let client = SocketFiNativeAccountClient(configuration: configuration, sessionStore: store, urlSession: http)
        let hash = String(repeating: "b", count: 64)
        WalletFixtureProtocol.replies = [preparedReply(), ["success": true, "data": [
            "txHash": hash, "status": "SUCCESS", "walletAddress": wallet, "evmAddress": owner,
            "contractId": token, "functionName": "transfer"]]]
        var submitted = false; var signed = false
        let result = try await client.authorizeEvmTransaction(request(), onSubmission: { submitted = true }) { message in
            if message == "__socketfi_address__" { return self.owner }
            XCTAssertEqual(message, "0x" + String(repeating: "a", count: 64))
            signed = true
            return "0x" + String(repeating: "c", count: 130)
        }
        XCTAssertTrue(signed); XCTAssertTrue(submitted); XCTAssertEqual(result.id, hash)
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/evm-transactions", "/api/evm-transactions"])
        await store.clear()
    }
    func testEvmLostSubmissionResponseIsUncertainAndNeverRetried() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let store = SocketFiSessionStore(service: "fi.socket.fixture.\(UUID().uuidString)")
        try await store.save(session())
        let client = SocketFiNativeAccountClient(configuration: configuration, sessionStore: store, urlSession: http)
        // No second response: transport fails after submission begins.
        WalletFixtureProtocol.replies = [preparedReply()]
        var submitted = false
        do {
            _ = try await client.authorizeEvmTransaction(request(), onSubmission: { submitted = true }) { message in
                message == "__socketfi_address__" ? self.owner : "0x" + String(repeating: "c", count: 130)
            }
            XCTFail("Lost response reported success")
        } catch SocketFiNativeError.submissionUncertain { }
        XCTAssertTrue(submitted)
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/evm-transactions", "/api/evm-transactions"])
        await store.clear()
    }
    func testEvmSignatureCancellationNeverSubmits() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let store = SocketFiSessionStore(service: "fi.socket.fixture.\(UUID().uuidString)")
        try await store.save(session())
        let client = SocketFiNativeAccountClient(configuration: configuration, sessionStore: store, urlSession: http)
        WalletFixtureProtocol.replies = [preparedReply()]
        do {
            _ = try await client.authorizeEvmTransaction(request(), onSubmission: { XCTFail("Cancelled approval submitted") }) { message in
                if message == "__socketfi_address__" { return self.owner }
                throw CancellationError()
            }
            XCTFail("Cancelled signature accepted")
        } catch is CancellationError { }
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/evm-transactions"])
        await store.clear()
    }

    func testWatchlistAcceptsMetadataWithoutBalanceAndRejectsWrongNetwork() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let client = SocketFiWalletClient(configuration: configuration, session: http)
        var metadata: [String: Any] = ["success": true, "network": "TESTNET", "walletAddress": wallet, "token": ["contract": token, "symbol": "XLM", "decimals": 7]]
        WalletFixtureProtocol.replies = [metadata]
        try await client.addTokenToWatchlist(session: session(), contract: token)
        metadata["network"] = "PUBLIC"; WalletFixtureProtocol.replies = [metadata]
        do { try await client.addTokenToWatchlist(session: session(), contract: token); XCTFail("Wrong network accepted") }
        catch SocketFiNativeError.invalidResponse { }
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/wallet/tokens", "/api/wallet/tokens"])
    }
    func testOldSessionDecodesWithoutOwnerAndNewSessionPreservesOwner() throws {
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        let data = try encoder.encode(session())
        XCTAssertEqual(try decoder.decode(SocketFiSession.self, from: data).evmOwnerAddress, owner)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try decoder.decode(SocketFiSession.self, from: data).evmWalletSessionTopic, "fixture-wallet-topic")
        old.removeValue(forKey: "evmOwnerAddress")
        old.removeValue(forKey: "evmWalletSessionTopic")
        let legacy = try decoder.decode(SocketFiSession.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.evmOwnerAddress)
        XCTAssertNil(legacy.evmWalletSessionTopic)
    }
    func testEvmWrongAccountNeverPreparesOrSubmits() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let store = SocketFiSessionStore(service: "fi.socket.fixture.\(UUID().uuidString)")
        try await store.save(session())
        let client = SocketFiNativeAccountClient(configuration: configuration, sessionStore: store, urlSession: http)
        do {
            _ = try await client.authorizeEvmTransaction(request(), onSubmission: { XCTFail("Wrong account submitted") }) { _ in "0x2222222222222222222222222222222222222222" }
            XCTFail("Wrong owner accepted")
        } catch SocketFiNativeError.configuration { }
        await store.clear()
        XCTAssertTrue(WalletFixtureProtocol.paths.isEmpty)
    }
    func testEvmPrepareBindingFailureNeverRequestsSignature() async throws {
        let http = transport(); defer { http.invalidateAndCancel() }
        let store = SocketFiSessionStore(service: "fi.socket.fixture.\(UUID().uuidString)")
        try await store.save(session())
        let client = SocketFiNativeAccountClient(configuration: configuration, sessionStore: store, urlSession: http)
        WalletFixtureProtocol.replies = [["success": true, "sessionId": "fixture", "network": "PUBLIC", "walletAddress": wallet, "evmAddress": owner, "signingMethod": "personal_sign", "expiresInMs": 60000, "signaturePayloadHex": "0x" + String(repeating: "a", count: 64)]]
        do {
            _ = try await client.authorizeEvmTransaction(request(), onSubmission: { XCTFail("Mismatched prepare submitted") }) { message in
                XCTAssertEqual(message, "__socketfi_address__")
                return self.owner
            }
            XCTFail("Mismatched prepare accepted")
        } catch SocketFiNativeError.invalidResponse { }
        await store.clear()
        XCTAssertEqual(WalletFixtureProtocol.paths, ["/api/evm-transactions"])
    }
}
