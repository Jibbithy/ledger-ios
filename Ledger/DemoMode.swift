import SwiftUI

/// Fake data for screenshots, and the launch flags that open each screen.
///
/// DEBUG builds only, and only with `-LedgerDemo` on the launch line - which
/// nothing but `xcrun simctl launch` ever passes. In demo mode the app starts
/// without reading the Keychain, skips the biometric gate, and answers the
/// summary, settings and subscription calls from the data below instead of the
/// hub - so a screenshot can never contain a real balance and a simulator
/// needs no session. (Sign in and Sign Out are untouched: tapped, they still go
/// to the real hub.) Every figure below is invented.
///
///     -LedgerDemo                    required; everything else is ignored without it
///     -LedgerTab <overview|spending|subscriptions|activity>
///     -LedgerSlice <category|Other>  preselect a pie wedge on Spending
///     -LedgerSheet <settings|confirmed|candidate>
///     -LedgerScrollEnd               open every scroll view at its bottom
///     -LedgerDemoStale               the savings balance is five days old
///     -LedgerDemoError               the fetch fails: Tailscale is "off"
///     -LedgerShowLock / -LedgerShowLogin
enum DemoMode {
    #if DEBUG
        static let isActive = arguments.contains("-LedgerDemo")
    #else
        static let isActive = false
    #endif

    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard isActive, let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
    private static func flag(_ name: String) -> Bool { isActive && arguments.contains(name) }

    static var tab: MainTab? {
        switch value(after: "-LedgerTab") {
        case "overview": .overview
        case "spending": .spending
        case "subscriptions": .subscriptions
        case "activity": .activity
        default: nil
        }
    }
    static var slice: String? { value(after: "-LedgerSlice") }
    static var sheet: String? { value(after: "-LedgerSheet") }
    static var showsLock: Bool { flag("-LedgerShowLock") }
    static var showsLogin: Bool { flag("-LedgerShowLogin") }
    static var fails: Bool { flag("-LedgerDemoError") }
    /// Where a scroll view opens: nil (the top, as always) unless the flag asks
    /// for the end - simctl cannot scroll, and below the fold is still the app.
    static var scrollAnchor: UnitPoint? { flag("-LedgerScrollEnd") ? .bottom : nil }
    private static var stale: Bool { flag("-LedgerDemoStale") }

    // MARK: - The fake hub

    /// 2025-01-15 12:00 UTC. Fixed, so a screenshot says the same thing on
    /// every run: every "ago" below is measured from this.
    private static let nowMs: Double = 1_736_942_400_000

    static var summary: Summary {
        let savingsOn = stale ? "2025-01-10" : "2025-01-14"
        let accounts = [
            Account(
                id: 1, name: "Example Checking", mask: "0001", kind: "checking",
                balance_cents: 125_000, balance_on: "2025-01-15",
                available_cents: 110_000, balance_source: "summary"),
            Account(
                id: 2, name: "Example Savings", mask: "0002", kind: "savings",
                balance_cents: 250_000, balance_on: savingsOn,
                available_cents: nil, balance_source: "summary"),
            Account(
                id: 3, name: "Example Spending", mask: "0003", kind: "checking",
                balance_cents: nil, balance_on: nil,
                available_cents: nil, balance_source: nil),
        ]
        return Summary(
            accounts: accounts,
            transactions: transactions,
            spend: spend,
            merchants: merchants,
            unparsed: 1,
            hasIncome: false,
            subscriptions: subscriptions,
            poll: Poll(
                enabled: true, running: false, lastRunAt: nowMs - 4 * 60_000,
                lastError: nil, lastStored: 2),
            since: "2024-12-16",
            now: nowMs,
            totals: Totals(
                balance_cents: 375_000, available_cents: 110_000,
                accounts_known: 2, accounts_total: 3, as_of: savingsOn),
            spendTotal: SpendTotal(
                total_cents: spend.reduce(0) { $0 + $1.total_cents },
                count: spend.reduce(0) { $0 + $1.count }),
            pay: PayForecast(
                amount_cents: 100_000, cadence_days: 14, anchor_date: "2025-01-05",
                next_on: "2025-01-19", days_until: 4, previous_on: "2025-01-05",
                cadence_label: "Every 2 weeks"),
            goal: GoalProgress(
                name: "Example Goal", target_cents: 1_000_000,
                target_date: "2025-12-31", saved_cents: 250_000,
                funded_from: "savings", funded_accounts: ["Example Savings"],
                remaining_cents: 750_000, reached: false, progress: 0.25,
                days_left: 350),
            today: "2025-01-15")
    }

    static let settings = SettingsPayload(
        pay: PaySetting(amount_cents: 100_000, cadence_days: 14, anchor_date: "2025-01-05"),
        goal: GoalSetting(name: "Example Goal", target_cents: 1_000_000, target_date: "2025-12-31"),
        cadences: [
            Cadence(days: 7, label: "Weekly"), Cadence(days: 14, label: "Every 2 weeks"),
            Cadence(days: 30, label: "Monthly"),
        ])

