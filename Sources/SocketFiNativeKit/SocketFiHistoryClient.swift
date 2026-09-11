import Foundation

public struct SocketFiHistoryItem: Decodable, Identifiable, Sendable {
    public let id: String
    public let network: SocketFiNetwork
    public let walletAddress: String
    public let txHash: String
    public let ledger: String
    public let ledgerClosedAt: String?
    public let status: String
    public let successful: Bool
    public let actionType: String
    public let functionName: String?
    public let invokedContract: String?
    public let assetContract: String?
    public let assetSymbol: String?
    public let assetDecimals: Int?
    public let amountAtomic: String?
    public let direction: String?
    public let fromAddress: String?
    public let toAddress: String?
    public let counterparty: String?
    public let feeChargedStroops: String?
    public let memoType: String?
    public let memoValue: String?

    public var date: Date? { ledgerClosedAt.flatMap(SocketFiWalletClient.date) }
    public var symbol: String {
        let value = assetSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.uppercased() == "UNKNOWN" { return "" }
        return value.lowercased() == "native" ? "XLM" : value
    }
    public var amountText: String? {
        guard let amountAtomic else { return nil }
        // String arithmetic preserves every digit, including amounts above 2^53.
        // Unusual metadata never hides the asset or invents decimal precision.
        guard let decimals = assetDecimals, (0...38).contains(decimals),
              let digits = try? SocketFiAmount.normalized(amountAtomic) else {
            return "\(amountAtomic) atomic units"
        }
        guard decimals > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -decimals)
        let fraction = padded[split...].reversed().drop(while: { $0 == "0" }).reversed()
        return String(padded[..<split]) + (fraction.isEmpty ? "" : "." + String(fraction))
    }
    public var title: String {
        switch actionType {
        case "TRANSFER", "RECEIVE", "WITHDRAW", "DEPOSIT":
            switch direction {
            case "incoming", "IN": return "Received"
            case "outgoing", "OUT": return "Sent"
            case "self", "SELF": return "Self transfer"
            default: return "Transfer"
            }
        case "SWAP": return "Swap"
        case "ACCOUNT_CREATE": return "Account created"
        case "SESSION_CREATE": return "Session created"
        case "SESSION_REVOKE": return "Session revoked"
        case "APPROVE": return "Token approval"
        case "RECOVERY": return "Account recovery"
        case "GUARDIAN": return "Guardian update"
        case "PAUSE": return "Account paused"
        case "UNPAUSE": return "Account unpaused"
        default: return functionName?.isEmpty == false ? functionName! : "Contract activity"
        }
    }
    public var explorerURL: URL {
        URL(string: "https://stellar.expert/explorer/\(network == .testnet ? "testnet" : "public")/tx/\(txHash)")!
    }
}

public struct SocketFiHistoryPage: Decodable, Sendable {
    public let success: Bool
    public let network: SocketFiNetwork
    public let walletAddress: String
    public let count: Int
    public let hasMore: Bool
    public let nextCursor: String?
    public let transactions: [SocketFiHistoryItem]

    public func validate(session: SocketFiSession, cursor: String?, limit: Int) throws {
        guard success, network == session.account.network, walletAddress == session.account.address,
              count == transactions.count, count <= limit,
              Set(transactions.map(\.id)).count == count,
              hasMore ? (count > 0 && Self.validCursor(nextCursor) && nextCursor != cursor) : nextCursor == nil,
              transactions.allSatisfy({ item in
                  !item.id.isEmpty && item.id.count <= 200 && item.network == network && item.walletAddress == walletAddress &&
                  item.txHash.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil &&
                  ["SUCCESS", "FAILED"].contains(item.status) && item.successful == (item.status == "SUCCESS") &&
                  item.ledger.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil &&
                  (item.amountAtomic == nil || item.amountAtomic!.range(of: "^[0-9]{1,78}$", options: .regularExpression) != nil)
              }) else { throw SocketFiNativeError.invalidResponse }
    }
    public static func validCursor(_ cursor: String?) -> Bool {
        guard let cursor else { return false }
        return cursor.range(of: "^[A-Za-z0-9_-]{1,1024}$", options: .regularExpression) != nil
    }
}

@MainActor
public struct SocketFiHistoryClient {
    private let configuration: SocketFiConfiguration
    private let api: SocketFiAPIClient
    public init(configuration: SocketFiConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        api = SocketFiAPIClient(configuration: configuration, session: urlSession)
    }
    public func load(session: SocketFiSession, cursor: String? = nil) async throws -> SocketFiHistoryPage {
        guard !session.isExpired, session.account.network == configuration.network,
              SocketFiXDR.isAddress(session.account.address, contractOnly: true) else { throw SocketFiNativeError.sessionUnavailable }
        if let cursor, !SocketFiHistoryPage.validCursor(cursor) { throw SocketFiNativeError.invalidResponse }
        var query = ["network": configuration.network.rawValue, "walletAddress": session.account.address,
                     "applicationId": configuration.applicationID, "platform": "ios", "limit": "25"]
        query["cursor"] = cursor
        let page = try await api.get("api/wallet/history", query: query, bearerToken: session.accessToken, response: SocketFiHistoryPage.self)
        try Task.checkCancellation()
        try page.validate(session: session, cursor: cursor, limit: 25)
        return page
    }
}
