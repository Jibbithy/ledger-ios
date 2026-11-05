import SwiftUI

/// The balance, forecast, and subscription-detection placeholders, plus the
/// unparsed-mail banner and Sign Out. Everything here answers one question -
/// "where does my money stand right now" - which is why it's the tab the app
/// opens on.
struct OverviewView: View {
    var onSignOut: () -> Void
    @Environment(LedgerStore.self) private var store
    @State private var editing: SettingsSheet.Focus?

    var body: some View {
        VStack(spacing: 0) {
            LedgerHeader("Ledger", mark: true) {
                Button {
                    editing = .pay
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(DeckIconButtonStyle())
                .accessibilityLabel("Edit")
                Button("Sign Out") {
                    Task {
                        await HubClient.shared.logout()
                        onSignOut()
                    }
                }
                .buttonStyle(DeckButtonStyle(.plain))
            }
            LedgerSummaryGate { s in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if s.unparsed > 0 {
                            DeckAlert(.warn, message: "\(s.unparsed) email\(s.unparsed == 1 ? "" : "s") could not be read")
                        }
                        LedgerCard("Balance") {
                            // The combined figure first, then the accounts
                            // behind it. "What do I have" is the question, and
                            // until the balance-summary parser existed it could
                            // not be answered - only checking had ever reported.
                            if let totals = s.totals, totals.accounts_known > 0 {
                                TotalCard(totals: totals, nowMs: s.now)
                                    .padding(.bottom, 14)
                                DeckRule()
                            }
                            BalanceCard(accounts: s.accounts, nowMs: s.now)
                            PollRow(poll: s.poll, nowMs: s.now)
                        }
                        LedgerCard("Next paycheck") { PayCard(pay: s.pay) }
                        LedgerCard("Goal") { GoalCard(goal: s.goal) }
                        LedgerCard("Subscriptions") {
                            SubscriptionsCard(subscriptions: s.subscriptions)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .defaultScrollAnchor(DemoMode.scrollAnchor)
                .refreshable { await store.refresh() }
            }
        }
        .deckGround()
        .sheet(item: $editing) { focus in
            SettingsSheet(focus: focus).environment(store).deckSheet()
        }
        .task { if DemoMode.sheet == "settings" { editing = .pay } }
    }
}

extension SettingsSheet.Focus: Identifiable {
    public var id: Int { self == .pay ? 0 : 1 }
}

/// A money figure in Plex Mono: every digit the same width, one line, and
/// allowed to shrink rather than wrap at the largest Dynamic Type sizes - a
/// balance broken across two lines reads as two numbers.
private struct Money: View {
    let text: String
    var size: CGFloat
    var style: Font.TextStyle = .title
    var color: Color = Deck.ink

    var body: some View {
        Text(text)
            .font(LedgerType.money(size, relativeTo: style))
            .tracking(-0.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A caption line under a figure: mono, muted - the web's `.asof`.
private struct Caption: View {
    let text: String
    var color: Color = Deck.muted

    init(_ text: String, color: Color = Deck.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(LedgerType.rowMeta)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The STALE marker. A chip with the warn diamond, so staleness is carried by
/// a shape and a word as well as by colour.
private struct StaleChip: View {
    var body: some View {
        DeckChip("Stale", kind: .warn, status: .warn)
            .accessibilityLabel("Stale")
    }
}

// --- Mailbox poll ---

/// Sits under the balance because that is the number it explains. A poller
/// that silently stopped is indistinguishable from a month with no charges,
/// so "checked 4 minutes ago" is what makes the balance trustworthy rather
/// than merely present. Renders nothing at all when the hub reports no
/// poller, so an older hub simply looks the way it always did.
private struct PollRow: View {
    let poll: Poll?
    let nowMs: Double

    var body: some View {
        if let p = poll {
            Group {
                if !p.enabled {
                    label("Automatic checking is off — ingest is manual.", status: .idle)
                } else if let err = p.lastError {
                    label("Last mailbox check failed: \(err)", status: .crit)
                } else if let at = p.lastRunAt {
                    label("Mailbox checked \(relativeMinutes(nowMs - at)).", status: .ok)
                } else {
                    label("Mailbox has not been checked yet.", status: .idle)
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth)
            }
        }
    }

    /// The dot's SHAPE says how it went (● checked, ■ failed, ○ off or not
    /// yet) - the colour is the second signal, not the only one.
    private func label(_ text: String, status: DeckStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            DeckDot(status, size: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Caption(text, color: status == .crit ? Deck.critInk : Deck.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// --- Balance ---

/// The money across every account.
///
/// Dated by its STALEST part (see hub/queries.js's balanceTotals): a total is
/// only as current as the oldest balance inside it, and showing the newest date
/// would make a month-old savings figure look refreshed this morning. It also
/// says when some account has never reported at all - a sum over two of three
/// accounts looks exactly like a sum over three.
private struct TotalCard: View {
    let totals: Totals
    let nowMs: Double

    var body: some View {
        let days = totals.as_of.flatMap { daysBetween($0, nowMs: nowMs) }
        let stale = (days ?? 0) > staleDays
        VStack(alignment: .leading, spacing: 6) {
            Money(
                text: formatCents(totals.balance_cents), size: 38, style: .largeTitle,
                color: stale ? Deck.warnInk : Deck.ink)
            Caption(caption(days), color: stale ? Deck.warnInk : Deck.muted)
            if stale { StaleChip() }
        }
    }

    private func caption(_ days: Int?) -> String {
        var parts = ["across \(totals.accounts_known) account\(totals.accounts_known == 1 ? "" : "s")"]
        if totals.accounts_known < totals.accounts_total {
            let missing = totals.accounts_total - totals.accounts_known
            parts.append("\(missing) more \(missing == 1 ? "has" : "have") never reported")
        }
        if let on = totals.as_of, let days {
            parts.append("as of \(formatShortDate(on)) · \(relativeDay(days))")
        }
        return parts.joined(separator: " · ")
    }
}

// --- Pay ---

/// The next paycheck - the ONLY figure on this screen the bank did not send.
/// Not one deposit alert has ever arrived, so it cannot be inferred; it is
/// stated by the owner and hub/pay.js does the calendar arithmetic. Labelled as
/// expected, never as received, so it can never be read as money that landed.
private struct PayCard: View {
    let pay: PayForecast?

    var body: some View {
        if let pay {
            VStack(alignment: .leading, spacing: 6) {
                Money(text: formatCents(pay.amount_cents), size: 30)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatDayName(pay.next_on))
                        .font(Deck.sans(15, .bold))
                        .foregroundStyle(Deck.ink)
                    Text("· \(when(pay.days_until))")
                        .font(Deck.body)
                        .foregroundStyle(pay.days_until <= 1 ? Deck.okInk : Deck.muted)
                }
                Caption(
                    [pay.cadence_label, "expected, not yet received"]
                        .compactMap { $0 }.joined(separator: " · "))
            }
        } else {
            Text("No paycheck set up yet. No deposit alert has ever arrived, so this is something to tell Ledger rather than something it can work out.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func when(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }
}

// --- Goal ---

/// Progress measured against real account balances rather than a second number
/// the owner also has to keep updated, so it cannot drift stale the moment
/// money moves. It names the accounts it counted: a bar whose denominator
/// silently changed would be worse than one that never ran.
private struct GoalCard: View {
    let goal: GoalProgress?

    var body: some View {
        if let goal {
            VStack(alignment: .leading, spacing: 8) {
                Money(text: formatCents(goal.saved_cents), size: 30)
                Text(goal.name)
                    .font(Deck.sans(15, .bold))
                    .foregroundStyle(Deck.ink)
                DeckMeter(fraction: goal.progress, fill: goal.reached ? Deck.ok : Deck.accent, height: 16)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Caption(percentText(goal))
                        Spacer()
                        Caption(remainingText(goal))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Caption(percentText(goal))
                        Caption(remainingText(goal))
                    }
                }
                .accessibilityElement(children: .combine)
                Caption(notes(goal))
            }
        } else {
            Text("No goal set. Add one and Ledger will track it against your savings.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percentText(_ goal: GoalProgress) -> String {
        "\(Int((goal.progress * 100).rounded()))% of \(formatCents(goal.target_cents))"
    }

    private func remainingText(_ goal: GoalProgress) -> String {
        goal.reached ? "reached" : "\(formatCents(goal.remaining_cents)) to go"
    }

    private func notes(_ goal: GoalProgress) -> String {
        var parts = [
            goal.funded_from == "savings"
                ? "counting \(goal.funded_accounts.joined(separator: ", "))"
                : "counting every account — no savings account has reported yet"
        ]
        if let on = goal.target_date, let left = goal.days_left {
            parts.append(
                left >= 0
                    ? "\(left) day\(left == 1 ? "" : "s") until \(formatShortDate(on))"
                    : "target date \(formatShortDate(on)) has passed")
        }
        return parts.joined(separator: " · ")
    }
}

private struct BalanceCard: View {
    let accounts: [Account]
    let nowMs: Double

    var body: some View {
        if accounts.isEmpty {
            Text("No accounts yet.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, acct in
                    row(acct)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ acct: Account) -> some View {
        let label = acct.mask.map { "\(acct.name) ••\($0)" } ?? acct.name
        if let cents = acct.balance_cents, let on = acct.balance_on {
            let days = daysBetween(on, nowMs: nowMs) ?? 0
            let stale = days > staleDays
            VStack(alignment: .leading, spacing: 4) {
                Text(label).deckLabel()
                // Smaller than the combined total above it: the total is the
                // headline now, and two equally large numbers would compete
                // for it.
                Money(
                    text: formatCents(cents), size: 22, style: .title2,
                    color: stale ? Deck.warnInk : Deck.ink)
                // Only a BALANCE SUMMARY carries this. Its absence is shown as
                // absence, never as equality with the current balance - the
                // gap is holds and pending charges.
                if let available = acct.available_cents, available != cents {
                    Caption("\(formatCents(available)) available")
                }
                Caption(
                    "as of \(formatShortDate(on)) · \(relativeDay(days))",
                    color: stale ? Deck.warnInk : Deck.muted)
                // A stale balance shown as though it were current is the one
                // way this screen can lie about money - see the spec. The chip
                // exists so staleness can never be missed by scanning color
                // alone.
                if stale { StaleChip().padding(.top, 2) }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).deckLabel()
                Text("Balance unknown")
                    .font(Deck.sans(19, .medium, relativeTo: .title3))
                    .foregroundStyle(Deck.ink)
                Caption("no balance has been reported yet")
            }
        }
    }
}

// --- Subscriptions ---
//
// A one-line pointer to the Subscriptions tab, not a second copy of what
// that tab already shows in full - this card's whole job is to make the
// balance screen say "there's something to look at over there" the same way
// the unparsed-mail banner does.

private struct SubscriptionsCard: View {
    let subscriptions: Subscriptions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Entries with no known cadence are EXCLUDED from the total and
            // counted separately: the hub refuses to invent a cadence for a
            // merchant seen once, and folding those in as zero would present
            // an under-count as a total.
            if let monthly = subscriptions.monthly_total_cents,
                let known = subscriptions.monthly_known, known > 0
            {
                Money(text: "\(formatCents(monthly)) / mo", size: 30)
                Caption(costCaption(known: known, unknown: subscriptions.monthly_unknown ?? 0))
            }
            Text(text)
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func costCaption(known: Int, unknown: Int) -> String {
        var parts = ["\(known) subscription\(known == 1 ? "" : "s")"]
        if unknown > 0 { parts.append("\(unknown) more with no known cadence, not counted") }
        return parts.joined(separator: " · ")
    }

    private var text: String {
        let confirmed = subscriptions.confirmed.count
        let candidates = subscriptions.candidates.count
        if confirmed == 0 && candidates == 0 {
            return "No subscriptions confirmed or detected yet."
        }
        var parts: [String] = []
        if confirmed > 0 { parts.append("\(confirmed) confirmed") }
        if candidates > 0 { parts.append("\(candidates) to review") }
        return "\(parts.joined(separator: ", ")) — see the Subscriptions tab."
    }
}
