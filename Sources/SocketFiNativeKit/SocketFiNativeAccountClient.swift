import Foundation

@MainActor
public final class SocketFiNativeAccountClient {
    private let configuration: SocketFiConfiguration
    private let api: SocketFiAPIClient
    private let passkey: SocketFiPasskeySigner
    private let sessionStore: SocketFiSessionStore
    private var isAuthenticating = false

    public init(
        configuration: SocketFiConfiguration,
        passkey: SocketFiPasskeySigner = SocketFiPasskeySigner(),
        sessionStore: SocketFiSessionStore? = nil
    ) {
        self.configuration = configuration
        self.api = SocketFiAPIClient(configuration: configuration)
        self.passkey = passkey
        self.sessionStore = sessionStore ?? SocketFiSessionStore(
            service: "fi.socket.socketfi.\(configuration.applicationID).\(configuration.clientID).\(configuration.network.rawValue).\(configuration.relyingPartyID)"
        )
    }

    public func restoreSession() async throws -> SocketFiSession? {
        guard let session = try await sessionStore.load() else { return nil }
        guard !session.isExpired else {
            await sessionStore.clear()
            return nil
        }
        guard session.account.network == configuration.network else {
            await sessionStore.clear()
            return nil
        }
        return session
    }

    public func authenticate(
        method: SocketFiSignInMethod,
        mode: SocketFiAuthMode,
        username: String? = nil
    ) async throws -> SocketFiSession {
        try Task.checkCancellation()
        guard !isAuthenticating else { throw SocketFiNativeError.authorizationBusy }
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard method == .passkey else {
            // These methods are deliberately visible in the app but are not
            // silently routed through the passkey endpoint.
            throw SocketFiNativeError.configuration(
                "\(method.rawValue) native signing is not enabled in this build."
            )
        }

        let started: NativeAuthStartResponse = try await api.post(
            "api/native/auth/start",
            body: NativeAuthStartRequest(
                clientId: configuration.clientID,
                applicationId: configuration.applicationID,
                network: configuration.network.rawValue,
                mode: mode.rawValue,
                username: username
            ),
            response: NativeAuthStartResponse.self
        )
        guard started.data.rpId == configuration.relyingPartyID,
              !started.data.tempAccess.isEmpty else {
            throw SocketFiNativeError.configuration("The server passkey domain does not match this app's configuration.")
        }
        try Task.checkCancellation()
        let optionsResponse: NativeAuthOptionsResponse = try await api.post(
            "oauth/init-auth",
            body: NativeAuthOptionsRequest(
                tempAccess: started.data.tempAccess,
                clientId: configuration.clientID,
                mode: mode.rawValue
            ),
            response: NativeAuthOptionsResponse.self
        )

        let firstCredential = try await passkey.perform(
            options: optionsResponse.options,
            relyingPartyID: started.data.rpId,
            mode: mode
        )
        var verified = try await verify(
            credential: firstCredential,
            tempAccess: started.data.tempAccess,
            mode: mode
        )

        if verified.createPopAccess == true {
            guard let followUpOptions = verified.options else { throw SocketFiNativeError.invalidResponse }
            let proof = try await passkey.perform(
                options: followUpOptions,
                relyingPartyID: started.data.rpId,
                mode: .signIn
            )
            verified = try await verify(
                credential: proof,
                tempAccess: started.data.tempAccess,
                mode: mode,
                path: "oauth/create-wallet"
            )
        }

        guard verified.verified == true,
              let payload = verified.session,
              let address = payload.address?[configuration.network.rawValue],
              !address.isEmpty,
              !payload.socketfiAccessToken.isEmpty else {
            throw SocketFiNativeError.invalidResponse
        }

        let session = SocketFiSession(
            account: SocketFiAccount(
                address: address,
                network: configuration.network,
                signer: .passkey
            ),
            accessToken: payload.socketfiAccessToken,
            expiresAt: TokenExpiry.date(from: payload.socketfiAccessToken)
                ?? Date().addingTimeInterval(3_600)
        )
        try Task.checkCancellation()
        try await sessionStore.save(session)
        return session
    }

    public func signOut() async {
        await sessionStore.clear()
    }

