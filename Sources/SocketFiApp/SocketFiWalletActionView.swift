import SwiftUI
import SocketFiNativeKit

struct SocketFiWalletActionView: View {
    @ObservedObject var model: SocketFiWalletModel
    let action: SocketFiWalletModel.Action
    @Environment(\.dismiss) private var dismiss
    @State private var noMemoRequired = false
    @FocusState private var amountFocused: Bool

    private var isSwap: Bool { action == .swap }
    private var permitted: Bool { isSwap ? model.supportsSwaps : model.canWithdraw }

    private var canSubmit: Bool {
        guard !model.busy, !model.unresolved, permitted, !model.amount.isEmpty else {
            return false
        }
        if isSwap {
            return !model.toID.isEmpty && model.fromID != model.toID
        }
        return noMemoRequired && !model.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let request = model.review {
                        reviewContent(request.review)
                    } else {
                        actionHeader
                        if let from = model.from {
                            fromAssetRow(from)
                        }
                        amountCard
                        if isSwap { swapFields } else { withdrawalFields }
                        if !permitted {
                            WalletNotice(
                                title: isSwap ? "Swaps aren't available yet" : "Withdrawals unavailable",
                                message: "This app's transaction permissions must allow this action for \(model.networkLabel). Funds remain in your account."
                            )
                        }
                    }
                    if model.unresolved {
                        WalletNotice(
                            title: "Complete previous payment check",
                            message: "Check the linked account activity before making another payment."
                        )
                    }
                    if let error = model.actionError {
                        WalletNotice(title: "Couldn't continue", message: error, systemImage: "exclamationmark.circle")
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AccessStyle.background.ignoresSafeArea())
            .navigationTitle(model.review == nil ? (isSwap ? "Swap" : "Withdraw") : "Review transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.review == nil ? "Cancel" : "Back") {
                        if model.review != nil {
                            model.review = nil
                            model.quote = nil
                        } else {
                            dismiss()
                        }
                    }.disabled(model.busy)
                }
                ToolbarItem(placement: .topBarTrailing) { Text(model.networkLabel).font(.caption.weight(.semibold)) }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .tint(AccessStyle.brand)
        .interactiveDismissDisabled(model.busy)
        .onChange(of: model.amount) { _, _ in
            model.invalidateQuote()
            model.actionError = nil
        }
        .onChange(of: model.fromID) { _, _ in
            model.invalidateQuote()
            model.actionError = nil
        }
        .onChange(of: model.toID) { _, _ in
            model.invalidateQuote()
            model.actionError = nil
        }
        .onChange(of: model.slippageBps) { _, _ in
            model.invalidateQuote()
            model.actionError = nil
        }
        .onChange(of: model.recipient) { _, _ in
            noMemoRequired = false
            model.review = nil
            model.actionError = nil
        }
    }

    private var actionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(isSwap ? "SocketFiSwap" : "SocketFiSend")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .padding(10)
                .frame(width: 52, height: 52)
                .background(AccessStyle.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text(isSwap ? "Exchange assets" : "Send to another account")
                .font(.title2.weight(.semibold))
            Text(
                isSwap
                ? "Get a fresh quote, then approve the transaction with your passkey."
                : "Choose an asset and enter a Stellar recipient address."
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func fromAssetRow(_ token: SocketFiToken) -> some View {
        HStack(spacing: 12) {
            WalletTokenIcon(symbol: token.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text("From asset").font(.caption).foregroundStyle(.secondary)
                Text(token.symbol).font(.body.weight(.semibold))
            }
            Spacer(minLength: 4)
            Text(model.hideBalances ? "••••" : token.balanceText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(16)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isSwap ? "You pay" : "Amount").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("Asset", selection: $model.fromID) {
                    ForEach(model.tokens) { token in
                        Text(token.symbol).tag(token.id)
                    }
                }.labelsHidden()
                .disabled(model.busy)
            }
            TextField("0.00", text: $model.amount)
                .font(.system(.largeTitle, design: .rounded).weight(.medium))
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .accessibilityLabel("Amount to \(isSwap ? "swap" : "withdraw")")
                .disabled(model.busy)
            HStack {
                Text("Available: \(model.from?.balanceText ?? "—") \(model.from?.symbol ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Max") {
                    model.amount = model.from?.balanceText ?? ""
                }
                .font(.caption.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(model.from?.availableBalance == nil || model.busy)
            }
        }
        .padding(20)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var withdrawalFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipient").font(.subheadline.weight(.semibold))
            TextField("Stellar G… or C… address", text: $model.recipient, axis: .vertical)
                .font(.footnote.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(2...4)
                .padding(16)
                .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .disabled(model.busy)
            Toggle(isOn: $noMemoRequired) {
                Text("This recipient does not require a memo.")
                    .font(.footnote)
            }
            .disabled(model.busy)
            Text("Memo-based exchange deposits are not supported by this transfer flow. Confirm destination details before submitting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var swapFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("You receive").font(.subheadline.weight(.semibold))
                Spacer()
                if model.tokens.filter({ $0.id != model.fromID }).isEmpty {
                    Text("No alternate tokens available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Receive asset", selection: $model.toID) {
                        Text("Choose token").tag("")
                        ForEach(model.tokens.filter { $0.id != model.fromID }) { token in
                            Text(token.symbol).tag(token.id)
                        }
                    }.labelsHidden()
                    .disabled(model.busy)
                }
            }
            .padding(18)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))

            Text("Slippage tolerance")
                .font(.subheadline.weight(.semibold))
            Picker("Slippage tolerance", selection: $model.slippageBps) {
                Text("0.1%").tag(10)
                Text("0.5%").tag(50)
                Text("1%").tag(100)
            }.pickerStyle(.segmented)
                .disabled(model.busy)

            Text("Your swap will fail if the quoted route cannot satisfy the minimum output amount.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewContent(_ review: SocketFiTransactionReview) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isSwap ? "You pay" : "You're sending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(review.amount ?? "—")
                    .font(.largeTitle.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 16) {
                if isSwap, let quote = model.quote, let to = model.to {
                    reviewRow("Estimated receive", value: "\(SocketFiAmount.display(quote.quotedOutAtomic, decimals: to.decimals)) \(to.symbol)")
                }
                if let minimum = review.minimumReceived {
                    reviewRow("Minimum received", value: minimum)
                }
                if let slippage = review.slippage {
                    reviewRow("Slippage tolerance", value: slippage)
                }
                reviewRow("Network", value: model.networkLabel)
                reviewRow(isSwap ? "Aquarius router" : "Recipient", value: review.destination, address: true)
                reviewRow("From your account", value: review.source, address: true)
                reviewRow("Token contract", value: model.from?.contract ?? "", address: true)
                if isSwap, let to = model.to {
                    reviewRow("Receive token contract", value: to.contract, address: true)
                }
                Text("Paymaster handles network fees. Fee details are not surfaced by the current API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(review.expiresAt.timeIntervalSince(context.date)))
                Text(
                    context.date < review.expiresAt
                    ? "Review expires in \(seconds)s"
                    : "This review has expired. Open a fresh quote."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label("Approve only if the details are correct.", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewRow(_ label: String, value: String, address: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(address ? .footnote.monospaced() : .subheadline.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                if model.busy {
                    Text(model.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    amountFocused = false
                    Task {
                        if model.review != nil {
                            await model.approve()
                        } else {
                            await model.prepare()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if model.busy { ProgressView().tint(.white) }
                        else {
                            Image(systemName: model.review == nil ? "arrow.right" : "person.badge.key.fill")
                        }
                        Text(
                            model.review == nil
                            ? (isSwap ? "Get quote" : "Review withdrawal")
                            : "Approve with passkey"
                        )
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(AccessStyle.primary)
                .disabled(
                    model.busy ||
                    model.unresolved ||
                    !canSubmit ||
                    (model.review.map { $0.review.expiresAt <= context.date } ?? false)
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}
