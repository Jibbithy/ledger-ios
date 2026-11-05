import SwiftUI

/// The one screen that ever sends a password over the wire. It is never
/// stored - see SessionStore's comment for why only the session cookie that
/// comes back from a successful login is worth keeping in the Keychain.
struct LoginView: View {
    var onSignedIn: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var checking = false
    @State private var problem: String?
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    var body: some View {
        VStack(spacing: 0) {
            LedgerHeader("Ledger", subtitle: "Sign in to the hub", mark: true)
            ScrollView {
                LedgerCard("Sign in") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username").deckLabel().accessibilityHidden(true)
                            TextField(
                                "Username", text: $username,
                                prompt: Text("Username").foregroundStyle(Deck.muted)
                            )
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focused, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                            .deckFieldChrome(focused: focused == .username, mono: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password").deckLabel().accessibilityHidden(true)
                            SecureField(
                                "Password", text: $password,
                                prompt: Text("Password").foregroundStyle(Deck.muted)
                            )
                            .textContentType(.password)
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await attempt() } }
                            .deckFieldChrome(focused: focused == .password, invalid: problem != nil, mono: true)
                        }

                        if let problem {
                            // Shown VERBATIM - see HubClient.login's comment. The hub
                            // returns the identical message for a wrong password and
                            // for a username that doesn't exist, and rewriting it here
                            // could reintroduce the distinction on this side.
                            DeckErrorText(problem)
                        }

                        Button(checking ? "Signing in…" : "Sign in") { Task { await attempt() } }
                            .buttonStyle(.deckPrimary)
                            .disabled(username.isEmpty || password.isEmpty || checking)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .deckGround()
    }

    private func attempt() async {
        guard !username.isEmpty, !password.isEmpty, !checking else { return }
        checking = true
        problem = nil
        defer { checking = false }
        do {
            try await HubClient.shared.login(username: username, password: password)
            password = ""
            onSignedIn()
        } catch {
            problem = error.localizedDescription
            password = ""
        }
    }
}
