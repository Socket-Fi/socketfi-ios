import Foundation

@MainActor
public enum SocketFiWalletTransactions {
    public static func addGuardian(session: SocketFiSession, guardian: String,
                                   capabilities: SocketFiProjectCapabilities) throws -> SocketFiTransactionRequest {
        let address = guardian.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isExpired else { throw SocketFiNativeError.sessionUnavailable }
        guard SocketFiXDR.isAddress(address), address != session.account.address else {
            throw SocketFiNativeError.configuration("Enter a valid Stellar guardian address different from your wallet.")
        }
        guard capabilities.allows(network: session.account.network, contract: session.account.address,
                                  function: "add_guardian", account: session.account.address) else {
            throw SocketFiNativeError.configuration("Adding guardians is not enabled for this app on this network yet.")
        }
        return SocketFiTransactionRequest(contractID: session.account.address, functionName: "add_guardian",
            argsXDR: [try SocketFiXDR.address(address)], review: SocketFiTransactionReview(
                title: "Add guardian", network: session.account.network, source: session.account.address,
                destination: address, expiresAt: Date().addingTimeInterval(120)))
    }

    public static func withdrawal(session: SocketFiSession, token: SocketFiToken, recipient: String, amount: String,
                                  capabilities: SocketFiProjectCapabilities) throws -> SocketFiTransactionRequest {
        let destination = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isExpired else { throw SocketFiNativeError.sessionUnavailable }
        guard SocketFiXDR.isAddress(destination), destination != session.account.address else {
            throw SocketFiNativeError.configuration("Enter a valid recipient address different from your account.")
        }
        guard capabilities.allows(network: session.account.network, contract: token.contract, function: "transfer") else {
            throw SocketFiNativeError.configuration("Withdrawals for this asset are not enabled for this app yet.")
        }
        let atomic = try SocketFiWalletClient.spendAmount(amount, token: token)
        return SocketFiTransactionRequest(contractID: token.contract, functionName: "transfer", argsXDR: [
            try SocketFiXDR.address(session.account.address), try SocketFiXDR.address(destination), try SocketFiXDR.integer(atomic)
        ], review: SocketFiTransactionReview(
            title: "Withdraw \(token.symbol)", network: session.account.network,
            source: session.account.address, destination: destination,
            amount: "\(SocketFiAmount.display(atomic, decimals: token.decimals)) \(token.symbol)",
            expiresAt: Date().addingTimeInterval(120)
        ))
    }

    public static func swap(session: SocketFiSession, from: SocketFiToken, to: SocketFiToken, amount: String,
                            slippageBps: Int, quote: SocketFiSwapQuote,
                            capabilities: SocketFiProjectCapabilities) throws -> SocketFiTransactionRequest {
        guard !session.isExpired else { throw SocketFiNativeError.sessionUnavailable }
        let atomic = try SocketFiWalletClient.spendAmount(amount, token: from)
        try quote.validate(network: session.account.network, tokenIn: from.contract, tokenOut: to.contract,
                           amount: atomic, slippageBps: slippageBps)
        guard capabilities.allows(network: session.account.network, contract: quote.routerContractId, function: "swap_chained"),
              let expiry = quote.expiry else {
            throw SocketFiNativeError.configuration("Swaps are not enabled for this app on this network yet.")
        }
        return SocketFiTransactionRequest(contractID: quote.routerContractId, functionName: "swap_chained", argsXDR: [
            try SocketFiXDR.address(session.account.address), quote.swapChainXdr,
            try SocketFiXDR.address(quote.tokenIn), try SocketFiXDR.integer(atomic, unsigned: true),
            try SocketFiXDR.integer(quote.minimumOutAtomic, unsigned: true)
        ], review: SocketFiTransactionReview(
            title: "Swap \(from.symbol) to \(to.symbol)", network: session.account.network,
            source: session.account.address, destination: quote.routerContractId,
            amount: "\(SocketFiAmount.display(atomic, decimals: from.decimals)) \(from.symbol)",
            minimumReceived: "\(SocketFiAmount.display(quote.minimumOutAtomic, decimals: to.decimals)) \(to.symbol)",
            slippage: "\(SocketFiAmount.display(String(slippageBps), decimals: 2))%",
            expiresAt: expiry
        ))
    }
}
