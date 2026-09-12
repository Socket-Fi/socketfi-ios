import Foundation
import SocketFiNativeKit
import CryptoSwift

struct SocketFiCctpChain: Codable, Identifiable, Equatable {
    var id: Int { chainId }
    let chainId: Int
    let domain: Int
    let label: String
    let network: SocketFiNetwork
    let nativeSymbol: String?
    let usdc: String
    let tokenMessengerV2: String
    let explorerTxUrl: String
}

struct SocketFiCctpPrepared: Codable {
    let sessionId: String
    let expiresAt: String
    let source: SocketFiCctpChain
    let network: SocketFiNetwork
    let sender: String
    let recipient: String
    let amount: String
    let maxFee: String
    let minFinalityThreshold: Int
    let destinationDomain: Int
    let mintRecipient: String
    let destinationCaller: String
    let hookData: String
    let stellarForwarder: String
    let eta: String
    var expiry: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
    }

    func validate(chain: SocketFiCctpChain, sender: String, recipient: String, amount: String, speed: String) throws {
        guard UUID(uuidString: sessionId) != nil, source == chain, network == chain.network,
              self.sender.lowercased() == sender.lowercased(), self.recipient == recipient,
              self.amount == (try SocketFiAmount.atomic(amount, decimals: 6)), self.amount != "0",
              (try SocketFiAmount.normalized(maxFee)) == maxFee, SocketFiAmount.greater(self.amount, than: maxFee),
              minFinalityThreshold == (speed == "FAST" ? 1000 : 2000), destinationDomain == 27,
              let expiry, expiry > Date(), SocketFiXDR.isAddress(stellarForwarder, contractOnly: true),
              SocketFiCctpABI.isAddress(source.usdc), SocketFiCctpABI.isAddress(source.tokenMessengerV2),
              let forwarderXDR = Data(base64Encoded: try SocketFiXDR.address(stellarForwarder)),
              mintRecipient.lowercased() == "0x" + forwarderXDR.suffix(32).toHexString(),
              destinationCaller.lowercased() == mintRecipient.lowercased(),
              hookData.lowercased() == "0x" + (try SocketFiCctpABI.word("56")) + Data(recipient.utf8).toHexString()
        else { throw SocketFiNativeError.configuration("The deposit details changed or expired. Review a fresh deposit before approving.") }
    }
}

struct SocketFiCctpStatus: Decodable {
    let sessionId: String
    let network: SocketFiNetwork
    let chainId: Int
    let sender: String
    let recipient: String
    let status: String
    let burnTxHash: String?
    let stellarTxHash: String?
}

struct SocketFiCctpReadiness: Decodable {
    let sessionId: String
    let network: SocketFiNetwork
    let chainId: Int
    let sender: String
    let balance: String
    let allowance: String
    let gasBalance: String
    let gasRequired: String
}

