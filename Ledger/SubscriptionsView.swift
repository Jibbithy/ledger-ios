import SwiftUI

/// Confirmed recurring charges, and the hub's unconfirmed guesses about new
/// ones - see hub/recurring.js for how each list is built. This tab is the
/// only place in the app that writes anything besides logging in: confirming
/// or dismissing a candidate, or removing a confirmed subscription, all go
/// through LedgerStore (which re-fetches the shared summary afterward), so a
/// guess never sits in local state disagreeing with what the hub decided.
struct SubscriptionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var detail: SubscriptionDetail?
    @State private var actionError: HubError?

    var body: some View {
        VStack(spacing: 0) {
            LedgerHeader("Subscriptions")
            LedgerSummaryGate { s in
                // A List, unlike the other tabs, and only for the candidates'
                // swipe actions - which exist nowhere else. It is styled back
                // down to the same Deck tables: no insets, no system
                // separators, rows drawn by `deckRow`.
                List {
                    DeckTableHead("Confirmed").ledgerListRow()
                    ConfirmedSection(items: s.subscriptions.confirmed) { detail = .confirmed($0) }
                    DeckTableEdgeRow()
                    Color.clear.frame(height: 22).ledgerListRow()
                    DeckTableHead("Might be subscriptions").ledgerListRow()
                    CandidatesSection(
                        items: s.subscriptions.candidates,
                        onTap: { detail = .candidate($0) },
                        onConfirm: { confirm($0) },
                        onDismiss: { dismiss($0) }
                    )
                    DeckTableEdgeRow()
                    Color.clear.frame(height: 24).ledgerListRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .contentMargins(.top, 18, for: .scrollContent)
                .defaultScrollAnchor(DemoMode.scrollAnchor)
                .refreshable { await store.refresh() }
            }
        }
        .deckGround()
        .sheet(item: $detail) { d in
            SubscriptionDetailSheet(detail: d, onError: { actionError = $0 })
                .deckSheet()
        }
        // One alert for every write path in this tab - the sheet's own
        // actions AND the candidate row's swipe actions - rather than a
        // separate alert per surface, since "the write failed" reads the
        // same regardless of which button triggered it.
        .alert(
            "Couldn't save that",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError?.localizedDescription ?? "")
        }
        .task(id: store.summary == nil) {
            // Demo mode only: open a detail sheet once there is something to
            // open it on.
            guard detail == nil, let s = store.summary else { return }
            switch DemoMode.sheet {
            case "confirmed": detail = s.subscriptions.confirmed.first.map { .confirmed($0) }
            case "candidate": detail = s.subscriptions.candidates.last.map { .candidate($0) }
            default: break
            }
        }
    }

    private func confirm(_ c: CandidateSubscription) {
        Task {
            do {
                try await store.confirmSubscription(merchant: c.merchant, amountCents: c.amount_cents, cadenceDays: defaultCadence(for: c.cadence_days))
            } catch let e as HubError { actionError = e } catch { actionError = .http(0, error.localizedDescription) }
        }
    }

    private func dismiss(_ c: CandidateSubscription) {
        Task {
            do { try await store.dismissSubscription(merchant: c.merchant) } catch let e as HubError { actionError = e } catch {
                actionError = .http(0, error.localizedDescription)
            }
        }
    }
}

/// Which detail sheet is open, and for what - a confirmed row or a
/// candidate. Kept as one enum rather than two separate `@State` optionals
/// so at most one sheet can ever be presented at a time.
private enum SubscriptionDetail: Identifiable {
    case confirmed(ConfirmedSubscription)
    case candidate(CandidateSubscription)

    var id: String {
        switch self {
        case .confirmed(let c): "confirmed-\(c.merchant)"
        case .candidate(let c): "candidate-\(c.merchant)"
        }
    }
}

/// The cadences a person can assert when confirming. Mirrors cadencePicker()
/// in web/app.js so the phone and the browser offer the same choices. `nil`
/// is "Not sure", which stores no cadence and therefore shows no monthly cost.
///
/// This exists because detection cannot supply one: every mcc-basis candidate
/// has been seen exactly once, so its cadence_days is always null. Without a
/// way to say "monthly", confirming such a candidate could never produce a
/// monthly figure. The rule was always that WE must not invent a cadence --
/// one the user states is not invented.
let cadenceChoices: [(label: String, days: Int?)] = [
    ("Weekly", 7), ("Every 2 weeks", 14), ("Monthly", 30),
    ("Quarterly", 91), ("Yearly", 365), ("Not sure", nil),
]

