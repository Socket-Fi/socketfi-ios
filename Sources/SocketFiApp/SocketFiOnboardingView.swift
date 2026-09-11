import SwiftUI
import SocketFiNativeKit

struct SocketFiSignInView: View {
    @ObservedObject var model: SocketFiAppModel
    @ObservedObject private var walletConnection = SocketFiWalletConnect.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPasskey = false
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 38

    private var busy: Bool { model.isAuthenticating || model.evmStage != nil || model.isDisconnectingEvm }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        SocketFiBrandMark()
                            .fill(AccessStyle.brand, style: FillStyle(eoFill: true))
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text("socketfi").font(.title3.weight(.semibold)).tracking(-0.5)
                        Spacer()
                        if model.configuration.network == .testnet {
                            Text("Testnet")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(AccessStyle.secondary)
                                .background(AccessStyle.surface.opacity(0.8), in: Capsule())
                        }
                    }

                    Spacer(minLength: 48)

                    Text("Your account.\nYour control.")
                        .font(.system(size: headlineSize, weight: .semibold))
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Create an account or pick up where you left off.")
                        .font(.body)
                        .foregroundStyle(AccessStyle.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    Spacer(minLength: 36)

                    if let stage = model.evmStage {
                        progressCard(stage)
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                model.errorMessage = nil
                                model.evmError = nil
                                model.evmNotice = nil
                                showingPasskey = true
                            } label: {
                                methodLabel(title: "Continue with passkey", subtitle: "Face ID, Touch ID, or device passcode", prominent: true)
                            }
                            .buttonStyle(AccessButtonStyle())
                            .accessibilityIdentifier("onboarding.passkey")
                            .disabled(busy)

                            Button { model.startEvm() } label: {
                                methodLabel(title: "Continue with EVM wallet",
                                            subtitle: "MetaMask, Trust, and more", prominent: false)
                            }
                            .buttonStyle(AccessButtonStyle())
                            .accessibilityIdentifier("onboarding.evm")
                            .disabled(busy)

                            Button {} label: {
                                methodLabel(title: "Continue with Stellar wallet",
                                            subtitle: "Coming soon · Freighter, xBull, LOBSTR",
                                            prominent: false, assetName: "SocketFiStellar", available: false)
                            }
                            .buttonStyle(AccessButtonStyle())
                            .disabled(true)
                            .accessibilityIdentifier("onboarding.stellar")
                            .accessibilityHint("Stellar wallet access is coming soon")
                        }

                        if let wallet = model.connectedWalletName {
                            HStack(spacing: 8) {
                                Text("\(wallet) connected")
                                    .font(.caption)
                                    .foregroundStyle(AccessStyle.secondary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Button { model.disconnectEvm() } label: {
                                    HStack(spacing: 6) {
                                        if model.isDisconnectingEvm { ProgressView().controlSize(.small) }
                                        Text("Change wallet").font(.caption.weight(.semibold))
                                    }
                                    .frame(minHeight: 44)
                                }
                                .disabled(busy)
                                .accessibilityIdentifier("onboarding.changeWallet")
                            }
                            .padding(.horizontal, 4)
                        }
                    }

                    if let message = model.evmError ?? model.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Couldn’t finish signing in", systemImage: "exclamationmark.circle")
                                .font(.subheadline.weight(.semibold))
                            Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                            if model.evmError != nil {
                                Button("Try again") { model.startEvm() }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                                    .disabled(busy)
                            }
                        }
                        .foregroundStyle(AccessStyle.text)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border))
                        .padding(.top, 16)
                        .accessibilityIdentifier("onboarding.error")
                    } else if let notice = model.evmNotice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(AccessStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    Label("You choose how to access your account.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(AccessStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                .foregroundStyle(AccessStyle.text)
                .frame(maxWidth: 460)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .background {
                ZStack(alignment: .top) {
                    AccessStyle.background
                    LinearGradient(colors: [Color.indigo.opacity(0.08), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 360)
                }.ignoresSafeArea()
            }
        }
        .tint(AccessStyle.brand)
        .onAppear { model.refreshEvmConnection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshEvmConnection() }
        }
        .sheet(isPresented: $walletConnection.showingPicker, onDismiss: {
            if model.evmStage == .connecting && !walletConnection.hasSelectedSession { model.cancelEvm() }
        }) {
            SocketFiWalletPicker(connection: walletConnection, cancel: model.cancelEvm)
        }
        .sheet(isPresented: $showingPasskey) {
            SocketFiPasskeySheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private func methodLabel(title: String, subtitle: String, prominent: Bool, assetName: String = "SocketFiEthereum", available: Bool = true) -> some View {
        HStack(spacing: 14) {
            Group {
                if prominent {
                    Image(systemName: "touchid").font(.system(size: 25, weight: .medium))
                } else {
                    Image(assetName).resizable().scaledToFit()
                }
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption)
                    .foregroundStyle(prominent ? Color.white.opacity(0.8) : AccessStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if available {
                Image(systemName: "arrow.right").font(.footnote.weight(.medium)).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 19)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .foregroundStyle(prominent ? .white : AccessStyle.text)
        .background(prominent ? AccessStyle.primary : AccessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(prominent ? Color.clear : AccessStyle.border))
    }

    private func progressCard(_ stage: SocketFiEvmAuthStage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProgressView().tint(AccessStyle.brand)
                Text(stage.onboardingTitle).font(.headline)
            }
            Text(stage.onboardingDetail)
                .font(.subheadline).foregroundStyle(AccessStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<3) { step in
                    Capsule()
                        .fill(step <= stage.onboardingStep ? AccessStyle.brand : AccessStyle.border)
                        .frame(height: 4)
                }
            }.accessibilityLabel("Step \(stage.onboardingStep + 1) of 3")
            if stage == .awaitingSignature {
                Button { model.reopenEvmWallet() } label: {
                    Label("Open \(model.connectedWalletName ?? "wallet")", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(AccessButtonStyle())
            }
            if stage != .submitting {
                Button("Cancel EVM sign-in") { model.cancelEvm() }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("onboarding.cancelEvm")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AccessStyle.border))
        .accessibilityIdentifier("onboarding.progress")
    }
}

extension SocketFiEvmAuthStage {
    var onboardingTitle: String {
        switch self {
        case .connecting: "Connect your wallet"
        case .preparing: "Preparing your sign-in"
        case .awaitingSignature: "Approve in your wallet"
        case .submitting: "Opening your account"
        }
    }

    var onboardingDetail: String {
        switch self {
        case .connecting: "Choose a wallet and approve the connection. You’ll return here to continue."
        case .preparing: "Your wallet is connected. We’re getting your secure signing request ready."
        case .awaitingSignature: "Review SocketFi’s message in your wallet, then return here. This signature confirms that you control the wallet."
        case .submitting: "Your signature is approved. We’re confirming your account. This can take a moment."
        }
    }

    var onboardingStep: Int {
        switch self {
        case .connecting: 0
        case .preparing, .awaitingSignature: 1
        case .submitting: 2
        }
    }
}
