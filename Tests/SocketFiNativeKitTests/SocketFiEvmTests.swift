import XCTest
@testable import SocketFiNativeKit

final class SocketFiEvmTests: XCTestCase {
    @MainActor
    private func client() -> SocketFiNativeAccountClient {
        SocketFiNativeAccountClient(configuration: SocketFiConfiguration(
            apiBaseURL: URL(string: "https://example.invalid")!, clientID: "test",
            applicationID: "fi.socket.tests", network: .testnet, relyingPartyID: "socket.fi"
        ))
    }

    @MainActor
    func testMalformedAddressNeverPrepares() async {
        let client = client()
        var calls = 0
        do {
            _ = try await client.authenticateEvm { _ in
                calls += 1
                return "0x" + String(repeating: "z", count: 40)
            }
            XCTFail("Non-hex address must fail before network access")
        } catch SocketFiNativeError.configuration { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testCancellationReleasesAuthenticationForRetry() async {
        let client = client()
        for _ in 0..<2 {
            do {
                _ = try await client.authenticateEvm { _ in throw CancellationError() }
                XCTFail("Must propagate cancellation")
            } catch is CancellationError { }
            catch { XCTFail("Retry remained blocked: \(error)") }
        }
    }

    @MainActor
    func testConcurrentAttemptIsRejectedWhileWalletPending() async {
        let client = client()
        var pending: CheckedContinuation<String, Error>?
        let first = Task {
            try await client.authenticateEvm { _ in
                try await withCheckedThrowingContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        do {
            _ = try await client.authenticateEvm { _ in
                XCTFail("Second attempt must not open a wallet")
                return ""
            }
            XCTFail("Second attempt must fail")
        } catch SocketFiNativeError.authorizationBusy { }
        catch { XCTFail("Unexpected error: \(error)") }
        pending?.resume(throwing: CancellationError())
        _ = await first.result
    }
}
