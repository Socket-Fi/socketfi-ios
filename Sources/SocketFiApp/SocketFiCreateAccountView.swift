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
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(AccessStyle.brand)
                            .accessibilityHidden(true)
                        Text("Make it yours")
                            .font(.largeTitle.bold())
                            .tracking(-0.8)
                        Text("Choose a username for your SocketFi account.")
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
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border))
                        .disabled(isWorking)

                        Text(valid
                             ? "You can change the suggestion. Availability is checked when you continue."
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
                            .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(AccessButtonStyle())
                        .disabled(!valid || isWorking)
                        .opacity(valid ? 1 : 0.5)
                        Text("Your passkey securely signs you in. No password to remember.")
                            .font(.footnote)
                            .foregroundStyle(AccessStyle.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
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
