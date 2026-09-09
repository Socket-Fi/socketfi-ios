import XCTest
@testable import SocketFiNativeKit

final class SocketFiWalletTests: XCTestCase {
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let recipient = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"

    func testExactAtomicAmountsAndPrecisionLimits() throws {
        XCTAssertEqual(try SocketFiAmount.atomic("900719925.4740993", decimals: 7), "9007199254740993")
        XCTAssertEqual(try SocketFiAmount.atomic("0001.0000001", decimals: 7), "10000001")
        XCTAssertEqual(SocketFiAmount.display("10000001", decimals: 7), "1.0000001")
        XCTAssertEqual(SocketFiAmount.display("1", decimals: 7), "0.0000001")
        XCTAssertEqual(try SocketFiAmount.normalized(SocketFiAmount.maximum), SocketFiAmount.maximum)
        for invalid in ["-1", "+1", "1e7", "NaN", "1,000", ".", "", "1.00000001", "1.2.3", "1 2", "１２"] {
            XCTAssertThrowsError(try SocketFiAmount.atomic(invalid, decimals: 7), invalid)
        }
        XCTAssertThrowsError(try SocketFiAmount.normalized("170141183460469231731687303715884105728"))
        XCTAssertThrowsError(try SocketFiAmount.atomic("1", decimals: -1))
        XCTAssertThrowsError(try SocketFiAmount.atomic("1", decimals: 19))
    }

    func testSlippageUsesIntegerRoundingEvenBeyondDecimalPrecision() throws {
        XCTAssertEqual(try SocketFiAmount.minimumOutput("10001", slippageBps: 50), "9950")
        XCTAssertEqual(try SocketFiAmount.minimumOutput(SocketFiAmount.maximum, slippageBps: 50), "169290477543166885573028867197304685198")
        XCTAssertEqual(try SocketFiAmount.minimumOutput("1", slippageBps: 50), "0")
    }

    func testAddressChecksumAndScValMatchStellarSDKFixtures() throws {
        // Generated independently with @stellar/stellar-sdk nativeToScVal.
        XCTAssertEqual(try SocketFiXDR.address(xlm), "AAAAEgAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQ==")
        XCTAssertEqual(try SocketFiXDR.address(recipient), "AAAAEgAAAAAAAAAAQj59BfLsr7/sGSshWj8b6WrtuNjnAlSr40E+AgfeVrI=")
        XCTAssertEqual(try SocketFiXDR.integer("123456789"), "AAAACgAAAAAAAAAAAAAAAAdbzRU=")
        XCTAssertEqual(try SocketFiXDR.integer("123456789", unsigned: true), "AAAACQAAAAAAAAAAAAAAAAdbzRU=")
        XCTAssertEqual(try SocketFiXDR.integer(SocketFiAmount.maximum), "AAAACn////////////////////8=")
        XCTAssertFalse(SocketFiXDR.isAddress(recipient, contractOnly: true))
        XCTAssertFalse(SocketFiXDR.isAddress(String(xlm.dropLast()) + "A"))
        XCTAssertFalse(SocketFiXDR.isAddress(xlm.lowercased()))
        XCTAssertFalse(SocketFiXDR.isAddress("M" + String(xlm.dropFirst())))
    }

    func testUnavailableBalancesAndPricesAreNotDisplayedAsZero() throws {
        let missingBalance = try token(balance: nil, status: "unavailable")
        XCTAssertNil(missingBalance.availableBalance)
        XCTAssertNil(missingBalance.estimatedValue)
        XCTAssertEqual(missingBalance.balanceText, "—")
        let missingPrice = try token(balance: "10000000", priceStatus: "unavailable")
        XCTAssertNil(missingPrice.estimatedValue)
        let zero = try token(balance: "0", priceStatus: "unavailable")
        XCTAssertEqual(zero.estimatedValue, 0)
        let valid = try token(balance: "12345678")
        XCTAssertEqual(valid.balanceText, "1.2345678")
        XCTAssertEqual(valid.estimatedValue, Decimal(string: "2.4691356"))
    }

    @MainActor
    func testWithdrawalBindsReviewedRecipientAmountNetworkAndPermission() throws {
        let asset = try token(balance: "9007199254740993")
        let session = session()
        let permissions = try capabilities()
        let request = try SocketFiWalletTransactions.withdrawal(session: session, token: asset, recipient: recipient,
                                                                amount: "1.2345678", capabilities: permissions)
        XCTAssertEqual(request.contractID, xlm)
        XCTAssertEqual(request.functionName, "transfer")
        XCTAssertEqual(request.argsXDR, [try SocketFiXDR.address(usdc), try SocketFiXDR.address(recipient), try SocketFiXDR.integer("12345678")])
        XCTAssertEqual(request.review.source, usdc)
        XCTAssertEqual(request.review.destination, recipient)
        XCTAssertEqual(request.review.network, .testnet)
        XCTAssertEqual(request.review.amount, "1.2345678 XLM")
        XCTAssertThrowsError(try SocketFiWalletTransactions.withdrawal(session: session, token: asset, recipient: usdc, amount: "1", capabilities: permissions))
        XCTAssertThrowsError(try SocketFiWalletTransactions.withdrawal(session: session, token: asset, recipient: recipient, amount: "900719926", capabilities: permissions))
        XCTAssertThrowsError(try SocketFiWalletTransactions.withdrawal(session: self.session(network: .public), token: asset, recipient: recipient, amount: "1", capabilities: permissions))
        XCTAssertThrowsError(try SocketFiWalletTransactions.withdrawal(session: session, token: self.token(balance: nil, status: "unavailable"), recipient: recipient, amount: "1", capabilities: permissions))
    }