/// Encode only the two reviewed CCTP operations. The API cannot supply arbitrary calldata.
enum SocketFiCctpABI {
    static func isAddress(_ value: String) -> Bool { value.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func isHash(_ value: String) -> Bool { value.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
    static func word(_ decimal: String) throws -> String {
        // Native amounts deliberately stay within the account's i128 range.
        guard let xdr = Data(base64Encoded: try SocketFiXDR.integer(decimal, unsigned: true)) else { throw SocketFiNativeError.invalidResponse }
        return String(repeating: "0", count: 32) + xdr.suffix(16).toHexString()
    }
    static func approve(_ prepared: SocketFiCctpPrepared) throws -> String {
        guard isAddress(prepared.source.tokenMessengerV2) else { throw SocketFiNativeError.invalidResponse }
        return "0x095ea7b3" + String(repeating: "0", count: 24) + prepared.source.tokenMessengerV2.dropFirst(2).lowercased() + (try word(prepared.amount))
    }
    static func burn(_ prepared: SocketFiCctpPrepared) throws -> String {
        let signature = "depositForBurnWithHook(uint256,uint32,bytes32,address,bytes32,uint256,uint32,bytes)"
        let digest = SHA3(variant: .keccak256).calculate(for: Array(signature.utf8))
        let selector = Array(digest[0..<4]).toHexString()
        guard isAddress(prepared.source.usdc), isHash(prepared.mintRecipient), isHash(prepared.destinationCaller),
              prepared.hookData.range(of: "^0x(?:[0-9a-fA-F]{2}){88}$", options: .regularExpression) != nil else { throw SocketFiNativeError.invalidResponse }
        let head = try word(prepared.amount) + word(String(prepared.destinationDomain)) + prepared.mintRecipient.dropFirst(2) +
            String(repeating: "0", count: 24) + prepared.source.usdc.dropFirst(2) + prepared.destinationCaller.dropFirst(2) +
            word(prepared.maxFee) + word(String(prepared.minFinalityThreshold)) + word("256")
        let tail = try word("88") + prepared.hookData.dropFirst(2) + String(repeating: "0", count: 16)
        return "0x" + selector + head.lowercased() + tail.lowercased()
    }
}

@MainActor
protocol SocketFiCctpServicing {
    func chains() async throws -> [SocketFiCctpChain]
    func prepare(chain: SocketFiCctpChain, sender: String, amount: String, speed: String, idempotencyKey: String) async throws -> SocketFiCctpPrepared
    func readiness(_ prepared: SocketFiCctpPrepared) async throws -> SocketFiCctpReadiness
    func status(_ prepared: SocketFiCctpPrepared, burnHash: String?) async throws -> SocketFiCctpStatus
}

@MainActor
struct SocketFiCctpClient: SocketFiCctpServicing {
    private struct Envelope<T: Decodable>: Decodable { let success: Bool; let data: T }
    private struct ChainList: Decodable { let network: SocketFiNetwork; let chains: [SocketFiCctpChain] }
    private struct Input: Encodable {
        let network: SocketFiNetwork
        let walletAddress: String
        let applicationId: String
        let platform = "ios"
        var chainId: Int?
        var sender: String?
        var amount: String?
        var speed: String?
        var idempotencyKey: String?
        var sessionId: String?
        var burnTxHash: String?
    }
    let configuration: SocketFiConfiguration
    let session: SocketFiSession
    private var input: Input { Input(network: session.account.network, walletAddress: session.account.address, applicationId: configuration.applicationID) }
    private func call<T: Decodable>(_ action: String, input: Input, type: T.Type) async throws -> T {
        guard !session.isExpired, session.account.network == configuration.network else { throw SocketFiNativeError.sessionUnavailable }
        let result = try await SocketFiAPIClient(configuration: configuration).post("api/wallet/cctp/" + action, body: input, bearerToken: session.accessToken, response: Envelope<T>.self)
        guard result.success else { throw SocketFiNativeError.invalidResponse }
        return result.data
    }
    func chains() async throws -> [SocketFiCctpChain] {
        let result = try await call("chains", input: input, type: ChainList.self)
        guard result.network == configuration.network, !result.chains.isEmpty,
              Set(result.chains.map(\.chainId)).count == result.chains.count,
              result.chains.allSatisfy({ $0.network == configuration.network && $0.chainId > 0 && SocketFiCctpABI.isAddress($0.usdc) && SocketFiCctpABI.isAddress($0.tokenMessengerV2) }) else { throw SocketFiNativeError.invalidResponse }
        return result.chains
    }
    func prepare(chain: SocketFiCctpChain, sender: String, amount: String, speed: String, idempotencyKey: String) async throws -> SocketFiCctpPrepared {
        var body = input
        body.chainId = chain.chainId; body.sender = sender; body.amount = amount; body.speed = speed; body.idempotencyKey = idempotencyKey
        let prepared = try await call("prepare", input: body, type: SocketFiCctpPrepared.self)
        try prepared.validate(chain: chain, sender: sender, recipient: session.account.address, amount: amount, speed: speed)
        return prepared
    }
    func readiness(_ prepared: SocketFiCctpPrepared) async throws -> SocketFiCctpReadiness {
        var body = input; body.sessionId = prepared.sessionId
        let result = try await call("readiness", input: body, type: SocketFiCctpReadiness.self)
        guard result.sessionId == prepared.sessionId, result.network == prepared.network, result.chainId == prepared.source.chainId,
              result.sender.lowercased() == prepared.sender.lowercased(),
              [result.balance, result.allowance, result.gasBalance, result.gasRequired].allSatisfy({ $0.range(of: "^(0|[1-9][0-9]{0,77})$", options: .regularExpression) != nil }) else { throw SocketFiNativeError.invalidResponse }
        return result
    }
    func status(_ prepared: SocketFiCctpPrepared, burnHash: String? = nil) async throws -> SocketFiCctpStatus {
        var body = input; body.sessionId = prepared.sessionId; body.burnTxHash = burnHash
        let result = try await call(burnHash == nil ? "status" : "settle", input: body, type: SocketFiCctpStatus.self)
        guard result.sessionId == prepared.sessionId, result.network == prepared.network, result.chainId == prepared.source.chainId,
              result.recipient == session.account.address, result.sender.lowercased() == prepared.sender.lowercased(),
              result.burnTxHash == nil || SocketFiCctpABI.isHash(result.burnTxHash!),
              result.status != "SUCCESS" || result.stellarTxHash?.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { throw SocketFiNativeError.invalidResponse }
        return result
    }
}
