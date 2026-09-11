import XCTest
@testable import SocketFi
import SocketFiNativeKit

@MainActor
final class SocketFiHistoryTests: XCTestCase {
    private func page(_ ids: [String], cursor: String? = nil) throws -> SocketFiHistoryPage {
        let wallet = "CCFBZEUCDA4XT5TBSIHO6SH72P5NNQSUGFHAZTPS7YWMNXFS7KXAM5ZV"
        let items: [[String: Any]] = ids.map { id in
            ["id": id, "network": "TESTNET", "walletAddress": wallet, "txHash": String(repeating: "a", count: 64),
             "ledger": "4621493", "ledgerClosedAt": "2026-09-11T12:00:00.000Z", "status": "SUCCESS", "successful": true,
             "actionType": "TRANSFER", "assetSymbol": "UNKNOWN", "assetDecimals": 18, "amountAtomic": "1", "direction": "incoming"]
        }
        var json: [String: Any] = ["success": true, "network": "TESTNET", "walletAddress": wallet,
            "count": ids.count, "hasMore": cursor != nil, "transactions": items]
        json["nextCursor"] = cursor
        return try JSONDecoder().decode(SocketFiHistoryPage.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testPaginationPreservesMultipleEventsForSameHashAndRetriesWithoutLosingRows() async throws {
        let first = try page(["event-1", "event-2"], cursor: "next")
        let second = try page(["event-2", "event-3"])
        var requests: [String?] = []
        var failNext = true
        let model = SocketFiHistoryModel { cursor in
            requests.append(cursor)
            if cursor == nil { return first }
            if failNext { failNext = false; throw URLError(.timedOut) }
            return second
        }
        await model.refresh()
        XCTAssertEqual(model.items.count, 2)
        await model.loadMore()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.nextCursor, "next")
        XCTAssertNotNil(model.pageError)
        await model.loadMore()
        XCTAssertEqual(model.items.map(\.id), ["event-1", "event-2", "event-3"])
        XCTAssertNil(model.nextCursor)
        XCTAssertNil(model.pageError)
        XCTAssertEqual(requests.count, 3)
    }

    func testRefreshFailureRetainsHistoryAndCancellationDoesNotBecomeEmptySuccess() async throws {
        let first = try page(["one"])
        var failure: Error?
        let model = SocketFiHistoryModel { _ in
            if let failure { throw failure }
            return first
        }
        await model.refresh()
        failure = URLError(.notConnectedToInternet)
        await model.refresh()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.loading)
        let cancelled = SocketFiHistoryModel { _ in throw CancellationError() }
        await cancelled.refresh()
        XCTAssertFalse(cancelled.loaded)
        XCTAssertNil(cancelled.error)
    }

    func testCursorCycleFailsWithoutDroppingLoadedActivity() async throws {
        let first = try page(["one"], cursor: "a")
        let second = try page(["two"], cursor: "b")
        let cycle = try page(["three"], cursor: "a")
        let model = SocketFiHistoryModel { cursor in cursor == nil ? first : cursor == "a" ? second : cycle }
        await model.refresh(); await model.loadMore(); await model.loadMore()
        XCTAssertEqual(model.items.map(\.id), ["one", "two"])
        XCTAssertNotNil(model.pageError)
    }

    func testUnknownAssetMetadataAndTinyAmountsStayVisible() throws {
        let item = try XCTUnwrap(page(["one"]).transactions.first)
        XCTAssertEqual(item.amountText, "0.000000000000000001")
        XCTAssertEqual(item.symbol, "")
        XCTAssertEqual(item.title, "Received")
        XCTAssertNotNil(item.date)
    }
}