    public func authorizePasskeyTransaction(
        _ request: SocketFiTransactionRequest,
        onSubmission: @escaping @MainActor () -> Void = {},
        confirmReview: @escaping @MainActor (SocketFiTransactionReview) async -> Bool
    ) async throws -> SocketFiTransactionResult {
        guard !isAuthenticating else { throw SocketFiNativeError.authorizationBusy }
        isAuthenticating = true
        defer { isAuthenticating = false }
        try Task.checkCancellation()
        guard let session = try await restoreSession() else {
            throw SocketFiNativeError.sessionUnavailable
        }
        guard request.review.network == configuration.network,
              request.review.source == session.account.address,
              request.review.expiresAt > Date() else {
            throw SocketFiNativeError.invalidResponse
        }
        guard await confirmReview(request.review) else {
            throw SocketFiNativeError.transactionCancelled
        }
        guard request.review.expiresAt > Date() else { throw SocketFiNativeError.invalidResponse }
        try Task.checkCancellation()

        let started: NativeTransactionStartResponse = try await api.post(
            "api/native/transactions/start",
            body: NativeTransactionStartRequest(
                clientId: configuration.clientID,
                applicationId: configuration.applicationID,
                network: configuration.network.rawValue,
                contractID: request.contractID,
                functionName: request.functionName,
                argsXDR: request.argsXDR
            ),
            bearerToken: session.accessToken,
            response: NativeTransactionStartResponse.self
        )
        let initialized: NativeTransactionInitResponse = try await api.post(
            "api/tx/transaction-intents/init",
            body: NativeTransactionInitRequest(
                txSession: started.txSession,
                clientId: configuration.clientID
            ),
            response: NativeTransactionInitResponse.self
        )
        guard request.review.expiresAt > Date() else {
            throw SocketFiNativeError.configuration("The request expired while preparing. Go back for a fresh review.")
        }
        let credential = try await passkey.perform(
            options: initialized.options,
            relyingPartyID: configuration.relyingPartyID,
            mode: .signIn
        )
        guard case let .assertion(assertion) = credential else {
            throw SocketFiNativeError.unsupportedCredential
        }
        guard request.review.expiresAt > Date() else {
            throw SocketFiNativeError.configuration("This request expired. Review a fresh request before signing again.")
        }
        try Task.checkCancellation()
        let path = request.submit
            ? "api/tx/transaction-intents/sign-and-submit"
            : "api/tx/transaction-intents/sign"
        if request.submit { onSubmission() }
        let result: NativeTransactionResult
        do {
            result = try await api.post(
                path,
                body: NativeTransactionSignRequest(txSession: started.txSession, sigData: assertion),
                response: NativeTransactionResult.self
            )
        } catch {
            // A timeout, decoding error, or even a server error can occur after broadcast.
            // Never automatically retry an operation whose outcome is unknown.
            if request.submit { throw SocketFiNativeError.submissionUncertain(hash: nil) }
            throw error
        }
        guard result.success else {
            if request.submit { throw SocketFiNativeError.submissionUncertain(hash: nil) }
            throw SocketFiNativeError.invalidResponse
        }
        if request.submit {
            return try SocketFiTransactionResult.confirmedSubmission(hash: result.data?.txHash, status: result.data?.status)
        }
        return SocketFiTransactionResult(
            id: result.data?.txHash ?? started.txSession,
            submitted: request.submit
        )
    }

    private func verify(
        credential: SocketFiCredential,
        tempAccess: String,
        mode: SocketFiAuthMode,
        path: String = "oauth/verify-auth"
    ) async throws -> NativeVerifyResponse {
        switch credential {
        case let .registration(value):
            return try await api.post(
                path,
                body: NativeVerifyRequest(
                    tempAccess: tempAccess,
                    clientId: configuration.clientID,
                    mode: mode.rawValue,
                    authData: value
                ),
                response: NativeVerifyResponse.self
            )
        case let .assertion(value):
            return try await api.post(
                path,
                body: NativeVerifyRequest(
                    tempAccess: tempAccess,
                    clientId: configuration.clientID,
                    mode: mode.rawValue,
                    authData: value
                ),
                response: NativeVerifyResponse.self
            )
        }
    }
}

private struct NativeAuthStartRequest: Encodable {
    let clientId: String
    let applicationId: String
    let platform = "ios"
    let network: String
    let mode: String
    let username: String?
}

private struct NativeAuthStartResponse: Decodable {
    struct Data: Decodable {
        let tempAccess: String
        let rpId: String
    }
    let data: Data
}

private struct NativeAuthOptionsRequest: Encodable {
    let tempAccess: String
    let clientId: String
    let mode: String
}

private struct NativeAuthOptionsResponse: Decodable {
    let options: SocketFiPasskeyOptions
    let createPopAccess: Bool?
}

private struct NativeSessionPayload: Decodable {
    let socketfiAccessToken: String
    let address: [String: String]?
    let username: String?
}

private struct NativeVerifyResponse: Decodable {
    let verified: Bool?
    let options: SocketFiPasskeyOptions?
    let createPopAccess: Bool?
    let session: NativeSessionPayload?
}

private struct NativeVerifyRequest<Credential: Encodable>: Encodable {
    let tempAccess: String
    let clientId: String
    let mode: String
    let authData: Credential
}

private struct NativeTransactionStartRequest: Encodable {
    struct CallFunction: Encodable { let name: String }
    let clientId: String
    let applicationId: String
    let platform = "ios"
    let network: String
    let contractID: String
    let functionName: String
    let argsXDR: [String]

    enum CodingKeys: String, CodingKey {
        case clientId, applicationId, platform, network, contractID = "contractId"
        case callFunction, argsXDR = "argsXdr"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientId, forKey: .clientId)
        try container.encode(applicationId, forKey: .applicationId)
        try container.encode(platform, forKey: .platform)
        try container.encode(network, forKey: .network)
        try container.encode(contractID, forKey: .contractID)
        try container.encode(CallFunction(name: functionName), forKey: .callFunction)
        try container.encode(argsXDR, forKey: .argsXDR)
    }
}

private struct NativeTransactionStartResponse: Decodable {
    let txSession: String
}

private struct NativeTransactionInitRequest: Encodable {
    let txSession: String
    let clientId: String
}

private struct NativeTransactionInitResponse: Decodable {
    let options: SocketFiPasskeyOptions
}

private struct NativeTransactionSignRequest: Encodable {
    let txSession: String
    let sigData: SocketFiAssertionCredential
}

private struct NativeTransactionResult: Decodable {
    struct Payload: Decodable { let txHash: String?; let status: String? }
    let success: Bool
    let data: Payload?
}

private enum TokenExpiry {
    static func date(from token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payload = Data(base64URLEncoded: String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let seconds = object["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
