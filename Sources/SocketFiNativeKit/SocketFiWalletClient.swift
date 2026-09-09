import Foundation

public struct SocketFiToken: Decodable, Identifiable, Sendable {
    public var id: String { contract }
    public let contract: String
    public let symbol: String
    public let decimals: Int
    public let atomicBalance: String?
    public let balanceStatus: String
    public let price: Price?

    public struct Price: Decodable, Sendable {
        public let selectedPrice: Decimal?
        public let status: String?

        enum CodingKeys: String, CodingKey { case selectedPrice, status }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            if let text = try? container.decode(String.self, forKey: .selectedPrice) {
                selectedPrice = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
            } else { selectedPrice = try? container.decode(Decimal.self, forKey: .selectedPrice) }
        }
    }

    public var availableBalance: String? {
        guard balanceStatus == "fresh", (0...18).contains(decimals),
              let atomicBalance else { return nil }
        return try? SocketFiAmount.normalized(atomicBalance)
    }
    public var balanceText: String {
        availableBalance.map { SocketFiAmount.display($0, decimals: decimals) } ?? "—"
    }
    public var estimatedValue: Decimal? {
        guard let balance = availableBalance else { return nil }
        if balance == "0" { return 0 }
        guard price?.status != "unavailable", let unitPrice = price?.selectedPrice,
              unitPrice > 0, let amount = Decimal(string: balanceText, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return amount * unitPrice
    }
}

public struct SocketFiWalletSnapshot: Decodable, Sendable {
    public let success: Bool
    public let network: SocketFiNetwork
    public let walletAddress: String
    public let tokens: [SocketFiToken]
    public let fetchedAt: String

    public var estimatedTotal: Decimal? {
        var total: Decimal = 0
        for token in tokens {
            guard let value = token.estimatedValue else { return nil }
            total += value
        }
        return total
    }
}

public struct SocketFiProjectCapabilities: Decodable, Sendable {
    public struct Invocation: Decodable, Sendable {
        public let network: SocketFiNetwork
        public let contractId: String
        public let functions: [String]
    }
    public let clientId: String
    public let networks: [SocketFiNetwork]
    public let allowedInvocations: [Invocation]

    public func allows(network: SocketFiNetwork, contract: String, function: String) -> Bool {
        networks.contains(network) && allowedInvocations.contains {
            $0.network == network && $0.contractId == contract && $0.functions.contains(function)
        }
    }
}

public struct SocketFiSwapQuote: Decodable, Sendable {
    public let network: SocketFiNetwork
    public let routerContractId: String
    public let tokenIn: String
    public let tokenOut: String
    public let amountInAtomic: String
    public let quotedOutAtomic: String
    public let minimumOutAtomic: String
    public let swapChainXdr: String
    public let pools: [String]
    public let slippageBps: Int
    public let expiresAt: String

    public var expiry: Date? { SocketFiWalletClient.date(expiresAt) }

    public func validate(network: SocketFiNetwork, tokenIn: String, tokenOut: String, amount: String, slippageBps: Int) throws {
        guard self.network == network, self.tokenIn == tokenIn, self.tokenOut == tokenOut,
              tokenIn != tokenOut, amountInAtomic == amount, self.slippageBps == slippageBps,
              (1...500).contains(slippageBps), let expiry, expiry > Date(),
              SocketFiXDR.isAddress(routerContractId, contractOnly: true),
              let chain = Data(base64Encoded: swapChainXdr), !chain.isEmpty, chain.count <= 65_536,
              !pools.isEmpty, pools.count <= 10 else { throw SocketFiNativeError.invalidResponse }
        let output = try SocketFiAmount.normalized(quotedOutAtomic)
        let minimum = try SocketFiAmount.normalized(minimumOutAtomic)
        guard minimum != "0", !SocketFiAmount.greater(minimum, than: output) else {
            throw SocketFiNativeError.invalidResponse
        }
        // Reject a quote whose minimum exceeds the user's chosen slippage tolerance.
        let floor = try SocketFiAmount.minimumOutput(output, slippageBps: slippageBps)
        guard !SocketFiAmount.greater(floor, than: minimum) else {
            throw SocketFiNativeError.configuration("The quote exceeds your slippage limit. Request a new quote.")
        }
    }
}

