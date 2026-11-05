import Foundation

/// GET /api/summary's whole response - see hub/server.js's handleSummary and
/// hub/queries.js for exactly what each field is. Property names are kept in
/// the hub's own snake_case rather than remapped to camelCase: a CodingKeys
/// block that renames every field is one more place for a hub-side rename to
/// go unnoticed until decoding starts failing silently.
struct Summary: Codable, Sendable {
    let accounts: [Account]
    let transactions: [Transaction]
    let spend: [CategorySpend]
    let merchants: [Merchant]
    let unparsed: Int
    let hasIncome: Bool
    let subscriptions: Subscriptions
    let poll: Poll?  // null when the hub was built without a poller
    let since: String  // "YYYY-MM-DD", 30 days back from the server clock
    let now: Double  // epoch MILLISECONDS, Date.now() on the hub

    // Everything below is OPTIONAL for the same reason `poll` is: this app and
    // the hub are deployed separately, so a phone can be updated first and
    // spend a day talking to an older hub. A non-optional field the hub does
    // not send yet fails the WHOLE decode, and the app shows "couldn't read the
    // hub's answer" on every screen rather than the one card that is missing.
    let totals: Totals?
    let spendTotal: SpendTotal?
    let pay: PayForecast?  // null when no schedule has been entered
    let goal: GoalProgress?  // null when no goal has been entered
    let today: String?  // "YYYY-MM-DD" on the hub's clock
}

/// The money across every account at once - `accounts`' figures added up by the
/// hub (queries.js's balanceTotals) rather than here, so the phone and the
/// browser can never disagree about the total.
///
/// `accounts_known` is not decoration: summing three accounts when only two
/// have ever reported gives a number that LOOKS like everything and is not.
/// `as_of` is the OLDEST of the balances behind it, because a total is only as
/// current as its stalest part.
struct Totals: Codable, Sendable {
    let balance_cents: Int
    let available_cents: Int?
    let accounts_known: Int
    let accounts_total: Int
    let as_of: String?
}

/// Total DEBITS over the window. Summed in SQL over every debit, so a charge
/// the categoriser could not name still counts - a total built by adding up the
/// category rows would silently under-report by exactly whatever fell through.
struct SpendTotal: Codable, Sendable {
    let total_cents: Int
    let count: Int
}

/// The next paycheck.
///
/// The ONLY figure in this app the bank did not send. Not one deposit alert has
/// ever arrived, so there is no income history to infer a cadence from; the
/// schedule is stated by the owner and the hub does the calendar arithmetic
/// (hub/pay.js). It must always be rendered as expected, never as received.
struct PayForecast: Codable, Sendable {
    let amount_cents: Int
    let cadence_days: Int
    let anchor_date: String  // a day the owner knows they were paid
    let next_on: String  // "YYYY-MM-DD", on or after the hub's today
    let days_until: Int  // 0 means today
    let previous_on: String?
    let cadence_label: String?  // "Weekly", from the hub's own list
}

/// A savings goal and how far along it is.
///
/// `saved_cents` is measured against real account balances, not a second number
/// the owner also has to keep updated, so it cannot drift stale when money
/// moves. `funded_from` says WHICH accounts were counted ("savings", or "all"
/// before any savings balance has arrived) - a progress bar whose denominator
/// quietly changed would be worse than one that never ran. `progress` is a
/// clamped 0...1 ratio, so a passed goal cannot overflow its track.
struct GoalProgress: Codable, Sendable {
    let name: String
    let target_cents: Int
    let target_date: String?
    let saved_cents: Int
    let funded_from: String
    let funded_accounts: [String]
    let remaining_cents: Int
    let reached: Bool
    let progress: Double
    let days_left: Int?
}

// --- GET/POST /api/settings -------------------------------------------------

/// One cadence the hub can compute EXACTLY. The picker is built from the list
/// the server sends, never from one hardcoded here: an option the hub would
/// then refuse is a form that can only fail.
struct Cadence: Codable, Sendable, Identifiable, Hashable {
    let days: Int
    let label: String
    var id: Int { days }
}

/// The stored pay schedule, as opposed to PayForecast which is that schedule
/// already resolved against today. The edit sheet reads THIS: editing a derived
/// view of a value instead of the value itself is how a form starts writing
/// back its own output.
struct PaySetting: Codable, Sendable {
    let amount_cents: Int
    let cadence_days: Int
    let anchor_date: String
}

struct GoalSetting: Codable, Sendable {
    let name: String
    let target_cents: Int
    let target_date: String?
}

struct SettingsPayload: Codable, Sendable {
    let pay: PaySetting?
    let goal: GoalSetting?
    let cadences: [Cadence]
}

/// Whether the hub is still checking the mailbox, and how that last check
/// went. This exists because a poller that quietly died looks exactly like a
/// month with no charges - without it, silent failure is invisible.
/// Optional throughout: `lastRunAt` is null before the first cycle has run,
/// and `lastError` is null whenever the last cycle succeeded.
struct Poll: Codable, Sendable {
    let enabled: Bool
    let running: Bool
    let lastRunAt: Double?  // epoch MILLISECONDS, the hub's clock
    let lastError: String?
    let lastStored: Int?
}

