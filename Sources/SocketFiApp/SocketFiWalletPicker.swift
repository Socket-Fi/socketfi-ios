import SwiftUI

struct SocketFiWalletChoice: Decodable, Identifiable {
    struct Mobile: Decodable { let native: String?; let universal: String? }
    struct Images: Decodable { let md: String? }
    let id: String
    let name: String
    let mobile: Mobile
    let image_url: Images?
    var mobile_link: String? {
        if let native = mobile.native, !native.isEmpty { return native }
        return mobile.universal
    }
}

struct SocketFiWalletCatalogue: Decodable {
    let listings: [String: SocketFiWalletChoice]
    let total: Int
    var data: [SocketFiWalletChoice] { Array(listings.values) }
}

struct SocketFiWalletPicker: View {
    @ObservedObject var connection: SocketFiWalletConnect
    let cancel: () -> Void
    @State private var search = ""
    @State private var openError: String?

    var body: some View {
        NavigationStack {
            List {
                if connection.choosing {
                    Section {
                        Label(connection.pairingReady ? "Waiting for your wallet" : "Preparing connection", systemImage: "arrow.up.forward.app")
                        Text(connection.pairingReady ? "Approve the connection in your wallet, then return to SocketFi. A separate signature will confirm your account." : "Your wallet will open as soon as the secure connection is ready.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Open wallet") {
                            Task {
                                do { try await connection.reopenWallet(); openError = nil }
                                catch { openError = error.localizedDescription }
                            }
                        }.disabled(!connection.pairingReady)
                    }
                    if let openError { Text(openError).font(.footnote) }
                } else {
                    Section {
                        Text("Choose an installed WalletConnect wallet. Your wallet must support Ethereum message signing.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(connection.wallets.filter {
                        $0.mobile_link?.isEmpty == false && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                    }) { wallet in
                        Button { connection.choose(wallet) } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: wallet.image_url?.md.flatMap { URL(string: $0) }) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: { Image(systemName: "wallet.pass").foregroundStyle(.secondary) }
                                .frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(wallet.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("wallet.choice." + wallet.name)
                    }
                    if let error = connection.catalogueError {
                        Text(error).font(.footnote)
                        Button("Retry loading wallets") { Task { await connection.loadWallets() } }
                    }
                    if connection.loadingWallets { ProgressView("Loading wallets") }
                    else if connection.hasMoreWallets {
                        Button("Load more wallets") { Task { await connection.loadWallets() } }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a wallet")
            .navigationTitle("Choose your wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
        .interactiveDismissDisabled(connection.choosing)
        .task { if connection.wallets.isEmpty { await connection.loadWallets() } }
    }
}