@MainActor
public struct SocketFiWalletClient {
    private let configuration: SocketFiConfiguration
    private let api: SocketFiAPIClient

    public init(configuration: SocketFiConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.api = SocketFiAPIClient(configuration: configuration, session: session)
    }

    public func load(session: SocketFiSession) async throws -> SocketFiWalletSnapshot {
        guard session.account.network == configuration.network, !session.isExpired else {
            throw SocketFiNativeError.sessionUnavailable
        }
        guard let username = session.walletUsername else {
            throw SocketFiNativeError.configuration("Sign in again to load this account's assets.")
        }
        let snapshot = try await api.get("api/wallet/tokens", query: [
            "network": configuration.network.rawValue,
            "username": username,
            "walletAddress": session.account.address
        ], bearerToken: session.accessToken, response: SocketFiWalletSnapshot.self)
        guard snapshot.success, snapshot.network == configuration.network,
              snapshot.walletAddress == session.account.address,
              Set(snapshot.tokens.map(\.id)).count == snapshot.tokens.count,
              snapshot.tokens.allSatisfy({ SocketFiXDR.isAddress($0.contract, contractOnly: true) && (0...18).contains($0.decimals) }) else {
            throw SocketFiNativeError.invalidResponse
        }
        return snapshot
    }

    public func capabilities() async throws -> SocketFiProjectCapabilities {
        let result = try await api.get(".well-known/socketfi-projects/\(configuration.clientID)", response: Envelope<SocketFiProjectCapabilities>.self)
        guard result.success, result.data.clientId == configuration.clientID,
              result.data.networks.contains(configuration.network) else { throw SocketFiNativeError.invalidResponse }
        return result.data
    }

    public func quote(session: SocketFiSession, from: SocketFiToken, to: SocketFiToken, amount: String, slippageBps: Int) async throws -> SocketFiSwapQuote {
        let atomic = try Self.spendAmount(amount, token: from)
        guard !session.isExpired, session.account.network == configuration.network else { throw SocketFiNativeError.sessionUnavailable }
        let result = try await api.post("api/aquarius-swap/quote", body: QuoteRequest(
            network: configuration.network, walletAddress: session.account.address,
            tokenIn: from.contract, tokenOut: to.contract, amountAtomic: atomic, slippageBps: slippageBps
        ), response: Envelope<SocketFiSwapQuote>.self)
        guard result.success else { throw SocketFiNativeError.invalidResponse }
        try result.data.validate(network: configuration.network, tokenIn: from.contract, tokenOut: to.contract, amount: atomic, slippageBps: slippageBps)
        return result.data
    }

    public static func spendAmount(_ input: String, token: SocketFiToken) throws -> String {
        let atomic = try SocketFiAmount.atomic(input, decimals: token.decimals)
        guard let balance = token.availableBalance else { throw SocketFiNativeError.configuration("Refresh this token's balance before continuing.") }
        guard atomic != "0", !SocketFiAmount.greater(atomic, than: balance) else {
            throw SocketFiNativeError.configuration("Enter an amount above zero and within your available balance.")
        }
        return atomic
    }

    nonisolated public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension SocketFiSession {
    /// Display/read metadata only. Server and contract still verify all authority.
    public var walletUsername: String? {
        let pieces = accessToken.split(separator: ".")
        guard pieces.count == 3, let data = Data(base64URLEncoded: String(pieces[1])),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = claims["username"] as? String, !username.isEmpty else { return nil }
        return username
    }
}

private struct Envelope<T: Decodable>: Decodable { let success: Bool; let data: T }
private struct QuoteRequest: Encodable {
    let network: SocketFiNetwork
    let walletAddress: String
    let tokenIn: String
    let tokenOut: String
    let amountAtomic: String
    let slippageBps: Int
}
