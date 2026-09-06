import SwiftUI
import SocketFiNativeKit

/// The approval surface that must be shown immediately before a passkey
/// assertion. It intentionally presents the server-provided review model and
/// does not derive financial meaning from an opaque transaction payload.
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
