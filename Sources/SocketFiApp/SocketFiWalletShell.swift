import SwiftUI
import SocketFiNativeKit
import UIKit

private enum SocketFiWalletTab: String, Hashable, CaseIterable, Identifiable {
    case wallet, transfer, activity, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallet: "Wallet"
        case .transfer: "Transfer"
        case .activity: "Activity"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .wallet: "wallet.pass"
        case .transfer: "arrow.left.arrow.right"
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
                SocketFiWalletView(model: model)
                    .toolbarRole(.editor)
                    .navigationTitle("Wallet")
            }
            .tabItem { Label(SocketFiWalletTab.wallet.title, systemImage: SocketFiWalletTab.wallet.icon) }
            .tag(SocketFiWalletTab.wallet)

            NavigationStack {
                SocketFiTransfersView(model: model)
                    .toolbarRole(.editor)
                    .navigationTitle("Transfer")
            }
            .tabItem { Label(SocketFiWalletTab.transfer.title, systemImage: SocketFiWalletTab.transfer.icon) }
            .tag(SocketFiWalletTab.transfer)

            NavigationStack {
                SocketFiActivityView(model: model)
                    .toolbarRole(.editor)
                    .navigationTitle("Activity")
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
        .sheet(item: $model.action) { action in
            if action == .deposit || action == .address {
                SocketFiReceiveView(model: model, addressOnly: action == .address)
            } else {
                SocketFiWalletActionView(model: model, action: action)
            }
        }
    }
}

private struct SocketFiTransfersView: View {
    @ObservedObject var model: SocketFiWalletModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WalletSectionHeader(title: "Wallet actions", subtitle: "Use one path for each action.")

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

                WalletSectionHeader(title: "Important", subtitle: "Make sure you’re on \(model.networkLabel) before signing.")
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 12) {
                    Text("• Deposit funds with the link and complete in the SocketFi web flow.")
                    Text("• Withdraw and swap use on-chain smart-account permissions granted to this app.")
                    Text("• Each transfer is reviewed in the next screen before your passkey signs.")
                    Text("• Unconfirmed transactions are surfaced in Activity and should be checked before a retry.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(20)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .background(AccessStyle.background.ignoresSafeArea())
    }

    private var actionGrid: some View {
        VStack(spacing: 12) {
            ActionButton(
                title: "Deposit",
                subtitle: "Open a deposit link to add funds from another wallet",
                icon: "arrow.down.circle",
                enabled: !model.busy
            ) { model.open(.deposit) }

            ActionButton(
                title: "Reveal account",
                subtitle: "Copy your smart-account address and deposit details",
                icon: "wallet.pass",
                enabled: !model.busy
            ) { model.open(.address) }

            ActionButton(
                title: "Withdraw",
                subtitle: "Send an amount to another Stellar account",
                icon: "arrow.up.right.circle",
                enabled: !model.busy && !model.tokens.isEmpty
            ) { model.open(.withdraw) }

            ActionButton(
                title: "Swap",
                subtitle: "Exchange tokens with a live quote",
                icon: "arrow.left.arrow.right.circle",
                enabled: !model.busy && model.tokens.count >= 2
            ) { model.open(.swap) }
        }
    }
}

private struct SocketFiActivityView: View {
    @ObservedObject var model: SocketFiWalletModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let receipt = model.receipt {
                    Group {
                        Text(receipt.confirmed ? "Latest transaction confirmed" : "Latest transaction pending")
                            .font(.title3.weight(.semibold))
                        ActivityReceiptCard(receipt: receipt, action: { model.acknowledgeCheckedActivity() })
                    }
                } else {
                    Text("No recent activity")
                        .font(.title3.weight(.semibold))
                    Text("Approve a withdraw or swap transaction to start your activity log.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                WalletSectionHeader(title: "On-chain activity", subtitle: "Open your account in the explorer for complete history.")

                Link(destination: model.explorerURL) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open account activity in explorer")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                if let hash = model.receipt?.hash {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Text("Open latest transaction")
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "link")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }

                if model.unresolved {
                    WalletNotice(
                        title: "Awaiting on-chain confirmation",
                        message: "Check explorer before initiating another withdraw/swap."
                    )
                }

