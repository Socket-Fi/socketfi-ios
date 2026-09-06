import Foundation

@MainActor
public final class SocketFiNativeAccountClient {
    private let configuration: SocketFiConfiguration
    private let api: SocketFiAPIClient
    private let passkey: SocketFiPasskeySigner
    private let sessionStore: SocketFiSessionStore

    public init(
        configuration: SocketFiConfiguration,
        passkey: SocketFiPasskeySigner = SocketFiPasskeySigner(),
        sessionStore: SocketFiSessionStore? = nil
    ) {
        self.configuration = configuration
        self.api = SocketFiAPIClient(configuration: configuration)
        self.passkey = passkey
        self.sessionStore = sessionStore ?? SocketFiSessionStore(
            service: "fi.socket.socketfi.\(configuration.network.rawValue.lowercased())"
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
        guard method == .passkey else {
            // These methods are deliberately visible in the app but are not
            // silently routed through the passkey endpoint.
            throw SocketFiNativeError.configuration(
                "(method.rawValue) native signing is not enabled in this build."
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

        if verified.createPopAccess == true, let followUpOptions = verified.options {
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

        guard let payload = verified.session,
              let address = payload.address?[configuration.network.rawValue],
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
                ?? Date().addingTimeInterval(900)
        )
        try await sessionStore.save(session)
        return session
    }

    public func signOut() async {
        await sessionStore.clear()
    }

    public func authorizePasskeyTransaction(
        _ request: SocketFiTransactionRequest,
        confirmReview: @escaping @MainActor (SocketFiTransactionReview) async -> Bool
    ) async throws -> SocketFiTransactionResult {
        guard let session = try await restoreSession() else {
            throw SocketFiNativeError.sessionUnavailable
        }
        guard request.review.network == configuration.network,
              request.review.expiresAt > Date() else {
            throw SocketFiNativeError.invalidResponse
        }
        guard await confirmReview(request.review) else {
            throw SocketFiNativeError.transactionCancelled
        }

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
        let credential = try await passkey.perform(
            options: initialized.options,
            relyingPartyID: configuration.relyingPartyID,
            mode: .signIn
        )
        guard case let .assertion(assertion) = credential else {
            throw SocketFiNativeError.unsupportedCredential
        }
        let path = request.submit
            ? "api/tx/transaction-intents/sign-and-submit"
            : "api/tx/transaction-intents/sign"
        let result: NativeTransactionResult = try await api.post(
            path,
            body: NativeTransactionSignRequest(txSession: started.txSession, sigData: assertion),
            response: NativeTransactionResult.self
        )
        guard result.success else { throw SocketFiNativeError.invalidResponse }
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
    struct Payload: Decodable { let txHash: String? }
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
