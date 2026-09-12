import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import SocketFiNativeKit

struct SocketFiReceiveView: View {
    @ObservedObject var model: SocketFiWalletModel
    let addressOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showingEvmDeposit = false

    private var payload: String { addressOnly ? model.session.account.address : model.depositURL.absoluteString }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text(addressOnly ? "Your account" : "Receive funds").font(.title2.weight(.semibold))
                        Text(addressOnly ? "Your public SocketFi smart account address." : "Receive from a Stellar wallet or bridge USDC from EVM.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let qr = qrImage(payload) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 184, height: 184).padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel(addressOnly ? "Account address QR code" : "Deposit link QR code")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(addressOnly ? "Account address" : "Deposit link").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(model.networkLabel).font(.caption.weight(.semibold)).foregroundStyle(AccessStyle.brand)
                        }
                        Text(payload).font(.footnote.monospaced()).textSelection(.enabled)
                            .lineLimit(addressOnly ? nil : 1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = payload
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityIdentifier("deposit.copy")
                            ShareLink(item: payload) {
                                Label("Share", systemImage: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityIdentifier("deposit.share")
                            Spacer()
                        }.font(.subheadline.weight(.medium)).foregroundStyle(AccessStyle.brand)
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    if !addressOnly {
                        NavigationLink {
                            SocketFiCctpDepositView(wallet: model) {
                                dismiss()
                                Task { await model.refresh() }
                            }
                                .onAppear { showingEvmDeposit = true }
                                .onDisappear { showingEvmDeposit = false }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.left.circle.fill").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Deposit from EVM").font(.headline)
                                    Text("Bridge USDC with Circle CCTP").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.padding(18).background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.accessibilityIdentifier("deposit.evm")
                        Link(destination: model.depositURL) {
                            Label("Deposit from Stellar", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.borderedProminent).tint(AccessStyle.primary)
                    } else {
                        Link(destination: model.explorerURL) { Label("View account on explorer", systemImage: "arrow.up.right.square") }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(AccessStyle.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !showingEvmDeposit { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        }.tint(AccessStyle.brand)
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
