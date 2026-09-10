import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import SocketFiNativeKit

struct SocketFiReceiveView: View {
    @ObservedObject var model: SocketFiWalletModel
    let addressOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var payload: String { addressOnly ? model.session.account.address : model.depositURL.absoluteString }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(addressOnly ? "SocketFiWallet" : "SocketFiReceive")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .frame(width: 56, height: 56)
                            .background(AccessStyle.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        Text(addressOnly ? "Your account" : "Receive funds").font(.title2.weight(.semibold))
                        Text(addressOnly ? "Your public SocketFi smart account address." : "Share your deposit link or open it to deposit from a Stellar wallet.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let qr = qrImage(payload) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 200, height: 200).padding(20)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel(addressOnly ? "Account address QR code" : "Deposit link QR code")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(addressOnly ? "Account address" : "Deposit link").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(model.networkLabel).font(.caption.weight(.semibold)).foregroundStyle(AccessStyle.brand)
                        }
                        Text(payload).font(.footnote.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = payload
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                            ShareLink(item: payload) {
                                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                        }
                    }.padding(18).background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    WalletNotice(title: "Use the correct network", message: addressOnly
                        ? "This is a C… smart account on \(model.networkLabel). Use a wallet that supports transfers to contract addresses. Exchanges may not accept this address; use your deposit link when needed."
                        : "Send only assets on \(model.networkLabel). The deposit page lets the sending wallet sign the transfer; it never needs your SocketFi passkey.")
                    if !addressOnly {
                        Link(destination: model.depositURL) {
                            Label("Open deposit page", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.borderedProminent).tint(AccessStyle.primary)
                    } else {
                        Link(destination: model.explorerURL) { Label("View account on explorer", systemImage: "arrow.up.right.square") }
                    }
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(AccessStyle.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
