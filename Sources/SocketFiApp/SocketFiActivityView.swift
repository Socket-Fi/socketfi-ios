import SwiftUI
import SocketFiNativeKit

struct SocketFiActivityView: View {
    @ObservedObject var model: SocketFiWalletModel
    @StateObject private var history: SocketFiHistoryModel
    @Environment(\.scenePhase) private var scenePhase

    init(model: SocketFiWalletModel) {
        self.model = model
        let client = SocketFiHistoryClient(configuration: model.configuration)
        let session = model.session
        _history = StateObject(wrappedValue: SocketFiHistoryModel { cursor in
            try await client.load(session: session, cursor: cursor)
        })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("\(model.networkLabel) account activity")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.unresolved, let receipt = model.receipt {
                    ActivityReceiptCard(receipt: receipt, action: { model.acknowledgeCheckedActivity() })
                    if let hash = receipt.hash {
                        Link("View latest transaction", destination: model.transactionURL(hash))
                    }
                }
                if let error = history.error {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(history.items.isEmpty ? "History unavailable" : "History couldn’t refresh", systemImage: "wifi.exclamationmark")
                            .font(.headline)
                        Text(error).font(.subheadline)
                        Button("Retry") { Task { await history.refresh() } }
                            .frame(minHeight: 44)
                            .disabled(history.loading || history.loadingMore)
                            .accessibilityIdentifier("history.retry")
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                if history.loading && history.items.isEmpty {
                    ProgressView("Loading transactions…").frame(maxWidth: .infinity).padding(30)
                } else if history.loaded && history.items.isEmpty && history.error == nil {
                    ContentUnavailableView("No indexed activity yet", systemImage: "clock",
                        description: Text("Transfers and account activity will appear here after indexing. Pull down to refresh."))
                        .accessibilityIdentifier("history.empty")
                }
                ForEach(history.items) { item in
                    NavigationLink {
                        SocketFiHistoryDetailView(item: item)
                    } label: {
                        HistoryRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.item.\(item.id)")
                    .accessibilityValue(item.txHash)
                }
                if let error = history.pageError {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("history.pageError")
                }
                if history.nextCursor != nil {
                    Button {
                        Task { await history.loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            if history.loadingMore { ProgressView() }
                            Text(history.pageError == nil ? "Load older activity" : "Retry older activity")
                            Spacer()
                        }.padding()
                    }
                    .disabled(history.loading || history.loadingMore)
                    .accessibilityIdentifier("history.loadMore")
                }
                if let updated = history.updatedAt {
                    Text("History refreshed \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: model.explorerURL) {
                    Label("View account in explorer", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Indexing can lag behind network confirmation. Refresh to check for new activity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(AccessStyle.background.ignoresSafeArea())
        .refreshable { await history.refresh() }
        .task { await history.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await history.refresh() } }
        }
    }
}

private struct HistoryRow: View {
    let item: SocketFiHistoryItem
    private var incoming: Bool { ["incoming", "IN"].contains(item.direction ?? "") }
    private var outgoing: Bool { ["outgoing", "OUT"].contains(item.direction ?? "") }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: !item.successful ? "exclamationmark.circle" : incoming ? "arrow.down.left" : outgoing ? "arrow.up.right" : "arrow.left.arrow.right")
                .font(.title3).foregroundStyle(item.successful ? AccessStyle.brand : Color.red)
                .frame(width: 38, height: 38)
                .background(AccessStyle.background, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(item.successful ? "Confirmed" : "Failed")
                        .font(.caption.weight(.medium)).foregroundStyle(item.successful ? Color.secondary : Color.red)
                }
                if let amount = item.amountText {
                    Text("\(item.successful ? (incoming ? "+" : outgoing ? "−" : "") : "")\(amount)\(item.symbol.isEmpty ? "" : " " + item.symbol)")
                        .font(.body.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                } else if !item.symbol.isEmpty { Text(item.symbol).font(.subheadline) }
                HStack {
                    Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? "Time unavailable")
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct SocketFiHistoryDetailView: View {
    let item: SocketFiHistoryItem
    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: item.successful ? "Confirmed" : "Failed")
                LabeledContent("Network", value: item.network == .testnet ? "Stellar Testnet" : "Stellar Mainnet")
                if let date = item.date { LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let amount = item.amountText { LabeledContent(item.successful ? "Amount" : "Attempted amount", value: "\(amount) \(item.symbol)") }
                if !item.successful { Text("This transaction failed. The displayed amount was not confirmed as transferred.").font(.caption) }
            }
            Section("Addresses") {
                detail("Account", item.walletAddress)
                detail("From", item.fromAddress)
                detail("To", item.toAddress)
                detail("Asset contract", item.assetContract)
                detail("Invoked contract", item.invokedContract)
            }
            Section("Transaction") {
                detail("Hash", item.txHash)
                detail("Ledger", item.ledger)
                detail("Function", item.functionName)
                detail("Memo", item.memoValue)
                if let fee = item.feeChargedStroops {
                    LabeledContent("Network fee", value: "\(SocketFiAmount.display(fee, decimals: 7)) XLM")
                    Text("The network fee may be paid by a sponsor.").font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: item.explorerURL) { Label("View on Stellar Expert", systemImage: "arrow.up.right.square") }
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("history.detail")
    }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.footnote.monospaced()).textSelection(.enabled)
            }
        }
    }
}
