import SwiftUI
import SocketFiNativeKit
import UIKit

private enum SocketFiWalletTab: String, Hashable, CaseIterable, Identifiable {
    case wallet, tokens, activity, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallet: "Wallet"
        case .tokens: "Tokens"
        case .activity: "Transactions"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .wallet: "wallet.pass"
        case .tokens: "circle.grid.2x2"
        case .activity: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        }
    }
}

struct SocketFiWalletShell: View {
    private let signOut: () -> Void
    @StateObject private var model: SocketFiWalletModel
    @State private var selectedTab: SocketFiWalletTab = .wallet
    @State private var didAppear = false

    init(session: SocketFiSession, configuration: SocketFiConfiguration, signer: SocketFiNativeAccountClient, signOut: @escaping () -> Void) {
        _model = StateObject(wrappedValue: SocketFiWalletModel(session: session, configuration: configuration, signer: signer))
        self.signOut = signOut
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SocketFiWalletView(model: model, signOut: signOut)
                    .toolbarRole(.editor)
                    .navigationTitle("")
            }
            .tabItem { Label(SocketFiWalletTab.wallet.title, systemImage: SocketFiWalletTab.wallet.icon) }
            .tag(SocketFiWalletTab.wallet)

            NavigationStack {
                SocketFiTokensView(model: model)
                    .toolbarRole(.editor)
                    .navigationTitle("Tokens")
            }
            .tabItem { Label(SocketFiWalletTab.tokens.title, systemImage: SocketFiWalletTab.tokens.icon) }
            .tag(SocketFiWalletTab.tokens)

            NavigationStack {
                SocketFiActivityView(model: model)
                    .toolbarRole(.editor)
                    .navigationTitle("Transactions")
            }
            .tabItem { Label(SocketFiWalletTab.activity.title, systemImage: SocketFiWalletTab.activity.icon) }
            .tag(SocketFiWalletTab.activity)

            NavigationStack {
                SocketFiAccountView(model: model, signOut: signOut)
                .toolbarRole(.editor)
                .navigationTitle("Account")
            }
            .tabItem { Label(SocketFiWalletTab.account.title, systemImage: SocketFiWalletTab.account.icon) }
            .tag(SocketFiWalletTab.account)
        }
        .tint(AccessStyle.brand)
        .toolbarBackground(AccessStyle.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            if !didAppear {
                didAppear = true
                Task { await model.refresh() }
            }
        }
        .onChange(of: selectedTab) { _, nextTab in
            if nextTab == .wallet && model.snapshot == nil && !model.busy {
                Task { await model.refresh() }
            }
        }
        .background(AccessStyle.background.ignoresSafeArea())
        .sheet(item: $model.action, onDismiss: { model.dismissActionResult() }) { action in
            if action == .deposit || action == .address {
                SocketFiReceiveView(model: model, addressOnly: action == .address)
            } else if action == .delegation {
                SocketFiDelegationView(model: model)
            } else {
                SocketFiWalletActionView(model: model, action: action)
            }
        }
    }
}

private struct SocketFiDelegationView: View {
    @ObservedObject var model: SocketFiWalletModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WalletSectionHeader(
                        title: "Policy controls",
                        subtitle: "Set delegation and strategy controls for this smart account."
                    )

                    WalletNotice(
                        title: "Delegations and strategies",
                        message: "This area supports policy-based controls for approvals and recurring permissions."
                    )

                    VStack(spacing: 12) {
                        Button {
                            // placeholder for next iteration
                        } label: {
                        Label("Create delegation", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border, lineWidth: 0.5))
                        }
                        .buttonStyle(AccessButtonStyle())

