import SwiftUI
import SocketFiNativeKit

struct SocketFiCreateAccountView: View {
    @ObservedObject var model: SocketFiAppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var usernameFocused: Bool
    @State private var username = SocketFiUsername.suggested()
    @State private var isWorking = false
    @State private var creationTask: Task<Void, Never>?

    private var valid: Bool { SocketFiUsername.isValid(username) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose your username")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-0.8)
                        Text("Your new SocketFi account will be secured with a passkey.")
                            .font(.body)
                            .foregroundStyle(AccessStyle.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Username").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Text("@").foregroundStyle(AccessStyle.secondary)
                            TextField("Your username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .keyboardType(.asciiCapable)
                                .submitLabel(.go)
                                .focused($usernameFocused)
                                .accessibilityLabel("Username")
                                .onSubmit { createAccount() }
                        }
                        .padding(18)
                        .background(AccessStyle.background, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                            usernameFocused ? AccessStyle.brand : AccessStyle.border,
                            lineWidth: usernameFocused ? 2 : 1
                        ))
                        .disabled(isWorking)

                        Text(valid
                             ? "Make this username your own."
                             : "Use 3–30 letters, numbers, _ or -. Start and end with a letter or number.")
                            .font(.footnote)
                            .foregroundStyle(valid ? AccessStyle.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Account creation error: \(message)")
                    }

                    VStack(spacing: 14) {
                        Button(action: createAccount) {
                            HStack(spacing: 10) {
                                if isWorking { ProgressView().tint(.white) }
                                Text(isWorking ? "Creating account…" : "Continue with passkey")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(.white)
                            .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(AccessButtonStyle())
                        .disabled(!valid || isWorking)
                        .opacity(valid ? 1 : 0.5)
                            Text("Your passkey stays on this device and is never shared with SocketFi.")
                                .font(.footnote)
                            .foregroundStyle(AccessStyle.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AccessStyle.surface)
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { model.errorMessage = nil; dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onChange(of: username) { _, value in
            username = SocketFiUsername.normalize(value)
            model.errorMessage = nil
        }
        .onDisappear { creationTask?.cancel() }
    }

    private func createAccount() {
        guard valid, !isWorking else { return }
        usernameFocused = false
        isWorking = true
        let chosenUsername = username
        creationTask = Task {
            defer { isWorking = false }
            await model.authenticate(method: .passkey, mode: .signUp, username: chosenUsername)
        }
    }
}