/// What the picker starts on: the detected cadence when there is one, and
/// monthly otherwise, because monthly is what almost every subscription is.
func defaultCadence(for detected: Int?) -> Int? { detected ?? 30 }

extension View {
    /// A List row that draws itself: the list's insets and separator taken
    /// off, so the row's own Deck chrome is all there is. A table row passes
    /// `Deck.surface` so the cell behind it matches wherever the cell is
    /// taller than the content, and under a swipe.
    fileprivate func ledgerListRow(_ background: Color = .clear) -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}

/// An amount that is only ASSUMED monthly - the one known charge, shown softer
/// and in italics so it never reads as a monthly cost the hub computed.
private struct AssumedAmount: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Deck.mono(13, .regular, relativeTo: .subheadline))
            .italic()
            .foregroundStyle(Deck.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// --- Confirmed ---

private struct ConfirmedSection: View {
    let items: [ConfirmedSubscription]
    let onTap: (ConfirmedSubscription) -> Void

    var body: some View {
        if items.isEmpty {
            Text("Nothing confirmed yet — confirm a candidate below.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .deckRow(separator: false)
                .ledgerListRow(Deck.surface)
        } else {
            ConfirmedTotalRow(items: items)
                .deckRow(separator: false)
                .ledgerListRow(Deck.surface)
            ForEach(items) { item in
                Button {
                    onTap(item)
                } label: {
                    ConfirmedRow(item: item)
                }
                .buttonStyle(.plain)
                .deckRow()
                .ledgerListRow(Deck.surface)
            }
        }
    }
}

/// The "$X/mo" total called for at the top of the Confirmed section. Split
/// into a real total (summed from `monthly_cents`) and an "assumed" total
/// (the raw charge amount for anything whose cadence isn't known) rather
/// than blending them into one number - adding an assumed figure into the
/// real total would print a monthly cost the hub never actually computed.
private struct ConfirmedTotalRow: View {
    let items: [ConfirmedSubscription]

    private var real: Int { items.compactMap(\.monthly_cents).reduce(0, +) }
    private var assumed: Int { items.filter { $0.monthly_cents == nil }.reduce(0) { $0 + $1.amount_cents } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(formatCents(real))/mo")
                .font(LedgerType.money(26, relativeTo: .title2))
                .tracking(-0.5)
                .foregroundStyle(Deck.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if assumed > 0 {
                Text("+ \(formatCents(assumed)) assumed monthly")
                    .font(LedgerType.rowMeta)
                    .foregroundStyle(Deck.muted)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ConfirmedRow: View {
    let item: ConfirmedSubscription

    var body: some View {
        HStack(spacing: 12) {
            Text(item.display)
                .font(LedgerType.rowTitle)
                .foregroundStyle(Deck.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let m = item.monthly_cents {
                Text("\(formatCents(m))/mo")
                    .font(LedgerType.money(15))
                    .foregroundStyle(Deck.ink)
                    .fixedSize()
            } else {
                // See ConfirmedSubscription's doc comment - null cadence
                // means the hub refused to compute a monthly figure, so this
                // shows the one known charge amount instead, visibly softer
                // so it never reads as a real monthly cost.
                AssumedAmount(text: "\(formatCents(item.amount_cents)) (assumed monthly)")
                    .multilineTextAlignment(.trailing)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Deck.muted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// --- Candidates ---

private struct CandidatesSection: View {
    let items: [CandidateSubscription]
    let onTap: (CandidateSubscription) -> Void
    let onConfirm: (CandidateSubscription) -> Void
    let onDismiss: (CandidateSubscription) -> Void

    var body: some View {
        if items.isEmpty {
            Text("Nothing waiting — detection watches new transactions for repeating charges and subscription-flavored merchant categories.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .fixedSize(horizontal: false, vertical: true)
                .deckRow(separator: false)
                .ledgerListRow(Deck.surface)
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onTap(item)
                } label: {
                    CandidateRow(item: item)
                }
                .buttonStyle(.plain)
                .deckRow(separator: index > 0)
                .ledgerListRow(Deck.surface)
                .swipeActions(edge: .trailing) {
                    // Icons as well as words, so the two actions differ by
                    // shape - the system draws their labels white on the
                    // tint, with no hook for Deck's ink-on-fill text.
                    Button(role: .destructive) {
                        onDismiss(item)
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .tint(Deck.crit)
                    // Named for what it does: the swipe has nowhere to
                    // put a picker, so it commits the default rather than
                    // quietly storing "no cadence". Tap the row instead to
                    // choose a different one.
                    Button {
                        onConfirm(item)
                    } label: {
                        Label(
                            item.cadence_days == nil ? "Confirm monthly" : "Confirm",
                            systemImage: "checkmark")
                    }
                    .tint(Deck.ok)
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let item: CandidateSubscription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(item.display)
                    .font(LedgerType.rowTitle)
                    .foregroundStyle(Deck.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if item.cadence_days == nil {
                    AssumedAmount(text: "\(formatCents(item.amount_cents)) (assumed monthly)")
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(formatCents(item.amount_cents))
                        .font(LedgerType.money(15))
                        .foregroundStyle(Deck.ink)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Deck.muted)
                    .accessibilityHidden(true)
            }
            Text(basisSummary(item))
                .font(LedgerType.rowMeta)
                .foregroundStyle(Deck.muted)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "seen 3 times, every ~30 days" for a pattern candidate, or "looks like a
/// subscription by merchant category" for an mcc one - the user is being
/// asked to confirm a guess, so this says what the guess is BASED ON, per
/// spec, rather than just repeating the amount already shown next to it.
private func basisSummary(_ c: CandidateSubscription) -> String {
    switch c.basis {
    case "pattern":
        let times = "\(c.occurrences) time\(c.occurrences == 1 ? "" : "s")"
        if let days = c.cadence_days { return "seen \(times), every ~\(days) days" }
        return "seen \(times)"
    case "mcc":
        return "looks like a subscription by merchant category"
    default:
        return c.basis
    }
}

// --- Detail sheet ---

/// One detail view for either a confirmed row or a candidate - the fields
/// spec calls out (cadence, amount, first/last seen, count, every charge)
/// are identical between the two; only the action buttons at the bottom
/// differ (Confirm/Dismiss vs. Remove).
private struct SubscriptionDetailSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismissSheet
    let detail: SubscriptionDetail
    let onError: (HubError) -> Void
    @State private var working = false
    /// Seeded in .onAppear from the candidate, so the sheet opens on the
    /// detected cadence when there is one and on monthly when there is not.
    @State private var pickedCadence: Int? = 30

    var body: some View {
        VStack(spacing: 0) {
            LedgerSheetHeader(title: displayName, leading: { EmptyView() }) {
                Button("Close") { dismissSheet() }
                    .buttonStyle(.deckInk)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DeckFormSection(title: "Details") {
                        Field("Cadence") { Value(cadenceText) }
                        Field("Charge amount") { Value(formatCents(amountCents), money: true) }
                        if let m = monthlyCents {
                            Field("Monthly") { Value("\(formatCents(m))/mo", money: true) }
                        } else {
                            Field("Monthly") {
                                AssumedAmount(text: "\(formatCents(amountCents))/mo assumed")
                            }
                        }
                        Field("First seen") { Value(firstOn.map(formatShortDate) ?? "—", money: true) }
                        Field("Last seen") { Value(lastOn.map(formatShortDate) ?? "—", money: true) }
                        Field("Charges") { Value("\(count)", money: true) }
                        if case .candidate(let c) = detail {
                            Field("Detected by") { Value(basisSummary(c)) }
                        }
                    }

                    DeckFormSection(title: "Every charge") {
                        ForEach(Array(charges.enumerated()), id: \.offset) { _, ch in
                            Field(formatShortDate(ch.posted_on), mono: true) {
                                Value(formatCents(ch.amount_cents), money: true)
                            }
                        }
                    }

                    switch detail {
                    case .candidate(let c):
                        DeckFormSection(title: "Is it a subscription?") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("How often").deckLabel().accessibilityHidden(true)
                                DeckMenuPicker(
                                    title: "How often", selection: $pickedCadence,
                                    options: cadenceChoices.map { ($0.days, $0.label) })
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { actions(c) }
                                VStack(alignment: .leading, spacing: 10) { actions(c) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        .disabled(working)
                    case .confirmed(let c):
                        DeckFormSection(title: "Not a subscription?") {
                            Button("Remove", role: .destructive) {
                                run { try await store.removeSubscription(merchant: c.merchant) }
                            }
                            .buttonStyle(.deckDanger)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        .disabled(working)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .defaultScrollAnchor(DemoMode.scrollAnchor)
        }
        .background(Deck.ground)
        .overlay { if working { ProgressView().tint(Deck.muted) } }
        .onAppear { pickedCadence = defaultCadence(for: cadenceDaysValue) }
    }

    @ViewBuilder
    private func actions(_ c: CandidateSubscription) -> some View {
        Button("Confirm") {
            run { try await store.confirmSubscription(merchant: c.merchant, amountCents: c.amount_cents, cadenceDays: pickedCadence) }
        }
        .buttonStyle(.deckPrimary)
        Button("Dismiss", role: .destructive) {
            run { try await store.dismissSubscription(merchant: c.merchant) }
        }
        .buttonStyle(.deck)
    }

    /// Runs a write, closing the sheet on success and handing any failure
    /// back up to the tab's own alert rather than showing a second one here.
    private func run(_ body: @escaping () async throws -> Void) {
        working = true
        Task {
            do {
                try await body()
                working = false
                dismissSheet()
            } catch let e as HubError {
                working = false
                onError(e)
            } catch {
                working = false
                onError(.http(0, error.localizedDescription))
            }
        }
    }

    private var displayName: String {
        switch detail {
        case .confirmed(let c): c.display
        case .candidate(let c): c.display
        }
    }
    private var amountCents: Int {
        switch detail {
        case .confirmed(let c): c.amount_cents
        case .candidate(let c): c.amount_cents
        }
    }
    /// Only a confirmed row ever carries `monthly_cents` - see
    /// CandidateSubscription's doc comment for why the server never sends
    /// one for a candidate.
    private var monthlyCents: Int? {
        switch detail {
        case .confirmed(let c): c.monthly_cents
        case .candidate: nil
        }
    }
    private var cadenceDaysValue: Int? {
        switch detail {
        case .confirmed(let c): c.cadence_days
        case .candidate(let c): c.cadence_days
        }
    }
    private var firstOn: String? {
        switch detail {
        case .confirmed(let c): c.first_on
        case .candidate(let c): c.first_on
        }
    }
    private var lastOn: String? {
        switch detail {
        case .confirmed(let c): c.last_on
        case .candidate(let c): c.last_on
        }
    }
    private var count: Int {
        switch detail {
        case .confirmed(let c): c.count
        case .candidate(let c): c.count
        }
    }
    private var charges: [Charge] {
        switch detail {
        case .confirmed(let c): c.charges
        case .candidate(let c): c.charges
        }
    }
    private var cadenceText: String {
        guard let d = cadenceDaysValue else { return "unknown — a single charge doesn't establish one" }
        return "every \(d) day\(d == 1 ? "" : "s")"
    }
}

/// One labelled line of a detail section: the label left, its value right,
/// never shorter than a tap target. Wraps under itself at large type sizes
/// rather than truncating either half.
private struct Field<V: View>: View {
    let label: String
    var mono = false
    @ViewBuilder var value: V

    init(_ label: String, mono: Bool = false, @ViewBuilder value: () -> V) {
        self.label = label
        self.mono = mono
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                labelText.fixedSize()
                Spacer(minLength: 8)
                value.multilineTextAlignment(.trailing)
            }
            // Too long for one line: the value goes UNDER its label, flush
            // left like it, rather than a ragged right-aligned block.
            VStack(alignment: .leading, spacing: 4) {
                labelText
                value
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(mono ? Deck.mono(14, .medium, relativeTo: .subheadline) : Deck.body)
            .foregroundStyle(Deck.muted)
    }
}

/// A detail value: Space Grotesk for words, Plex Mono for money, dates and
/// counts.
private struct Value: View {
    let text: String
    var money = false

    init(_ text: String, money: Bool = false) {
        self.text = text
        self.money = money
    }

    var body: some View {
        Text(text)
            .font(money ? LedgerType.money(15) : Deck.sans(15, .bold))
            .foregroundStyle(Deck.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
