import Foundation
import Web3
import CryptoSwift
import HDWalletKit
import WalletConnectSigner

/// Crypto primitives required by Reown's WalletConnect verifier.
/// The wallet never receives or stores private key material here; this provider
/// is used only for local address/signature validation by the SDK.
struct SocketFiReownCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        let publicKey = try EthereumPublicKey(
            message: [UInt8](message),
            v: EthereumQuantity(quantity: BigUInt(signature.v)),
            r: EthereumQuantity(signature.r),
            s: EthereumQuantity(signature.s)
        )
        return Data(publicKey.rawPublicKey)
    }

    func keccak256(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: [UInt8](data)))
    }
}
