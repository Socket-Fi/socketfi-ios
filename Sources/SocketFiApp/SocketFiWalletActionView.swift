import SwiftUI
import SocketFiNativeKit

struct SocketFiWalletActionView: View {
    @ObservedObject var model: SocketFiWalletModel
    let action: SocketFiWalletModel.Action
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @FocusState private var recipientFocused: Bool

    private var isSwap: Bool { action == .swap }
    private var permitted: Bool { isSwap ? model.supportsSwaps : model.canWithdraw }
    private var hasRecipient: Bool { SocketFiXDR.isAddress(model.recipient.trimmingCharacters(in: .whitespacesAndNewlines)) && model.recipient.trimmingCharacters(in: .whitespacesAndNewlines) != model.session.account.address }

    private var amountError: String? {
        guard !model.amount.isEmpty, let token = model.from else { return nil }
        do { _ = try SocketFiWalletClient.spendAmount(model.amount, token: token); return nil }
        catch { return error.localizedDescription }
    }

    private var canSubmit: Bool {
        guard !model.busy, !model.unresolved, permitted, !model.amount.isEmpty, let from = model.from, (try? SocketFiWalletClient.spendAmount(model.amount, token: from)) != nil else {
            return false
        }
        if isSwap {
            return !model.toID.isEmpty && model.fromID != model.toID
        }
        return hasRecipient
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = model.actionError {
                        WalletNotice(title: "Couldn't continue", message: error, systemImage: "exclamationmark.circle")
                    }
                    if let result = model.actionResult {
                        resultContent(result)
                    } else if let request = model.review {
                        if model.busy { approvalProgress }
                        reviewContent(request.review)
                    } else {
                        if model.busy { approvalProgress }
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
                    if model.unresolved && model.actionResult == nil {
                        WalletNotice(
                            title: "Complete previous payment check",
                            message: "Check the linked account activity before making another payment."
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            // A new review/result starts at the top, independent of the form's
            // keyboard and scroll offset. Keep the sheet itself mounted.
            .id(model.actionResult != nil ? "result" : model.review != nil ? "review" : model.busy ? "preparing" : "entry")
            .scrollDismissesKeyboard(.interactively)
            .background(AccessStyle.background.ignoresSafeArea())
            .navigationTitle(model.actionResult != nil ? "Transaction status" : model.review == nil ? (isSwap ? "Swap" : "Withdraw") : "Review transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.actionResult != nil ? "Done" : model.review == nil ? "Cancel" : "Back") {
                        if model.actionResult != nil { dismiss(); return }
                        if model.review != nil {
                            model.review = nil
                            model.quote = nil
                        } else {
                            dismiss()
                        }
                    }.disabled(model.busy)
                }
                ToolbarItem(placement: .topBarTrailing) { Text(model.networkLabel).font(.caption.weight(.semibold)) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; recipientFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationBackground(AccessStyle.background)
        .background(AccessStyle.background.ignoresSafeArea())
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
            model.review = nil
            model.actionError = nil
        }
    }

    private var actionHeader: some View {
        HStack(spacing: 12) {
            Image(isSwap ? "SocketFiSwap" : "SocketFiSend")
                .resizable().scaledToFit().padding(8)
                .frame(width: 44, height: 44)
                .background(AccessStyle.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(isSwap ? "Exchange assets" : "Send to another account")
                    .font(.headline)
                Text(isSwap ? "Review a fresh quote before approving." : "Use a Stellar G… or C… recipient address.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
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
            if let amountError { Text(amountError).font(.caption).foregroundStyle(.red) }
            TextField("0.00", text: $model.amount)
                .font(.system(.largeTitle, design: .rounded).weight(.medium))
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .accessibilityLabel("Amount to \(isSwap ? "swap" : "withdraw")")
                .accessibilityIdentifier("withdraw.amount")
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
            HStack(alignment: .top, spacing: 8) {
                TextField("Stellar G… or C… address", text: $model.recipient, axis: .vertical)
                    .font(.footnote.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lineLimit(2...4)
                    .focused($recipientFocused)
                    .accessibilityIdentifier("withdraw.recipient")
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { model.recipient = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Paste recipient address")
                .accessibilityIdentifier("withdraw.paste")
            }
            .padding(16)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .disabled(model.busy)
            if !model.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasRecipient {
                Text(model.recipient.trimmingCharacters(in: .whitespacesAndNewlines) == model.session.account.address ? "Choose a different destination from this wallet." : "Enter a valid Stellar G… or C… address.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Memo-based exchange deposits are not supported by this transfer flow. Confirm destination details before submitting.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
                DisclosureGroup("Account and token details") {
                    VStack(alignment: .leading, spacing: 16) {
                        reviewRow("From your account", value: review.source, address: true)
                        reviewRow("Token contract", value: model.from?.contract ?? "", address: true)
                        if isSwap, let to = model.to {
                            reviewRow("Receive token contract", value: to.contract, address: true)
                        }
                    }.padding(.top, 12)
                }
                Text("Network fees are handled by SocketFi. A fee estimate is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))

            if !model.busy { TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(review.expiresAt.timeIntervalSince(context.date)))
                Text(
                    context.date < review.expiresAt
                    ? "Review expires in \(seconds)s"
                    : "This review has expired. Go back and review again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } }

            Label("Approve only if the details are correct.", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var approvalProgress: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().tint(AccessStyle.brand).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.phase).font(.subheadline.weight(.semibold))
                Text(model.unresolved ? "Sending your payment and checking its final status." : model.review == nil ? "Checking the latest balance and payment details." : "Your payment details stay here while you approve.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(AccessStyle.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultContent(_ result: SocketFiWalletModel.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: result.confirmed ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 48)).foregroundStyle(AccessStyle.brand)
            Text(result.confirmed ? "Transaction confirmed" : "Check transaction status")
                .font(.title2.weight(.semibold))
            if let review = model.review?.review {
                Text(review.amount ?? "").font(.largeTitle.weight(.semibold)).monospacedDigit()
                reviewRow("Recipient", value: review.destination, address: true)
                reviewRow("Network", value: model.networkLabel)
            }
            Text(result.confirmed ? "The network confirmed your transaction." : "The final result is not available yet. Check your account activity before sending again.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let hash = result.hash {
                Text(hash).font(.footnote.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("wallet.receipt").accessibilityValue(hash)
                Link("View transaction", destination: model.transactionURL(hash))
            } else {
                Link("View account activity", destination: model.explorerURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
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
                if model.actionResult != nil {
                    Button { dismiss() } label: {
                        Text("Done").frame(maxWidth: .infinity, minHeight: 52)
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(AccessStyle.primary)
                } else {
                if model.busy {
                    Text(model.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !permitted {
                    Text(isSwap ? "Swaps are unavailable for this app." : "Withdrawals are unavailable for this app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.busy && !model.unresolved && model.review != nil {
                    Button(model.session.account.signer == .evmWallet ? "Cancel wallet approval" : "Cancel approval") { model.cancelApproval() }
                }
                Button {
                    amountFocused = false
                    recipientFocused = false
                    Task {
                        if model.review != nil {
                            model.startApproval()
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
                            : model.approvalTitle
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
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}