    func testQuoteRejectsChangedAmountNetworkAndExpiredOrUnsafeMinimum() throws {
        let valid = try quote()
        XCTAssertNoThrow(try valid.validate(network: .testnet, tokenIn: xlm, tokenOut: usdc, amount: "10000000", slippageBps: 50))
        XCTAssertThrowsError(try valid.validate(network: .public, tokenIn: xlm, tokenOut: usdc, amount: "10000000", slippageBps: 50))
        XCTAssertThrowsError(try valid.validate(network: .testnet, tokenIn: xlm, tokenOut: usdc, amount: "10000001", slippageBps: 50))
        XCTAssertThrowsError(try valid.validate(network: .testnet, tokenIn: usdc, tokenOut: xlm, amount: "10000000", slippageBps: 50))
        XCTAssertThrowsError(try quote(minimum: "1").validate(network: .testnet, tokenIn: xlm, tokenOut: usdc, amount: "10000000", slippageBps: 50))
        XCTAssertThrowsError(try quote(expiry: Date(timeIntervalSince1970: 0)).validate(network: .testnet, tokenIn: xlm, tokenOut: usdc, amount: "10000000", slippageBps: 50))
    }

    func testSubmissionRequiresAuthoritativeSuccessAndRealHash() throws {
        let hash = String(repeating: "a", count: 64)
        XCTAssertTrue(try SocketFiTransactionResult.confirmedSubmission(hash: hash, status: "SUCCESS").submitted)
        for status in ["PENDING", "NOT_FOUND", "FAILED", "ERROR", "success", ""] {
            XCTAssertThrowsError(try SocketFiTransactionResult.confirmedSubmission(hash: hash, status: status))
        }
        XCTAssertThrowsError(try SocketFiTransactionResult.confirmedSubmission(hash: nil, status: "SUCCESS"))
        XCTAssertThrowsError(try SocketFiTransactionResult.confirmedSubmission(hash: "intent-id", status: "SUCCESS"))
    }

    @MainActor
    func testSwapArgumentsAndReviewMatchTheQuote() throws {
        let from = try token(balance: "10000000")
        let to = try token(balance: "0", contract: usdc)
        let quote = try quote()
        let request = try SocketFiWalletTransactions.swap(
            session: session(), from: from, to: to, amount: "1", slippageBps: 50,
            quote: quote, capabilities: capabilities(functions: ["swap_chained"])
        )
        XCTAssertEqual(request.functionName, "swap_chained")
        XCTAssertEqual(request.argsXDR, [try SocketFiXDR.address(usdc), quote.swapChainXdr,
                                       try SocketFiXDR.address(xlm), try SocketFiXDR.integer("10000000", unsigned: true),
                                       try SocketFiXDR.integer("19900000", unsigned: true)])
        XCTAssertEqual(request.review.minimumReceived, "1.99 XLM")
        XCTAssertEqual(request.review.slippage, "0.5%")
        XCTAssertThrowsError(try SocketFiWalletTransactions.swap(
            session: session(), from: from, to: to, amount: "1", slippageBps: 50,
            quote: quote, capabilities: capabilities()
        ))
    }

    func testExistingSessionUsesInternalUsernameForBalanceLookup() throws {
        let payload = Data(#"{"username":"internal_identity","projectUsername":"display_name"}"#.utf8).base64URLEncodedString
        let value = SocketFiSession(account: session().account, accessToken: "header.\(payload).signature", expiresAt: Date().addingTimeInterval(60))
        XCTAssertEqual(value.walletUsername, "internal_identity")
        XCTAssertNil(session().walletUsername)
    }

    private func session(network: SocketFiNetwork = .testnet) -> SocketFiSession {
        SocketFiSession(account: SocketFiAccount(address: usdc, network: network, signer: .passkey), accessToken: "fixture", expiresAt: Date().addingTimeInterval(300))
    }

    private func token(balance: String?, status: String = "fresh", priceStatus: String = "available", contract: String? = nil) throws -> SocketFiToken {
        let object: [String: Any] = ["contract": contract ?? xlm, "symbol": "XLM", "decimals": 7,
                                   "atomicBalance": balance.map { $0 as Any } ?? NSNull(), "balanceStatus": status,
                                   "price": ["selectedPrice": "2", "status": priceStatus]]
        return try JSONDecoder().decode(SocketFiToken.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func capabilities(functions: [String] = ["transfer"]) throws -> SocketFiProjectCapabilities {
        let object: [String: Any] = ["clientId": "fixture", "networks": ["TESTNET"],
                                   "allowedInvocations": [["network": "TESTNET", "contractId": xlm, "functions": functions]]]
        return try JSONDecoder().decode(SocketFiProjectCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func quote(minimum: String = "19900000", expiry: Date = Date().addingTimeInterval(30)) throws -> SocketFiSwapQuote {
        let object: [String: Any] = ["network": "TESTNET", "routerContractId": xlm, "tokenIn": xlm, "tokenOut": usdc,
                                   "amountInAtomic": "10000000", "quotedOutAtomic": "20000000", "minimumOutAtomic": minimum,
                                   "swapChainXdr": "AAAAEAAAAAEAAAAA", "pools": ["fixture"], "slippageBps": 50,
                                   "expiresAt": ISO8601DateFormatter().string(from: expiry)]
        return try JSONDecoder().decode(SocketFiSwapQuote.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