                if let snapshot = model.snapshot, let fetched = SocketFiWalletClient.date(snapshot.fetchedAt) {
                    Text("Last balance sync: \(fetched.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(AccessStyle.background.ignoresSafeArea())
    }

    private var url: URL {
        if let hash = model.receipt?.hash {
            return model.transactionURL(hash)
        }
        return model.explorerURL
    }
}

private struct SocketFiAccountView: View {
    @ObservedObject var model: SocketFiWalletModel
    let signOut: () -> Void
    @Environment(\.openURL) private var openURL

    @State private var copiedAddress = false
    @State private var copiedUsername = false
    @State private var copiedProject = false
    @State private var copiedApplication = false
    @State private var copiedRelyingParty = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SocketFiBrandMark().fill(AccessStyle.brand, style: FillStyle(eoFill: true)).frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SocketFi Account")
                            .font(.title3.weight(.semibold))
                        Text(model.networkLabel)
                            .font(.subheadline)
                            .foregroundStyle(AccessStyle.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AccessStyle.headerGradient, in: RoundedRectangle(cornerRadius: 18))

                WalletSectionHeader(title: "Account contract and identifiers", subtitle: "Primary metadata available in-session.")
                accountCard(title: "Smart account", rows: [
                    ("Contract ID", model.session.account.address),
                    ("Network", model.networkLabel),
                    ("Signer method", model.session.account.signer == .passkey ? "Passkey" : model.session.account.signer == .evmWallet ? "EVM Wallet" : "Stellar Wallet"),
                    ("Session expires", formattedSessionExpiry)
                ], copyActions: [
                    ("Contract ID", model.session.account.address, $copiedAddress),
                ])

                if let username = model.session.walletUsername {
                    accountCard(title: "Identity", rows: [
                        ("Display username", username)
                    ], copyActions: [
                        ("Username", username, $copiedUsername)
                    ])
                }

                WalletSectionHeader(title: "Project configuration", subtitle: "Project-level config used by this app.")
                accountCard(title: "SocketFi project", rows: [
                    ("Client ID", model.configuration.clientID),
                    ("Application ID", model.configuration.applicationID),
                    ("RP ID", model.configuration.relyingPartyID)
                ], copyActions: [
                    ("Client ID", model.configuration.clientID, $copiedProject),
                    ("Application ID", model.configuration.applicationID, $copiedApplication),
                    ("RP ID", model.configuration.relyingPartyID, $copiedRelyingParty)
                ])

                if let capabilities = model.capabilities {
                    let networkCaps = capabilities.allowedInvocations.filter { $0.network == model.session.account.network }
                    let funcs = Set(networkCaps.flatMap(\.functions)).sorted()
                    let caps = funcs.isEmpty ? "No capabilities indexed for current network" : funcs.joined(separator: ", ")
                    accountCard(title: "Wallet capabilities", rows: [
                        ("Enabled on networks", capabilities.networks.map(\.rawValue).joined(separator: ", ")),
                        ("Allowed contract functions", caps)
                    ], copyActions: [])
                } else {
                    WalletNotice(
                        title: "Capabilities pending",
                        message: model.loading
                            ? "Loading contract capabilities for wallet actions."
                            : "Capabilities are not available right now."
                    )
                }

                if let username = model.session.walletUsername {
                    WalletNotice(
                        title: "Session identity",
                        message: "This session is bound to username \(username) on this account contract."
                    )
                }

                WalletSectionHeader(title: "Account links", subtitle: "Common helpers for support and verification.")
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ActionButton(
                            title: "Copy contract ID",
                            subtitle: "Copy account contract address",
                            icon: "doc.on.doc",
                            enabled: true
                        ) { copy(model.session.account.address, copied: $copiedAddress) }