/// One row of accountsWithBalances. `balance_cents`/`balance_on` are null
/// together, before the hub has ever ingested a balance alert for the
/// account - never treat one as present without the other.
struct Account: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let mask: String?
    let kind: String
    let balance_cents: Int?
    let balance_on: String?  // "YYYY-MM-DD"
    /// Only a BALANCE SUMMARY alert carries this; a transaction alert has no
    /// such number. Null therefore means "not reported", never "same as the
    /// current balance" - the gap between the two is holds and pending
    /// charges, which is exactly what it exists to show.
    let available_cents: Int?
    /// "summary" | "transaction" - which alert the figure above came from.
    let balance_source: String?
}

/// One row of recentTransactions, newest first as the hub already sorts it -
/// this app must never re-sort and risk disagreeing with the server's order.
/// `category` is not a column; hub/queries.js resolves it from `mcc` via
/// hub/mcc.js on every read, so it can change retroactively as that table
/// grows without the stored row ever being touched.
struct Transaction: Codable, Identifiable, Sendable {
    let id: Int
    let posted_on: String  // "YYYY-MM-DD"
    let amount_cents: Int  // ALWAYS positive; sign comes from `direction`
    let direction: String  // "debit" | "credit"
    let merchant: String?  // the grouping key - never rendered
    let display: String?  // the human label - render this
    let merchant_raw: String?
    let mcc: String?
    let state: String?
    let balance_after_cents: Int?
    let mask: String
    let category: String

    var label: String { display ?? merchant ?? merchant_raw ?? "Unknown" }
}

/// One row of spendByCategory. DEBITS only - the hub never adds a credit into
/// a category total, or a paycheck would render as a spending line.
struct CategorySpend: Codable, Sendable {
    let category: String
    let total_cents: Int
    let count: Int
}

/// One row of topMerchants - ranked by money spent, not by visit count.
struct Merchant: Codable, Identifiable, Sendable {
    let merchant: String?  // the raw grouping key - never rendered
    let display: String?  // the human label - render this
    let total_cents: Int
    let count: Int
    let last_on: String  // "YYYY-MM-DD"

    var id: String { merchant ?? "Unknown" }
    var label: String { display ?? merchant ?? "Unknown" }
}

// --- Subscriptions - see hub/recurring.js and hub/server.js's withHistory ---

/// One charge behind a subscription or candidate's detail view -
/// `subscriptions.*.charges`, oldest first (hub/queries.js's chargesFor).
struct Charge: Codable, Sendable {
    let posted_on: String  // "YYYY-MM-DD"
    let amount_cents: Int
}

/// One row of `subscriptions.confirmed` - a human has confirmed this recurs.
/// `monthly_cents` is null exactly when `cadence_days` is null: a merchant
/// confirmed straight off a single-occurrence mcc candidate has no known
/// cadence, and hub/recurring.js's monthlyCostCents refuses to guess one
/// rather than feed a fabricated number into anything downstream - see
/// SubscriptionsView's "assumed monthly" rendering for how that's shown.
struct ConfirmedSubscription: Codable, Identifiable, Sendable {
    let merchant: String  // the raw grouping key - POST BACK, never render
    let display: String  // the human label - render this instead
    let amount_cents: Int
    let cadence_days: Int?
    let kind: String
    let monthly_cents: Int?
    let charges: [Charge]
    let first_on: String?
    let last_on: String?
    let count: Int

    var id: String { merchant }
}

/// One row of `subscriptions.candidates` - the hub's guess, never a fact
/// until a human confirms it through HubClient.confirmSubscription. `basis`
/// says HOW it was detected: "pattern" (>=3 charges with a stable cadence,
/// hub/recurring.js's patternCandidates) or "mcc" (the merchant's category
/// code looks subscription-flavoured, even at a single charge). There is no
/// `monthly_cents` here at all - the server only computes that once a human
/// has confirmed a cadence; see the comment above ConfirmedSubscription.
struct CandidateSubscription: Codable, Identifiable, Sendable {
    let merchant: String
    let display: String
    let amount_cents: Int
    let cadence_days: Int?
    let occurrences: Int
    let confidence: Double
    let basis: String  // "pattern" | "mcc"
    let charges: [Charge]
    let first_on: String?
    let last_on: String?
    let count: Int

    var id: String { merchant }
}

/// GET /api/summary's `subscriptions` - confirmed facts and unconfirmed
/// guesses, kept in two separate arrays rather than one list with a flag so
/// a view can never accidentally render a guess as though it were decided.
struct Subscriptions: Codable, Sendable {
    let confirmed: [ConfirmedSubscription]
    let candidates: [CandidateSubscription]

    /// What the confirmed subscriptions cost per month. Entries with no known
    /// cadence are EXCLUDED and counted in `monthly_unknown` instead - the hub
    /// refuses to invent a cadence for a merchant seen once, and folding those
    /// in as zero would present an under-count as a total.
    let monthly_total_cents: Int?
    let monthly_known: Int?
    let monthly_unknown: Int?
}
