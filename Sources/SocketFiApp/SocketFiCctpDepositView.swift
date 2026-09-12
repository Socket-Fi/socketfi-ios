import SwiftUI
import SocketFiNativeKit

struct SocketFiCctpDepositView: View {
    @StateObject private var model: SocketFiCctpDepositModel
    @ObservedObject private var connection = SocketFiWalletConnect.shared
    private let onComplete: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var recoveryHash = ""
    @State private var cancelPreparation = false
    @State private var selectingNetwork = false
    @FocusState private var amountFocused: Bool

    init(wallet: SocketFiWalletModel, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _model = StateObject(wrappedValue: SocketFiCctpDepositModel(session: wallet.session, configuration: wallet.configuration))
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Color.clear.frame(height: 0).id("depositTop")
                if model.pending == nil {
                    Text("USDC from EVM").font(.title2.weight(.semibold))
                }
                if let pending = model.pending { deposit(pending) }
                else { form }
                if let error = model.error {
                    WalletNotice(title: "Deposit update", message: error, systemImage: "info.circle")
                }
                if model.pending != nil {
                Link(destination: model.explorerURL) {
                    Label("Track in SocketFi explorer", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                }
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .onChange(of: model.pending?.phase) { _, _ in
            withAnimation { proxy.scrollTo("depositTop", anchor: .top) }
        }
        }
        .safeAreaInset(edge: .bottom) {
            actions.padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial)
        }
        .background(AccessStyle.background.ignoresSafeArea())
        .navigationTitle("Deposit from EVM")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .navigationBarBackButtonHidden(model.busy)
        .interactiveDismissDisabled(model.busy)
        .sheet(isPresented: $connection.showingPicker) {
            SocketFiWalletPicker(connection: connection, cancel: model.cancelConnection)
        }
        .sheet(isPresented: $selectingNetwork) { networkSelection }
        .confirmationDialog("Cancel this preparation?", isPresented: $cancelPreparation, titleVisibility: .visible) {
            Button("Cancel preparation", role: .destructive) { model.discard(); Task { await model.load() } }
        } message: { Text("No deposit will be sent. An approved USDC spending limit may remain in your funding wallet; you can manage it there.") }
        .task {
            await model.load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                if scenePhase == .active, let pending = model.pending,
                   pending.phase == .tracking || pending.phase == .burnRequested || pending.phase == .approvalRequested {
                    await model.refresh()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private func networkIcon(_ chainID: Int) -> some View {
        let asset: String?
        switch chainID {
        case 1, 11155111: asset = "NetworkEthereum"
        case 42161, 421614: asset = "NetworkArbitrum"
        case 8453, 84532: asset = "NetworkBase"
        case 43114, 43113: asset = "NetworkAvalanche"
        case 10, 11155420: asset = "NetworkOptimism"
        case 137, 80002: asset = "NetworkPolygon"
        case 56, 97: asset = "NetworkBNB"
        default: asset = nil
        }
        return Group {
            if let asset {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: "network").resizable().scaledToFit()
            }
        }.frame(width: 32, height: 32).accessibilityHidden(true)
    }

    private var networkSelection: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.chains) { chain in
                        Button {
                            model.chainID = chain.chainId
                            selectingNetwork = false
                        } label: {
                            HStack(spacing: 12) {
                                networkIcon(chain.chainId)
                                Text(chain.label).foregroundStyle(.primary)
                                Spacer()
                                if model.chainID == chain.chainId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AccessStyle.brand)
                                }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("cctp.network.\(chain.chainId)")
                        .accessibilityAddTraits(model.chainID == chain.chainId ? .isSelected : [])
                    }
                } header: { Text(model.session.account.network.rawValue) }
                footer: { Text("Choose the network holding your USDC. Enable it in your funding wallet before connecting.") }
            }
            .navigationTitle("Select network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectingNetwork = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.chains.isEmpty {
                if model.loadingChains {
                    ProgressView("Loading source networks…")
                } else {
                    Button("Retry loading networks") { Task { await model.load() } }.disabled(model.storageFailed)
                }
            } else {
                Button { amountFocused = false; selectingNetwork = true } label: {
                    HStack(spacing: 12) {
                        networkIcon(model.chainID)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From network").font(.caption).foregroundStyle(.secondary)
                            Text(model.selectedChain?.label ?? "Select network").font(.headline)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.subheadline.weight(.semibold))
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("cctp.sourceNetwork")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Amount in USDC").font(.subheadline.weight(.medium))
                    TextField("0.00", text: $model.amount).keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.title.weight(.medium)).padding(14)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("cctp.amount")
                    Text("Native USDC only · USDC.e isn’t supported by CCTP.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Speed", selection: $model.speed) {
                    Text("Standard").tag("STANDARD")
                    Text("Fast").tag("FAST")
                }.pickerStyle(.segmented)

            }
            recipient
            DisclosureGroup("How it works") {
                Text("Connect your funding wallet, approve USDC, then confirm the deposit. Your SocketFi sign-in stays the same.")
                Text("Enable the selected network in your wallet first. Test networks may need its testnet setting turned on.")
                Text("Fast availability varies by route. Review the fee before signing; wallet gas is separate.")
            }.font(.footnote).foregroundStyle(.secondary)
        }.disabled(model.busy)
    }

    private var recipient: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To your SocketFi account · \(model.session.account.network.rawValue)")
                .font(.subheadline.weight(.semibold))
            DisclosureGroup {
                Text(model.session.account.address).font(.caption.monospaced()).textSelection(.enabled)
            } label: {
                Text(model.session.account.address).font(.caption.monospaced())
                    .lineLimit(1).truncationMode(.middle)
            }
        }.padding(16).background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func deposit(_ pending: SocketFiCctpPending) -> some View {
        WalletNotice(title: statusTitle(pending), message: statusMessage(pending),
                     systemImage: pending.phase == .complete ? "checkmark.circle.fill" : "info.circle")
        VStack(alignment: .leading, spacing: 14) {
            Text("\(pending.amount) USDC").font(.largeTitle.weight(.semibold))
            row("From", pending.chain.label)
            if pending.phase != .complete {
            row("Speed", pending.speed == "FAST" ? "Fast" : "Standard")
            if let prepared = pending.prepared {
                row("Maximum bridge fee", SocketFiAmount.display(prepared.maxFee, decimals: 6) + " USDC")
                if !pending.burnMayHaveBeenSent { row("Estimated arrival", prepared.eta) }
            }
            }
            DisclosureGroup("Transaction details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Funding account").foregroundStyle(.secondary)
                    Text(pending.sender).font(.caption.monospaced()).textSelection(.enabled)
                    if !pending.burnMayHaveBeenSent, let ready = model.readiness {
                        row("USDC balance", SocketFiAmount.display(ready.balance, decimals: 6))
                    }
                    if pending.phase != .complete {
                        Text("Gas is paid separately and shown in your wallet.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }.font(.subheadline)
        }.padding(18).background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        recipient
        if !model.busy {
            if !pending.burnMayHaveBeenSent {
                if pending.phase != .approvalRequested {
                    Button("Reconnect funding wallet", action: model.reconnect).frame(minHeight: 44)
                }
                Button("Cancel preparation", role: .destructive) { cancelPreparation = true }
                    .frame(minHeight: 44)
            }
        }
        if pending.burnMayHaveBeenSent, pending.burnHash == nil {
            DisclosureGroup("Already approved? Add transaction hash") {
                Text("Copy the deposit transaction hash from your EVM wallet. SocketFi verifies its sender, amount, route, and recipient before settlement.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("0x… transaction hash", text: $recoveryHash).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { recoveryHash = $0.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                        .labelStyle(.iconOnly).accessibilityLabel("Paste deposit transaction hash")
                }.padding(.vertical, 10)
                Button("Check transaction") { model.recover(hash: recoveryHash) }
                    .disabled(model.busy || !SocketFiCctpABI.isHash(recoveryHash))
            }
        }
        if let hash = pending.burnHash {
            DisclosureGroup("Deposit transaction") { Text(hash).font(.caption.monospaced()).textSelection(.enabled) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.busy {
            HStack(spacing: 12) {
                ProgressView()
                Text(model.message).font(.subheadline)
            }.frame(maxWidth: .infinity, minHeight: 50)
        } else if let pending = model.pending {
            switch pending.phase {
            case .draft: primary("Retry preparation", action: model.retryPreparation)
            case .review: primary("Approve USDC spending limit", action: model.approveUSDC)
            case .approved: primary("Confirm deposit", action: model.deposit)
            case .approvalRequested, .burnRequested, .tracking:
                primary("Refresh status") { Task { await model.refresh() } }
            case .complete:
                primary("Done") { if model.finish() { onComplete() } }
                    .accessibilityIdentifier("cctp.done")
            }
        } else {
            primary("Connect wallet & review") { amountFocused = false; model.start() }
                .disabled(!model.canStart)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 50) }
            .buttonStyle(.borderedProminent).tint(AccessStyle.primary)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.subheadline)
    }
    private func statusTitle(_ pending: SocketFiCctpPending) -> String {
        if pending.phase == .complete { return "Deposit confirmed" }
        if ["FAILED_FINAL", "EXPIRED", "SUPERSEDED"].contains(pending.status ?? "") { return "Deposit needs attention" }
        switch pending.phase {
        case .draft: return "Preparing deposit"
        case .review: return "1. Approve USDC"
        case .approvalRequested: return "Waiting for USDC approval"
        case .approved: return "USDC approved · Step 2 of 2"
        case .burnRequested: return "Checking wallet submission"
        default: return "Deposit in progress"
        }
    }
    private func statusMessage(_ pending: SocketFiCctpPending) -> String {
        if pending.phase == .complete { return "The Stellar network confirmed delivery to your SocketFi account." }
        if ["FAILED_FINAL", "EXPIRED", "SUPERSEDED"].contains(pending.status ?? "") {
            return "Check this deposit in SocketFi’s explorer. Do not repeat a burn that was already approved; its funds may still need settlement."
        }
        switch pending.phase {
        case .draft: return "No transaction has been sent. Retry uses the same deposit identifier."
        case .review: return "First, approve the displayed USDC spending limit in your wallet."
        case .approvalRequested: return "Check your funding wallet and refresh. SocketFi will not resend the approval automatically."
        case .approved: return "Spending approved. Confirm the deposit transaction in your wallet next."
        case .burnRequested: return "The wallet may have submitted your deposit. SocketFi is checking; it will not send another burn. You can close this screen and return later."
        default: return "Your deposit is on its way. You can close this screen and track it later."
        }
    }
}
