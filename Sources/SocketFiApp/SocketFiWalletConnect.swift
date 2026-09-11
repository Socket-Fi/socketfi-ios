import Foundation
@preconcurrency import ReownAppKit
import WalletConnectNetworking
import WalletConnectRelay
import Starscream

#if canImport(UIKit)
import UIKit
#endif

extension WebSocket: WebSocketConnecting {}

/// Owns the one-time Reown/AppKit setup used by the native EVM sign-in flow.
@MainActor
final class SocketFiWalletConnect {
    static let shared = SocketFiWalletConnect()
    private var configured = false

    private init() {}

    func configure(projectID: String) {
        guard !configured else { return }
        guard !projectID.isEmpty else { return }

        Networking.configure(
            groupIdentifier: "group.fi.socket.socketfi",
            projectId: projectID,
            socketFactory: SocketFiWebSocketFactory()
        )

        let metadata = AppMetadata(
            name: "SocketFi",
            description: "Smart accounts for your digital money.",
            url: "https://socket.fi",
            icons: ["https://socket.fi/icon.png"]
        )

        AppKit.configure(
            projectId: projectID,
            metadata: metadata,
            crypto: SocketFiReownCryptoProvider(),
            authRequestParams: nil,
            includeWebWallets: true,
            coinbaseEnabled: true
        )
        configured = true
    }

    func presentWalletPicker() {
        guard configured else { return }
        AppKit.present()
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard configured else { return false }
        return AppKit.instance.handleDeeplink(url)
    }
}

private struct SocketFiWebSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        let socket = WebSocket(request: URLRequest(url: url))
        socket.callbackQueue = DispatchQueue(label: "fi.socket.socketfi.walletconnect", attributes: .concurrent)
        return socket
    }
}
