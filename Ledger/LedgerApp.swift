import SwiftUI

@main
struct LedgerApp: App {
    /// The Deck faces register from the bundled .ttf files before any view -
    /// or the tab bar, which asks UIKit for a UIFont by name - requests one. A
    /// font asked for before this runs falls back to the system face silently.
    init() {
        Deck.registerFonts()
        DeckTabBar.apply()
    }

    var body: some Scene {
        // Auto / Cream / Dark from the settings sheet, stamped on the WINDOW
        // so the UIKit tab bar flips with the content - see DeckTheme in
        // DeckCream.swift.
        WindowGroup { RootView().deckTheme() }
    }
}

/// Decides between Lock, Login, and the four-tab app.
struct RootView: View {
    // Demo mode (DEBUG + a launch flag, see DemoMode) never touches the
    // Keychain and skips the biometric gate unless the lock is what it is
    // there to show.
    @State private var session: String? =
        DemoMode.isActive
        ? (DemoMode.showsLogin ? nil : "demo") : SessionStore.load()
    @State private var lock: Lock = {
        let lock = Lock()
        if DemoMode.isActive && !DemoMode.showsLock { lock.unlocked = true }
        return lock
    }()
    @State private var store = LedgerStore()
    @State private var tab: MainTab = .overview
    @Environment(\.scenePhase) private var phase

    var body: some View {
        content
            .onChange(of: phase) { _, now in
                // Re-lock on the way OUT, not on the way back in. Locking on
                // .active would fire a biometric prompt over the app switcher
                // preview - which, for an app whose preview is a bank
                // balance, is exactly the frame you don't want a shoulder-surf
                // to catch; locking on .background means the app is already
                // covered by the system snapshot when the state flips.
                if now == .background { lock.unlocked = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !lock.unlocked {
            LockView(lock: lock)
        } else if session == nil {
            LoginView { session = SessionStore.load() }
        } else {
            // Opens on Overview, which is also the leftmost tab here - the
            // balance is the one number worth seeing before you've chosen to
            // look for anything else. Spending, Subscriptions, and Activity
            // exist to be drilled into, never to be the first thing on
            // screen, so there's no case (unlike another app's two-pane
            // split) where the initial selection needs to differ from tab
            // order.
            TabView(selection: $tab) {
                Tab("Overview", systemImage: "dollarsign.circle", value: .overview) {
                    // HubClient.summary() has already cleared the Keychain by
                    // the time this fires - see its comment - so this closure
                    // only has to flip local state to route back to LoginView.
                    OverviewView(onSignOut: { session = nil })
                }
                Tab("Spending", systemImage: "chart.bar", value: .spending) {
                    SpendingView()
                }
                Tab("Subscriptions", systemImage: "arrow.triangle.2.circlepath", value: .subscriptions) {
                    SubscriptionsView()
                }
                Tab("Activity", systemImage: "list.bullet", value: .activity) {
                    ActivityView()
                }
            }
            // The accent as TEXT, since the tab bar and every system control
            // draw their tint as text; no forced colour scheme - every Deck
            // token is a light/dark pair, so the app follows the system.
            .tint(Deck.accentInk)
            .environment(store)
            .task {
                if let demoTab = DemoMode.tab { tab = demoTab }
                // Lives on the TabView, not on any one tab, so it fires
                // exactly once per session regardless of which tab is
                // visible first - four tabs each kicking off their own
                // fetch on appear is exactly the "N round trips, maybe
                // disagreeing" problem the shared store exists to avoid.
                store.onUnauthorized = { session = nil }
                await store.refresh()
            }
        }
    }
}

enum MainTab: Hashable { case overview, spending, subscriptions, activity }
