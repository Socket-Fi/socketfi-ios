import SwiftUI
import SocketFiNativeKit

struct SocketFiWalletView: View {
    @StateObject private var model: SocketFiWalletModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmSignOut = false
    @State private var confirmActivityChecked = false
    @State private var selectedToken: SocketFiToken?
    let signOut: () -> Void

    init(session: SocketFiSession, configuration: SocketFiConfiguration, signer: SocketFiNativeAccountClient, signOut: @escaping () -> Void) {
        _model = StateObject(wrappedValue: SocketFiWalletModel(session: session, configuration: configuration, signer: signer))
        self.signOut = signOut
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        SocketFiBrandMark().fill(AccessStyle.brand, style: FillStyle(eoFill: true)).frame(width: 26, height: 26)
                        Text("SocketFi").font(.headline)
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Account details", systemImage: "person.crop.square") { model.open(.address) }
                        Link(destination: model.explorerURL) { Label("Account activity", systemImage: "arrow.up.right.square") }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmSignOut = true }
                    } label: {
                        Image(systemName: "person.crop.circle").font(.title2).frame(width: 44, height: 44)
                    }.disabled(model.busy).accessibilityLabel("Account menu")
                }
            }
        }
        .tint(AccessStyle.brand)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !model.busy { Task { await model.refresh() } }
        }
        .sheet(item: $model.action) { action in
            if action == .deposit || action == .address {
                SocketFiReceiveView(model: model, addressOnly: action == .address)
            } else {
                SocketFiWalletActionView(model: model, action: action)
            }
        }
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
        .confirmationDialog("Sign out of SocketFi?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: signOut)
        } message: { Text("Your account and passkey will remain available when you sign in again.") }
        .alert("Have you checked the transaction?", isPresented: $confirmActivityChecked) {
            Button("Keep checking", role: .cancel) { }
            Button("I've verified the outcome") { model.acknowledgeCheckedActivity() }
        } message: {
            Text("Only continue after checking your account activity and balances. Repeating a payment that already succeeded sends the funds again.")
        }
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

                Text("Your smart account")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.open(.address) } label: {
                    HStack(spacing: 6) {
                        Text(WalletFormat.shortAddress(model.session.account.address)).monospaced()
                        Image(systemName: "doc.on.doc")
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Reveal account")
            }
        }
        .padding(22)
        .background(AccessStyle.headerGradient, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AccessStyle.border, lineWidth: 0.5))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                actionButton("Deposit", subtitle: "Open deposit", icon: "arrow.down.left", action: .deposit, emphasized: true)
                actionButton("Reveal account", subtitle: "Copy wallet address", icon: "wallet.pass", action: .address)
                actionButton("Withdraw", subtitle: "Send to another account", icon: "arrow.up.right", action: .withdraw)
                actionButton("Swap", subtitle: "Exchange between assets", icon: "arrow.left.arrow.right", action: .swap)
            }
        }
    }

    private func actionButton(_ title: String, subtitle: String, icon: String, action: SocketFiWalletModel.Action, emphasized: Bool = false) -> some View {
        Button { model.open(action) } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill((emphasized ? AccessStyle.primary : AccessStyle.brand).opacity(emphasized ? 1 : 0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(emphasized ? .white : AccessStyle.brand)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background((emphasized ? AccessStyle.primary : AccessStyle.surface).opacity(emphasized ? 0.06 : 1), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(emphasized ? AccessStyle.primary.opacity(0.25) : AccessStyle.border)
            )
        }.disabled(model.busy)
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
            } else if model.tokens.isEmpty {
                ContentUnavailableView("Your wallet starts here", systemImage: "wallet.pass", description: Text("Deposit funds to start using your account."))
            } else {
                VStack(spacing: 0) {
                    ForEach(model.tokens) { token in
                        Button { selectedToken = token } label: {
                            tokenRow(token)
                        }.buttonStyle(.plain)
                        if token.id != model.tokens.last?.id {
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

struct WalletTokenIcon: View {
    let symbol: String
    var body: some View {
        ZStack {
            Circle().fill(symbol == "USDC" ? Color.blue.opacity(0.12) : AccessStyle.brand.opacity(0.08))
            if symbol == "USDC" { Text("$").font(.title2.weight(.medium)).foregroundStyle(.blue) }
            else if symbol == "XLM" { Image(systemName: "sparkle").font(.title2).foregroundStyle(AccessStyle.brand) }
            else { Text(String(symbol.prefix(2))).font(.subheadline.weight(.semibold)).foregroundStyle(AccessStyle.brand) }
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
