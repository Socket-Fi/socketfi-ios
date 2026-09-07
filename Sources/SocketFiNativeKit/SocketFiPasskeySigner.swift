import Foundation
import AuthenticationServices
import UIKit

@MainActor
public final class SocketFiPasskeySigner: NSObject, Sendable {
    private var continuation: CheckedContinuation<SocketFiCredential, Error>?
    private var authorizationController: ASAuthorizationController?
    private var activeRequestID: UUID?

    public override init() {}

    public func perform(
        options: SocketFiPasskeyOptions,
        relyingPartyID: String,
        mode: SocketFiAuthMode
    ) async throws -> SocketFiCredential {
        try Task.checkCancellation()
        guard continuation == nil else { throw SocketFiNativeError.authorizationBusy }
        guard let challenge = Data(base64URLEncoded: options.challenge), !challenge.isEmpty else {
            throw SocketFiNativeError.invalidChallenge
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyID
        )
        let request: ASAuthorizationRequest
        if mode == .signUp {
            guard let user = options.user, let userID = Data(base64URLEncoded: user.id),
                  !userID.isEmpty, userID.count <= 64, !user.name.isEmpty else {
                throw SocketFiNativeError.invalidChallenge
            }
            let registration = provider.createCredentialRegistrationRequest(
                challenge: challenge,
                name: user.name,
                userID: userID
            )
            registration.userVerificationPreference = .required
            request = registration
        } else {
            let assertion = provider.createCredentialAssertionRequest(challenge: challenge)
            assertion.userVerificationPreference = .required
            assertion.allowedCredentials = (options.allowCredentials ?? []).compactMap {
                guard let id = Data(base64URLEncoded: $0.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
            request = assertion
        }

        let requestID = UUID()
        activeRequestID = requestID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    self.activeRequestID = nil
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.authorizationController = controller
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.activeRequestID == requestID else { return }
                self?.cancelPendingAuthorization()
            }
        }
    }

    private func cancelPendingAuthorization() {
        authorizationController?.cancel()
        finish(.failure(SocketFiNativeError.authenticationCancelled))
    }

    private func finish(_ result: Result<SocketFiCredential, Error>) {
        activeRequestID = nil
        let pending = continuation
        continuation = nil
        authorizationController = nil
        pending?.resume(with: result)
    }
}

extension SocketFiPasskeySigner: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard controller === authorizationController else { return }
        if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
           let attestationObject = registration.rawAttestationObject {
            let id = registration.credentialID.base64URLEncodedString
            finish(.success(.registration(.init(
                id: id,
                rawId: id,
                response: .init(
                    clientDataJSON: registration.rawClientDataJSON.base64URLEncodedString,
                    attestationObject: attestationObject.base64URLEncodedString
                )
            ))))
            return
        }
        if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let id = assertion.credentialID.base64URLEncodedString
            finish(.success(.assertion(.init(
                id: id,
                rawId: id,
                response: .init(
                    clientDataJSON: assertion.rawClientDataJSON.base64URLEncodedString,
                    authenticatorData: assertion.rawAuthenticatorData.base64URLEncodedString,
                    signature: assertion.signature.base64URLEncodedString,
                    userHandle: assertion.userID.base64URLEncodedString
                )
            ))))
            return
        }
        finish(.failure(SocketFiNativeError.unsupportedCredential))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        guard controller === authorizationController else { return }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            finish(.failure(SocketFiNativeError.authenticationCancelled))
        } else {
            finish(.failure(error))
        }
    }
}

extension SocketFiPasskeySigner: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

public struct SocketFiPasskeyOptions: Decodable, Sendable {
    public struct User: Decodable, Sendable {
        public let id: String
        public let name: String
        public let displayName: String
    }

    public struct Credential: Decodable, Sendable {
        public let id: String
    }

    public let challenge: String
    public let user: User?
    public let allowCredentials: [Credential]?
}

public enum SocketFiCredential: Sendable {
    case registration(SocketFiRegistrationCredential)
    case assertion(SocketFiAssertionCredential)
}

public struct SocketFiRegistrationCredential: Encodable, Sendable {
    public struct Response: Encodable, Sendable {
        public let clientDataJSON: String
        public let attestationObject: String
        public let transports = ["internal"]
    }
    public let id: String
    public let rawId: String
    public let type = "public-key"
    public let response: Response
    public let authenticatorAttachment = "platform"
}

public struct SocketFiAssertionCredential: Encodable, Sendable {
    public struct Response: Encodable, Sendable {
        public let clientDataJSON: String
        public let authenticatorData: String
        public let signature: String
        public let userHandle: String
    }
    public let id: String
    public let rawId: String
    public let type = "public-key"
    public let response: Response
    public let authenticatorAttachment = "platform"
}
