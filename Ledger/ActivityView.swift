import SwiftUI

/// The full transaction list, newest first - the hub's own order, kept as-is
/// rather than re-sorted here so this tab can never disagree with what the
/// hub considers "recent".
struct ActivityView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            LedgerHeader("Activity")
            LedgerSummaryGate { s in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        DeckTableHead("Transactions")
                        TransactionsCard(transactions: s.transactions)
                        DeckRule()
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .defaultScrollAnchor(DemoMode.scrollAnchor)
                .refreshable { await store.refresh() }
            }
        }
        .deckGround()
    }
}

private struct TransactionsCard: View {
    let transactions: [Transaction]
    var body: some View {
        if transactions.isEmpty {
            Text("No transactions yet.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .deckRow(separator: false)
        } else {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, t in
                let credit = t.direction == "credit"
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.label)
                            .font(LedgerType.rowTitle)
                            .foregroundStyle(Deck.ink)
                            .lineLimit(2)
                        Text("\(formatShortDate(t.posted_on)) · \(t.category)")
                            .font(LedgerType.rowMeta)
                            .foregroundStyle(Deck.muted)
                    }
                    Spacer(minLength: 8)
                    // The sign is spelled out (+ / −), so a credit reads as one
                    // without its colour.
                    Text("\(credit ? "+" : "\u{2212}")\(formatCents(t.amount_cents))")
                        .font(LedgerType.money(15))
                        .foregroundStyle(credit ? Deck.okInk : Deck.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.vertical, 2)
                .deckRow(separator: index > 0)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