                        Button {
                            // placeholder for next iteration
                        } label: {
                        Label("Create strategy", systemImage: "chart.bar.doc.horizontal")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border, lineWidth: 0.5))
                        }
                        .buttonStyle(AccessButtonStyle())
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle("Policies")
            .background(AccessStyle.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct SocketFiTokensView: View {
    @ObservedObject var model: SocketFiWalletModel
    @State private var selectedToken: SocketFiToken?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WalletSectionHeader(title: "Your tokens", subtitle: "Balances held by your smart account.")

                if model.loading && model.snapshot == nil {
                    ProgressView("Loading tokens…")
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                } else if model.tokens.isEmpty {
                    ContentUnavailableView("No tokens yet", systemImage: "circle.grid.2x2", description: Text("Deposit funds to see your assets here."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.tokens) { token in
                            Button { selectedToken = token } label: {
                                HStack(spacing: 12) {
                                    WalletTokenIcon(symbol: token.symbol)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(token.symbol).font(.body.weight(.semibold))
                                        Text(model.hideBalances ? "••••" : token.balanceText)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(model.hideBalances ? "••••" : WalletFormat.fiat(token.estimatedValue))
                                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        Text("View details").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if token.id != model.tokens.last?.id { Divider().padding(.leading, 70) }
                        }
                    }
                    .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AccessStyle.border, lineWidth: 0.5))
                }

                WalletNotice(title: "Balances update from the network", message: "Token symbols are not proof of an issuer. Verify the contract address before receiving unfamiliar assets.")
            }
            .padding(16)
        }
        .background(AccessStyle.background.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .sheet(item: $selectedToken) { token in
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 14) {
                            WalletTokenIcon(symbol: token.symbol)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(token.symbol).font(.headline)
                                Text(model.hideBalances ? "••••" : "\(token.balanceText) \(token.symbol)")
                                    .font(.title3).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section("Token details") {
                        LabeledContent("Network", value: model.networkLabel)
                        Text(token.contract).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
                .navigationTitle(token.symbol)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedToken = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct SocketFiTransfersView: View {
    @ObservedObject var model: SocketFiWalletModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WalletSectionHeader(title: "Wallet actions", subtitle: "Choose one action per session.")

                if model.loading && model.snapshot == nil {
                    ProgressView("Loading wallet…")
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    actionGrid
                }

                if let error = model.error {
                    WalletNotice(title: "Wallet check failed", message: error, systemImage: "wifi.exclamationmark")
                }

                WalletNotice(
                    title: "Network check",
                    message: "Make sure your account and app are on \(model.networkLabel) before submitting."
                )
            }
            .padding(20)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .background(AccessStyle.background.ignoresSafeArea())
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickActionButton(
                title: "Deposit",
                subtitle: "Add funds",
                icon: "arrow.down.circle",
                enabled: !model.busy
            ) { model.open(.deposit) }

            QuickActionButton(
                title: "Reveal account",
                subtitle: "Copy address",
                icon: "wallet.pass",
                enabled: !model.busy
            ) { model.open(.address) }

            QuickActionButton(
                title: "Withdraw",
                subtitle: "Send funds",
                icon: "arrow.up.right.circle",
                enabled: !model.busy && !model.tokens.isEmpty
            ) { model.open(.withdraw) }

            QuickActionButton(
                title: "Swap",
                subtitle: "Exchange assets",
                icon: "arrow.left.arrow.right.circle",
                enabled: !model.busy && model.tokens.count >= 2
            ) { model.open(.swap) }
        }
    }
}

private struct SocketFiAccountView: View {
    @ObservedObject var model: SocketFiWalletModel
    let signOut: () -> Void
    @State private var copied = false
    @State private var confirmSignOut = false

    private var webHost: String {
        model.session.account.network == .testnet ? "https://testnet.socketfi.app" : "https://socketfi.app"
    }

    var body: some View {
        List {
            Section("Wallet") {
                if let username = model.session.walletUsername {
                    LabeledContent("Username", value: username)
                }
                LabeledContent("Network", value: model.networkLabel)
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Wallet address").font(.caption).foregroundStyle(.secondary)
                        Text(model.session.account.address).font(.subheadline.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        UIPasteboard.general.string = model.session.account.address
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(copied ? "Address copied" : "Copy wallet address")
                }
                ShareLink(item: model.session.account.address) {
                    Label("Share address", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                LabeledContent("Sign-in method", value: model.session.account.signer == .passkey ? "Passkey" : model.session.account.signer == .evmWallet ? "EVM wallet" : "Stellar wallet")
                NavigationLink {
                    SocketFiGuardianView(wallet: model)
                } label: {
                    Label("Recovery & guardians", systemImage: "person.2.shield.checkmark")
                }.accessibilityIdentifier("account.guardians")
                Link(destination: URL(string: webHost + "/settings/sessions")!) {
                    Label("Session permissions", systemImage: "lock.shield")
                }
            } header: { Text("Security") } footer: {
                Text("Session permissions open SocketFi in your browser.")
            }
            Section("Preferences") {
                Toggle("Hide balances", isOn: $model.hideBalances)
                Link(destination: model.explorerURL) {
                    Label("View on explorer", systemImage: "arrow.up.right.square")
                }
            }
            Section {
                Button(role: .destructive) { confirmSignOut = true } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }.accessibilityIdentifier("account.signOut")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Sign out of SocketFi?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Sign back in with the same passkey or wallet.")
        }
    }
}

private struct WalletSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionButtonLabel(title: title, subtitle: subtitle, icon: icon)
        }
        .disabled(!enabled)
        .buttonStyle(AccessButtonStyle())
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct QuickActionButtonLabel: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AccessStyle.brand.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AccessStyle.brand)
            }
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(12)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ActivityReceiptCard: View {
    let receipt: SocketFiWalletModel.Receipt
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(receipt.confirmed ? "Transaction confirmed" : receipt.title, systemImage: receipt.confirmed ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text(receipt.confirmed
                 ? "The network confirmed this transaction."
                 : "Check the on-chain status before starting another payment.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !receipt.confirmed {
                Button("I've verified this transaction", action: action)
                    .font(.footnote)
            } else {
                Button("Clear") { action() }
                    .font(.footnote)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