                        ShareLink(item: model.session.account.address) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(AccessStyle.brand.opacity(0.12))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AccessStyle.brand)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Share contract").font(.subheadline.weight(.semibold))
                                    Text("Share with another wallet").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption.weight(.semibold))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(AccessStyle.border)
                            )
                        }
                        .buttonStyle(AccessButtonStyle())
                        .contentShape(Rectangle())
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIApplication.shared.open(model.explorerURL)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(AccessStyle.brand.opacity(0.12)).frame(width: 40, height: 40)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AccessStyle.brand)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Open explorer").font(.subheadline.weight(.semibold))
                                    Text("View activity and contract page").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption.weight(.semibold))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AccessStyle.border.opacity(0.8)))
                        }
                        .buttonStyle(AccessButtonStyle())
                        .contentShape(Rectangle())

                        ActionButton(
                            title: "Open deposit page",
                            subtitle: "Fund this account from wallet",
                            icon: "arrow.down.left",
                            enabled: true
                        ) { UIApplication.shared.open(model.depositURL) }
                    }

                    Button {
                        openURL(settingsWebURL)
                    } label: {
                        Label("Open account settings (web)", systemImage: "person.text.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccessStyle.primary)
                }

                if let copiedText = copiedNoticeText {
                    WalletNotice(
                        title: "Clipboard",
                        message: copiedText,
                        systemImage: "doc.on.doc"
                    )
                }

                WalletSectionHeader(title: "Security and advanced settings", subtitle: "Guardian and session controls are managed in SocketFi web.")
                VStack(spacing: 10) {
                    webSettingsAction(title: "Recovery and guardians", destination: guardiansURL, subtitle: "Add trusted guardians, schedule removals, and finalize removals.")
                    webSettingsAction(title: "Session permissions", destination: sessionsURL, subtitle: "Inspect automation approvals and revoke active permissions.")
                }

                WalletNotice(
                    title: "Implementation boundary",
                    message: "Native sessions currently expose account balance/action operations. Guardian and session-management APIs stay in the web console for now."
                )

                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                WalletNotice(
                    title: "Session scope",
                    message: "Signing out clears local session state. Your account remains registered and can be re-opened with the same passkey."
                )
            }
            .padding(20)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(AccessStyle.background.ignoresSafeArea())
        .confirmationDialog("Sign out of SocketFi?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with your passkey anytime.")
        }
    }

    private var formattedSessionExpiry: String {
        model.session.expiresAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var settingsWebURL: URL {
        let host = model.session.account.network == .testnet ? "https://testnet.socketfi.app" : "https://socketfi.app"
        return URL(string: "\(host)/settings")!
    }

    private var guardiansURL: URL {
        let host = model.session.account.network == .testnet ? "https://testnet.socketfi.app" : "https://socketfi.app"
        return URL(string: "\(host)/settings/guardians")!
    }

    private var sessionsURL: URL {
        let host = model.session.account.network == .testnet ? "https://testnet.socketfi.app" : "https://socketfi.app"
        return URL(string: "\(host)/settings/sessions")!
    }

    private var copiedNoticeText: String? {
        if copiedAddress { return "Contract ID copied." }
        if copiedUsername { return "Username copied." }
        if copiedProject { return "Client ID copied." }
        if copiedApplication { return "Application ID copied." }
        if copiedRelyingParty { return "RP ID copied." }
        return nil
    }

    private func copy(_ value: String, copied: Binding<Bool>) {
        UIPasteboard.general.string = value
        copied.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied.wrappedValue = false
        }
    }

    private func accountCard(title: String, rows: [(String, String)], copyActions: [(String, String, Binding<Bool>)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.0).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(row.1).font(.body.weight(.semibold)).monospaced().foregroundStyle(.primary)
                    }
                }
            }

            if !copyActions.isEmpty {
                HStack {
                    ForEach(copyActions, id: \.0) { item in
                        Button {
                            copy(item.1, copied: item.2)
                        } label: {
                            Label("Copy \(item.0)", systemImage: item.2.wrappedValue ? "checkmark" : "doc.on.doc")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func webSettingsAction(title: String, destination: URL, subtitle: String) -> some View {
        Button {
            openURL(destination)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AccessStyle.brand.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AccessStyle.brand)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AccessStyle.border.opacity(0.8))
            )
        }
        .buttonStyle(AccessButtonStyle())
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

private struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(enabled ? AccessStyle.brand.opacity(0.12) : Color.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(enabled ? AccessStyle.brand : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(enabled ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(enabled ? AccessStyle.border : AccessStyle.border.opacity(0.4))
            )
        }
        .disabled(!enabled)
        .buttonStyle(AccessButtonStyle())
        .contentShape(Rectangle())
    }
}

private struct ActivityReceiptCard: View {
    let receipt: SocketFiWalletModel.Receipt
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(receipt.confirmed ? "Transaction confirmed" : receipt.title, systemImage: receipt.confirmed ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text(receipt.confirmed
                 ? "The wallet has reported confirmation."
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