    /// Nine categories, so the pie has six wedges and an "Other".
    private static let spend: [CategorySpend] = [
        CategorySpend(category: "Groceries", total_cents: 32_000, count: 7),
        CategorySpend(category: "Restaurants", total_cents: 18_000, count: 4),
        CategorySpend(category: "Gas", total_cents: 15_000, count: 5),
        CategorySpend(category: "Hardware", total_cents: 8_000, count: 1),
        CategorySpend(category: "Streaming & cable", total_cents: 5_500, count: 2),
        CategorySpend(category: "Pharmacy", total_cents: 4_000, count: 3),
        CategorySpend(category: "Phone", total_cents: 2_500, count: 1),
        CategorySpend(category: "Books", total_cents: 1_500, count: 1),
        CategorySpend(category: "Parking", total_cents: 500, count: 2),
    ]

    private static let merchants: [Merchant] = [
        Merchant(merchant: "example grocer", display: "Example Grocer", total_cents: 32_000, count: 4, last_on: "2025-01-15"),
        Merchant(merchant: "demo diner", display: "Demo Diner", total_cents: 18_000, count: 4, last_on: "2025-01-14"),
        Merchant(merchant: "sample fuel stop", display: "Sample Fuel Stop", total_cents: 15_000, count: 3, last_on: "2025-01-13"),
        Merchant(merchant: "test hardware co", display: "Test Hardware Co", total_cents: 8_000, count: 1, last_on: "2025-01-09"),
        Merchant(merchant: "placeholder pharmacy", display: "Placeholder Pharmacy", total_cents: 4_000, count: 2, last_on: "2025-01-08"),
    ]

    private static let transactions: [Transaction] = {
        let rows: [(String, Int, String, String, String)] = [
            ("2025-01-15", 6_000, "debit", "Example Grocer", "Groceries"),
            ("2025-01-15", 1_500, "debit", "Example Streaming", "Streaming & cable"),
            ("2025-01-14", 2_500, "debit", "Demo Diner", "Restaurants"),
            ("2025-01-13", 4_000, "debit", "Sample Fuel Stop", "Gas"),
            ("2025-01-12", 2_500, "debit", "Sample Phone Co", "Phone"),
            ("2025-01-11", 1_000, "credit", "Example Refund", "Retail"),
            ("2025-01-10", 250, "debit", "Demo Parking", "Parking"),
            ("2025-01-09", 8_000, "debit", "Test Hardware Co", "Hardware"),
            ("2025-01-08", 2_000, "debit", "Placeholder Pharmacy", "Pharmacy"),
            ("2025-01-07", 5_000, "debit", "Example Grocer", "Groceries"),
            ("2025-01-06", 1_500, "debit", "Sample Books", "Books"),
            ("2025-01-05", 500, "debit", "Demo News", "Streaming & cable"),
            ("2025-01-04", 3_000, "debit", "Demo Diner", "Restaurants"),
            ("2025-01-03", 4_500, "debit", "Example Grocer", "Groceries"),
        ]
        return rows.enumerated().map { i, r in
            Transaction(
                id: 1000 + i, posted_on: r.0, amount_cents: r.1, direction: r.2,
                merchant: r.3.lowercased(), display: r.3, merchant_raw: r.3.uppercased(),
                mcc: nil, state: "posted", balance_after_cents: nil,
                mask: "0001", category: r.4)
        }
    }()

    private static let subscriptions = Subscriptions(
        confirmed: [
            ConfirmedSubscription(
                merchant: "example streaming", display: "Example Streaming", amount_cents: 1_500,
                cadence_days: 30, kind: "subscription", monthly_cents: 1_500,
                charges: [
                    Charge(posted_on: "2024-11-15", amount_cents: 1_500),
                    Charge(posted_on: "2024-12-15", amount_cents: 1_500),
                    Charge(posted_on: "2025-01-15", amount_cents: 1_500),
                ],
                first_on: "2024-11-15", last_on: "2025-01-15", count: 3),
            ConfirmedSubscription(
                merchant: "sample phone co", display: "Sample Phone Co", amount_cents: 2_500,
                cadence_days: 30, kind: "subscription", monthly_cents: 2_500,
                charges: [Charge(posted_on: "2025-01-12", amount_cents: 2_500)],
                first_on: "2025-01-12", last_on: "2025-01-12", count: 1),
            ConfirmedSubscription(
                merchant: "demo news", display: "Demo News", amount_cents: 500,
                cadence_days: nil, kind: "subscription", monthly_cents: nil,
                charges: [Charge(posted_on: "2025-01-05", amount_cents: 500)],
                first_on: "2025-01-05", last_on: "2025-01-05", count: 1),
        ],
        candidates: [
            CandidateSubscription(
                merchant: "placeholder cloud", display: "Placeholder Cloud", amount_cents: 300,
                cadence_days: 30, occurrences: 3, confidence: 0.9, basis: "pattern",
                charges: [
                    Charge(posted_on: "2024-11-02", amount_cents: 300),
                    Charge(posted_on: "2024-12-02", amount_cents: 300),
                    Charge(posted_on: "2025-01-02", amount_cents: 300),
                ],
                first_on: "2024-11-02", last_on: "2025-01-02", count: 3),
            CandidateSubscription(
                merchant: "sample magazine", display: "Sample Magazine", amount_cents: 1_200,
                cadence_days: nil, occurrences: 1, confidence: 0.5, basis: "mcc",
                charges: [Charge(posted_on: "2025-01-01", amount_cents: 1_200)],
                first_on: "2025-01-01", last_on: "2025-01-01", count: 1),
        ],
        monthly_total_cents: 4_000, monthly_known: 2, monthly_unknown: 1)
}
