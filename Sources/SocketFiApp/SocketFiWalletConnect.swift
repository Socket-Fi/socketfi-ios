import Foundation
import Combine
import SocketFiNativeKit
@preconcurrency import ReownAppKit
import WalletConnectNetworking
import WalletConnectRelay
import Starscream

#if canImport(UIKit)
import UIKit
#endif

/// Owns the one-time Reown/AppKit setup used by the native EVM sign-in flow.
@MainActor
final class SocketFiWalletConnect {
    static let shared = SocketFiWalletConnect()
    private var configured = false
    private var pickerPresented = false
    private var subscriptions = Set<AnyCancellable>()

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
            icons: ["https://socket.fi/icon.png"],
            redirect: try! AppMetadata.Redirect(native: "socketfi://walletconnect", universal: nil)
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
        pickerPresented = true
        AppKit.present()
    }

    func sign(message: String) async throws -> String {
        guard configured else { throw SocketFiNativeError.configuration("Wallet connection is not configured.") }
        if message == "__socketfi_address__" {
            if let address = AppKit.instance.getAddress() { return address }
            try await waitForSession()
            guard let address = AppKit.instance.getAddress() else { throw SocketFiNativeError.invalidResponse }
            return address
        }
        guard let address = AppKit.instance.getAddress() else { throw SocketFiNativeError.sessionUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = AppKit.instance.sessionResponsePublisher
                .first()
                .sink { [weak self] response in
                    cancellable?.cancel()
                    self?.subscriptions.removeAll()
                    switch response.result {
                    case let .response(value):
                        do { continuation.resume(returning: try value.get(String.self)) }
                        catch { continuation.resume(throwing: SocketFiNativeError.invalidResponse) }
                    case .error:
                        continuation.resume(throwing: SocketFiNativeError.authenticationCancelled)
                    }
                }
            if let cancellable { subscriptions.insert(cancellable) }
            Task { try? await AppKit.instance.request(.personal_sign(address: address, message: message)) }
        }
    }

    private func waitForSession() async throws {
        if !pickerPresented { AppKit.present() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in AppKit.instance.sessionSettlePublisher.values { return }
                throw SocketFiNativeError.sessionUnavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                throw SocketFiNativeError.configuration("Wallet connection timed out. Try again.")
            }
            _ = try await group.next()
            group.cancelAll()
        }
        pickerPresented = false
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard configured else { return false }
        return AppKit.instance.handleDeeplink(url)
    }
}

private struct SocketFiWebSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        SocketFiWebSocket(request: URLRequest(url: url))
    }
}

private final class SocketFiWebSocket: NSObject, WebSocketConnecting, WebSocketDelegate {
    private let socket: WebSocket
    private(set) var isConnected = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?

    var request: URLRequest {
        get { socket.request }
        set { socket.request = newValue }
    }

    init(request: URLRequest) {
        socket = WebSocket(request: request)
        super.init()
        socket.delegate = self
        socket.callbackQueue = DispatchQueue(label: "fi.socket.socketfi.walletconnect", attributes: .concurrent)
    }

    func connect() { socket.connect() }

    func disconnect() { socket.disconnect() }

    func write(string: String, completion: (() -> Void)?) {
        socket.write(string: string, completion: completion)
    }

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            onConnect?()
        case let .disconnected(reason, _):
            isConnected = false
            onDisconnect?(NSError(domain: "SocketFiWalletConnect", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
        case let .text(value):
            onText?(value)
        case let .error(error):
            isConnected = false
            onDisconnect?(error)
        case .cancelled, .peerClosed:
            isConnected = false
            onDisconnect?(nil)
        default:
            break
        }
    }
}
