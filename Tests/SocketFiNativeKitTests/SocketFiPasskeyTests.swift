import XCTest
@testable import SocketFiNativeKit

final class SocketFiPasskeyTests: XCTestCase {
    @MainActor
    func testEmptyChallengeFailsBeforePresentingAppleSheet() async throws {
        let options = try JSONDecoder().decode(
            SocketFiPasskeyOptions.self,
            from: Data(#"{"challenge":""}"#.utf8)
        )
        do {
            _ = try await SocketFiPasskeySigner().perform(
                options: options, relyingPartyID: "socket.fi", mode: .signIn
            )
            XCTFail("An empty challenge must never open authentication")
        } catch SocketFiNativeError.invalidChallenge {
            // Expected protocol validation failure.
        }
    }

    @MainActor
    func testMissingRegistrationUserFailsBeforePresentingAppleSheet() async throws {
        let options = try JSONDecoder().decode(
            SocketFiPasskeyOptions.self,
            from: Data(#"{"challenge":"AQID"}"#.utf8)
        )
        do {
            _ = try await SocketFiPasskeySigner().perform(
                options: options, relyingPartyID: "socket.fi", mode: .signUp
            )
            XCTFail("Registration requires a user handle")
        } catch SocketFiNativeError.invalidChallenge {
            // Expected protocol validation failure.
        }
    }

    func testWebAuthnBinaryEncodingRoundTrip() throws {
        let bytes = Data([0, 255, 254, 128, 1])
        XCTAssertEqual(Data(base64URLEncoded: bytes.base64URLEncodedString), bytes)
        XCTAssertFalse(bytes.base64URLEncodedString.contains("="))
        XCTAssertNil(Data(base64URLEncoded: "not a credential!"))
    }
}
