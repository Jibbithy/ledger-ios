import SwiftUI

/// Owns the ONE `GET /api/summary` response every tab renders from.
///
/// Three tabs each fetching independently would mean three round trips for
/// one screenful of data, and - worse, on a screen that shows money - the
/// fetches could land at different times and disagree with each other mid-
/// refresh, so Overview and Spending could show two different balances for a
/// few hundred milliseconds. A single store, injected into all three tabs via
/// the environment, makes that structurally impossible: there is exactly one
/// `Summary` in memory, and every tab reads the same one.
@Observable
@MainActor
final class LedgerStore {
    var summary: Summary?
    var fatal: HubError?
    var loading = false

    /// Set by RootView. Called on a 401 so the app can drop back to
    /// LoginView - HubClient.summary() has ALREADY cleared the stored cookie
    /// by the time this fires, so there's nothing left for the caller to
    /// clean up except its own navigation state.
    var onUnauthorized: () -> Void = {}

    func refresh() async {
        loading = true
        defer { loading = false }
        // Demo mode (DEBUG + a launch flag) answers from invented data and
        // never opens a connection - see DemoMode.
        if DemoMode.isActive {
            if DemoMode.fails {
                fatal = .unreachable
            } else {
                summary = DemoMode.summary
                fatal = nil
            }
            return
        }
        do {
            summary = try await HubClient.shared.summary()
            fatal = nil
        } catch let e as HubError {
            fatal = e
            if case .unauthorized = e { onUnauthorized() }
        } catch {
            fatal = .http(0, error.localizedDescription)
        }
    }

    // --- Subscriptions writes ---
    //
    // Each of these performs the write and then re-fetches `summary` -
    // never patches it in place. A local patch would mean guessing what the
    // hub just computed (e.g. `monthly_cents` for a newly-confirmed row),
    // and that guess could disagree with the real answer for as long as the
    // guess sits there; refreshing means it's wrong for zero milliseconds.
    // Throws rather than swallowing, so the caller (a detail sheet) can show
    // its own error instead of the write silently failing.

    func confirmSubscription(merchant: String, amountCents: Int, cadenceDays: Int?) async throws {
        if DemoMode.isActive { return }
        try await HubClient.shared.confirmSubscription(merchant: merchant, amountCents: amountCents, cadenceDays: cadenceDays)
        await refresh()
    }

    func dismissSubscription(merchant: String) async throws {
        if DemoMode.isActive { return }
        try await HubClient.shared.dismissSubscription(merchant: merchant)
        await refresh()
    }

    func removeSubscription(merchant: String) async throws {
        if DemoMode.isActive { return }
        try await HubClient.shared.removeSubscription(merchant: merchant)
        await refresh()
    }

    // --- Settings ---

    /// The STORED pay schedule and goal, not the resolved ones on `summary`.
    /// Not cached here: the sheet is the only reader, it is short-lived, and a
    /// cached copy would be one more thing that can be stale on open.
    func loadSettings() async throws -> SettingsPayload {
        if DemoMode.isActive { return DemoMode.settings }
        return try await HubClient.shared.settings()
    }

    /// Double optionals, deliberately: the hub merges, so "leave this key
    /// alone" (nil) and "clear this key" (.some(nil)) are different requests
    /// and collapsing them would either wipe a schedule or refuse to.
    func saveSettings(pay: PaySetting??, goal: GoalSetting??) async throws {
        if DemoMode.isActive { return }
        try await HubClient.shared.saveSettings(pay: pay, goal: goal)
        await refresh()
    }
}
