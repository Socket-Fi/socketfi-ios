import SwiftUI
import SocketFiNativeKit

/// The approval surface that must be shown immediately before a passkey
/// assertion. The caller must bind the review to the exact transaction args;
/// the native API does not currently return a human-readable review model.
struct SocketFiTransactionReviewView: View {
    let review: SocketFiTransactionReview
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Operation") {
                    LabeledContent("Action", value: review.title)
                    LabeledContent("Network", value: review.network.rawValue)
                    LabeledContent("From", value: review.source)
                    LabeledContent("To", value: review.destination)
                }
                if let amount = review.amount {
                    Section("Amount") {
                        Text(amount).font(.title3.weight(.semibold))
                    }
                }
                if let fee = review.fee {
                    Section("Estimated fee") {
                        Text(fee)
                    }
                }
                if let minimum = review.minimumReceived {
                    Section("Minimum received") { Text(minimum) }
                }
                if let slippage = review.slippage {
                    Section("Slippage tolerance") { Text(slippage) }
                }
                Section {
                    Text("This approval uses your SocketFi owner passkey. Review the destination and amount carefully before continuing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve", action: onApprove)
                        .bold()
                }
            }
        }
    }
}
