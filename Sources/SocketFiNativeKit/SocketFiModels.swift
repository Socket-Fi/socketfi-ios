import Foundation

public enum SocketFiNetwork: String, Codable, Sendable {
    case testnet = "TESTNET"
    case `public` = "PUBLIC"
}

public enum SocketFiSignInMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case passkey
    case evmWallet = "evm_wallet"
    case stellarWallet = "stellar_wallet"
}

public enum SocketFiAuthMode: String, Codable, Sendable {
    case signIn = "signin"
    case signUp = "signup"
}

public struct SocketFiConfiguration: Sendable {
    public let apiBaseURL: URL
    public let clientID: String
    public let applicationID: String
    public let network: SocketFiNetwork
    public let relyingPartyID: String

    public init(
        apiBaseURL: URL,
        clientID: String,
        applicationID: String,
        network: SocketFiNetwork,
        relyingPartyID: String
    ) {
        precondition(apiBaseURL.scheme == "https", "SocketFi requires HTTPS API configuration")
        precondition(!clientID.isEmpty && !applicationID.isEmpty)
        precondition(!relyingPartyID.isEmpty)
        self.apiBaseURL = apiBaseURL
        self.clientID = clientID
        self.applicationID = applicationID
        self.network = network
        self.relyingPartyID = relyingPartyID
    }

    public static func fromInfoPlist(bundle: Bundle = .main) -> SocketFiConfiguration {
        func required(_ key: String) -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fatalError("Missing required SocketFi configuration: \(key)")
            }
            return value
        }
        guard let apiURL = URL(string: required("SocketFiAPIBaseURL")),
              let network = SocketFiNetwork(rawValue: required("SocketFiNetwork")) else {
            fatalError("Invalid SocketFi API URL or network configuration")
        }
        return SocketFiConfiguration(
            apiBaseURL: apiURL,
            clientID: required("SocketFiClientID"),
            applicationID: required("SocketFiApplicationID"),
            network: network,
            relyingPartyID: required("SocketFiRPID")
        )
    }
}

public struct SocketFiAccount: Codable, Equatable, Sendable {
    public let address: String
    public let network: SocketFiNetwork
    public let signer: SocketFiSignInMethod

    public init(address: String, network: SocketFiNetwork, signer: SocketFiSignInMethod) {
        self.address = address
        self.network = network
        self.signer = signer
    }
}

public struct SocketFiSession: Codable, Equatable, Sendable {
    public let account: SocketFiAccount
    public let accessToken: String
    public let expiresAt: Date
    public let evmOwnerAddress: String?
    public let evmWalletSessionTopic: String?

    public init(account: SocketFiAccount, accessToken: String, expiresAt: Date, evmOwnerAddress: String? = nil, evmWalletSessionTopic: String? = nil) {
        self.account = account
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.evmOwnerAddress = evmOwnerAddress
        self.evmWalletSessionTopic = evmWalletSessionTopic
    }

    public var isExpired: Bool { expiresAt <= Date() }
}

public struct SocketFiTransactionReview: Codable, Equatable, Sendable {
    public let title: String
    public let network: SocketFiNetwork
    public let source: String
    public let destination: String
    public let amount: String?
    public let fee: String?
    public let minimumReceived: String?
    public let slippage: String?
    public let expiresAt: Date

    public init(
        title: String,
        network: SocketFiNetwork,
        source: String,
        destination: String,
        amount: String? = nil,
        fee: String? = nil,
        minimumReceived: String? = nil,
        slippage: String? = nil,
        expiresAt: Date
    ) {
        self.title = title
        self.network = network
        self.source = source
        self.destination = destination
        self.amount = amount
        self.fee = fee
        self.minimumReceived = minimumReceived
        self.slippage = slippage
        self.expiresAt = expiresAt
    }
}

public struct SocketFiTransactionRequest: Sendable {
    public let contractID: String
    public let functionName: String
    public let argsXDR: [String]
    public let review: SocketFiTransactionReview
    public let submit: Bool

    public init(
        contractID: String,
        functionName: String,
        argsXDR: [String],
        review: SocketFiTransactionReview,
        submit: Bool = true
    ) {
        self.contractID = contractID
        self.functionName = functionName
        self.argsXDR = argsXDR
        self.review = review
        self.submit = submit
    }
}

public struct SocketFiTransactionResult: Sendable, Equatable {
    public let id: String
    public let submitted: Bool

    public init(id: String, submitted: Bool) {
        self.id = id
        self.submitted = submitted
    }

    public static func confirmedSubmission(hash: String?, status: String?) throws -> SocketFiTransactionResult {
        guard let hash, hash.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }) else {
            throw SocketFiNativeError.submissionUncertain(hash: nil)
        }
        guard status == "SUCCESS" else {
            if status == "FAILED" { throw SocketFiNativeError.transactionFailed(hash: hash) }
            throw SocketFiNativeError.submissionUncertain(hash: hash)
        }
        return SocketFiTransactionResult(id: hash, submitted: true)
    }
}

public enum SocketFiNativeError: LocalizedError, Sendable {
    case configuration(String)
    case authenticationCancelled
    case transactionCancelled
    case authorizationBusy
    case invalidChallenge
    case invalidResponse
    case unsupportedCredential
    case sessionUnavailable
    case submissionUncertain(hash: String?)
    case transactionFailed(hash: String)
    case requestFailed(status: Int, code: String?, message: String)

    public var errorDescription: String? {
        switch self {
        case let .configuration(message): message
        case .authenticationCancelled: "Authentication was cancelled."
        case .transactionCancelled: "The transaction was cancelled before signing."
        case .authorizationBusy: "Another passkey request is already in progress."
        case .invalidChallenge: "SocketFi returned an invalid passkey challenge."
        case .invalidResponse: "SocketFi returned an incomplete response."
        case .unsupportedCredential: "This device returned an unsupported passkey credential."
        case .sessionUnavailable: "Your SocketFi session has expired. Sign in again."
        case .submissionUncertain: "Confirmation is unavailable. The transaction may have been submitted. Check your account activity before making another payment."
        case .transactionFailed: "The network confirmed that this transaction failed. No successful transfer was reported."
        case let .requestFailed(_, _, message): message
        }
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Presentation milestones only; these do not grant account authorization.
public enum SocketFiEvmAuthStage: Equatable, Sendable {
    case connecting, preparing, awaitingSignature, submitting
}
