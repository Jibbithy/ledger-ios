import LocalAuthentication
import SwiftUI

/// Biometric gate.
///
/// This is not theatre: behind it sits a live bank session - real balances and
/// transaction history for one account. A borrowed unlocked phone would
/// otherwise be a shell-adjacent credential onto someone's actual money.
@Observable
@MainActor
final class Lock {
    var unlocked = false
    var failure: String?

    func authenticate() async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"

        var probe: NSError?
        // .deviceOwnerAuthentication, NOT ...WithBiometrics: the passcode has
        // to remain a way in. A phone with a wet thumb or a re-registered face
        // would otherwise be locked out of its own finances with no recourse.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else {
            // No passcode set at all. Refusing entirely would brick the app on
            // a device that simply has no lock, so this opens - the Keychain
            // item is WhenUnlockedThisDeviceOnly and is already as protected
            // as the device allows.
            unlocked = true
            return
        }

        do {
            unlocked = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Ledger")
            failure = nil
        } catch {
            unlocked = false
            failure = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }
}

struct LockView: View {
    let lock: Lock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Deck.onFill)
                .frame(width: 72, height: 72)
                .deckTile(fill: Deck.accent)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Ledger")
                    .font(Deck.display)
                    .textCase(.uppercase)
                    .foregroundStyle(Deck.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Locked").deckLabel()
            }
            if let f = lock.failure {
                DeckErrorText(f).multilineTextAlignment(.center)
            }
            Button("Unlock") { Task { await lock.authenticate() } }
                .buttonStyle(.deckPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckGround()
        .task {
            // Demo mode is here to photograph this screen, which an instant
            // simulator unlock would replace before the shutter.
            if DemoMode.showsLock { return }
            await lock.authenticate()
        }
    }
}
