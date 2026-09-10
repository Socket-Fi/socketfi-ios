import SwiftUI
import SocketFiNativeKit
import UIKit

struct SocketFiWalletView: View {
    @StateObject private var model: SocketFiWalletModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmActivityChecked = false
    @State private var selectedToken: SocketFiToken?
    @State private var copiedAddress = false
    @State private var showQuickSettings = false
    @State private var watchlistTokenIDs = Set<String>()
    @State private var usingCustomWatchlist = false

    init(session: SocketFiSession, configuration: SocketFiConfiguration, signer: SocketFiNativeAccountClient) {
        self.init(model: SocketFiWalletModel(session: session, configuration: configuration, signer: signer))
    }

    init(model: SocketFiWalletModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                walletBanner
                portfolio
                quickActions
                if let receipt = model.receipt { receiptCard(receipt) }
                if let error = model.error {
                    WalletNotice(title: "Couldn't refresh your wallet", message: error, systemImage: "wifi.exclamationmark")
                }
                assets
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 36)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(AccessStyle.background.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .tint(AccessStyle.brand)
        .onAppear { loadWatchlist() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !model.busy { Task { await model.refresh() } }
        }
        .sheet(isPresented: $showQuickSettings) { quickSettingsSheet }
        .sheet(item: $selectedToken) { token in
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 14) {
                            WalletTokenIcon(symbol: token.symbol)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(token.symbol).font(.headline)
                                Text(model.hideBalances ? "••••" : "\(token.balanceText) \(token.symbol)").font(.title3).monospacedDigit()
                            }
                        }.padding(.vertical, 12)
                    }
                    Section("Token details") {
                        LabeledContent("Network", value: model.networkLabel)
                        Text(token.contract).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                    Section {
                        Text("Balances are read from the network. A token's symbol is not proof of its issuer; verify the contract address before receiving unfamiliar assets.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(token.symbol)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedToken = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .alert("Have you checked the transaction?", isPresented: $confirmActivityChecked) {
            Button("Keep checking", role: .cancel) { }
            Button("I've verified the outcome") { model.acknowledgeCheckedActivity() }
        } message: {
            Text("Only continue after checking your account activity and balances. Repeating a payment that already succeeded sends the funds again.")
        }
    }

    private var walletBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SocketFiBrandMark()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SocketFi")
                        .font(.headline.weight(.semibold))
                    Text("Secure smart-account wallet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showQuickSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(AccessStyle.surface, in: Circle())
                        .foregroundStyle(AccessStyle.brand)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wallet settings")
            }
            HStack(spacing: 8) {
                TagPill(text: "Passkeys")
                TagPill(text: "Policy controls")
                TagPill(text: "Swaps")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var portfolio: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Portfolio")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(model.networkLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(AccessStyle.brand.opacity(0.09), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.hideBalances ? "••••••" : WalletFormat.fiat(model.snapshot?.estimatedTotal))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit().contentTransition(.numericText())
                    .minimumScaleFactor(0.75).lineLimit(1)
                Text(model.snapshot == nil ? "Sign in and load your balances" : "Total estimated USD value")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { model.hideBalances.toggle() } label: {
                    Image(systemName: model.hideBalances ? "eye.slash" : "eye")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.hideBalances ? "Show balances" : "Hide balances")

                Divider().frame(height: 34)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text(WalletFormat.shortAddress(model.session.account.address))
                            .font(.footnote.weight(.medium))
                            .monospaced()
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Button { copy(model.session.account.address, copied: $copiedAddress) } label: {
                            Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Contract account")
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(22)
        .background(AccessStyle.headerGradient, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AccessStyle.border, lineWidth: 0.5))
    }

    private var assets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assets").font(.title3.weight(.semibold))
                Spacer()
                if model.loading { ProgressView().accessibilityLabel("Refreshing balances") }
                else {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Refresh wallet")
                }
            }
            if model.snapshot == nil && model.loading {
                ProgressView("Loading your assets…").frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if displayTokens.isEmpty {
                ContentUnavailableView(
                    usingCustomWatchlist ? "No watched assets selected" : "Your wallet starts here",
                    systemImage: usingCustomWatchlist ? "eye.slash" : "wallet.pass",
                    description: Text(usingCustomWatchlist ? "Open quick settings and add at least one asset to your watchlist." : "Deposit funds to start using your account.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(displayTokens) { token in
                        Button { selectedToken = token } label: {
                            tokenRow(token)
                        }.buttonStyle(.plain)
                        if token.id != displayTokens.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AccessStyle.border, lineWidth: 0.45))
            }
            if let fetched = model.snapshot.flatMap({ SocketFiWalletClient.date($0.fetchedAt) }) {
                Text("Updated \(fetched.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            walletAction(title: "Deposit", icon: "arrow.down.left", action: .deposit)
            walletAction(title: "Withdraw", icon: "arrow.up.right", action: .withdraw)
            walletAction(title: "Swap", icon: "arrow.left.arrow.right", action: .swap)
            walletAction(title: "Policies", icon: "shield.fill", action: .delegation)
        }
    }

    private func walletAction(title: String, icon: String, action: SocketFiWalletModel.Action) -> some View {
        let assetName: String? = switch action {
        case .deposit: "SocketFiReceive"
        case .withdraw: "SocketFiSend"
        case .swap: "SocketFiSwap"
        case .address: "SocketFiWallet"
        case .delegation: nil
        }

        return Button { model.open(action) } label: {
            VStack(spacing: 7) {
                Group {
                    if let assetName {
                        Image(assetName)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AccessStyle.brand)
                    }
                }
                    .frame(width: 38, height: 38)
                    .background(AccessStyle.brand.opacity(0.1), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border, lineWidth: 0.5))
        }
        .buttonStyle(AccessButtonStyle())
        .disabled(model.busy || (action == .withdraw && model.tokens.isEmpty) || (action == .swap && model.tokens.count < 2))
        .opacity((model.busy || (action == .withdraw && model.tokens.isEmpty) || (action == .swap && model.tokens.count < 2)) ? 0.45 : 1)
    }

    private func receiptCard(_ receipt: SocketFiWalletModel.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(receipt.confirmed ? "Transaction confirmed" : receipt.title,
                  systemImage: receipt.confirmed ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            if model.unresolved {
                Text("Your transaction may have been submitted. Check its outcome before making another payment.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Link(destination: receipt.hash.map(model.transactionURL) ?? model.explorerURL) {
                Label("View on explorer", systemImage: "arrow.up.right.square").font(.subheadline)
            }
            if model.unresolved {
                Button("I've checked my account activity") { confirmActivityChecked = true }.font(.footnote)
            } else { Button("Dismiss") { model.receipt = nil }.font(.footnote) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var displayTokens: [SocketFiToken] {
        if usingCustomWatchlist {
            return model.tokens.filter { watchlistTokenIDs.contains($0.id) }
        }
        return model.tokens
    }

    private var quickSettingsSheet: some View {
        NavigationStack {
            List {
                Section("Watchlist") {
                    if model.tokens.isEmpty {
                        Text("Load your wallet to manage asset visibility.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.tokens) { token in
                            Button {
                                toggleWatchlist(token.id)
                            } label: {
                                HStack {
                                    WalletTokenIcon(symbol: token.symbol)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(token.symbol).font(.body.weight(.medium))
                                        Text(token.contract)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: isWatching(token.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(AccessStyle.brand)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Quick actions") {
                    Button("Show all assets") {
                        usingCustomWatchlist = false
                        watchlistTokenIDs.removeAll()
                        persistWatchlist()
                    }
                    .foregroundStyle(AccessStyle.brand)
                }
            }
            .navigationTitle("Wallet settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showQuickSettings = false }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func isWatching(_ tokenID: String) -> Bool {
        if !usingCustomWatchlist {
            return true
        }
        return watchlistTokenIDs.contains(tokenID)
    }

    private func toggleWatchlist(_ tokenID: String) {
        usingCustomWatchlist = true
        if watchlistTokenIDs.contains(tokenID) {
            watchlistTokenIDs.remove(tokenID)
        } else {
            watchlistTokenIDs.insert(tokenID)
        }
        persistWatchlist()
    }

    private func loadWatchlist() {
        let key = watchlistStorageKey
        guard let raw = UserDefaults.standard.data(forKey: key) else {
            usingCustomWatchlist = false
            watchlistTokenIDs.removeAll()
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String].self, from: raw)
            watchlistTokenIDs = Set(decoded)
            usingCustomWatchlist = !decoded.isEmpty
        } catch {
            usingCustomWatchlist = false
            watchlistTokenIDs.removeAll()
        }
    }

    private func persistWatchlist() {
        let key = watchlistStorageKey
        if !usingCustomWatchlist || watchlistTokenIDs.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        do {
            let encoded = try JSONEncoder().encode(Array(watchlistTokenIDs))
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
            return
        }
    }

    private var watchlistStorageKey: String {
        "socketfi.wallet.watchlist.\(model.configuration.clientID).\(model.session.account.network.rawValue).\(model.session.account.address)"
    }

    private func tokenRow(_ token: SocketFiToken) -> some View {
        HStack(spacing: 12) {
            WalletTokenIcon(symbol: token.symbol)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(token.symbol).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(model.hideBalances ? "••••" : "\(token.balanceText) \(token.symbol)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 3) {
                Text(model.hideBalances ? "••••" : WalletFormat.fiat(token.estimatedValue))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.primary)
                Text(token.availableBalance == nil ? "Balance unavailable" : "On-chain")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func copy(_ value: String, copied: Binding<Bool>) {
        UIPasteboard.general.string = value
        copied.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied.wrappedValue = false
        }
    }
}

enum WalletFormat {
    static func fiat(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    static func shortAddress(_ value: String) -> String { String(value.prefix(6)) + "…" + String(value.suffix(6)) }
}

private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AccessStyle.background, in: Capsule())
            .overlay(Capsule().stroke(AccessStyle.border, lineWidth: 0.5))
            .foregroundStyle(.primary)
    }
}

struct WalletTokenIcon: View {
    let symbol: String
    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            if ["XLM", "USDC", "USDT"].contains(symbol.uppercased()) {
                Image("Token\(symbol.uppercased())")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            } else {
                Circle().fill(AccessStyle.brand.opacity(0.08))
                Text(String(symbol.prefix(2))).font(.subheadline.weight(.semibold)).foregroundStyle(AccessStyle.brand)
            }
        }.frame(width: 44, height: 44).accessibilityHidden(true)
    }
}

struct WalletNotice: View {
    let title: String
    let message: String
    var systemImage = "info.circle"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(AccessStyle.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
