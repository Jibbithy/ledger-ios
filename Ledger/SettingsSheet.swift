import SwiftUI

/// The edit sheet for the two facts the bank never sends: the pay schedule and
/// the savings goal.
///
/// It reads GET /api/settings rather than pulling the values out of the summary
/// already on screen. The summary carries pay ALREADY resolved against today
/// (next_on, days_until) - editing a derived view of a value instead of the
/// value itself is how a form starts writing back its own output.
struct SettingsSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Which half the sheet was opened from, so that section is focused first.
    /// Both are always editable - one form, one save, one round trip.
    enum Focus { case pay, goal }
    let focus: Focus

    @State private var loaded: SettingsPayload?
    @State private var loadError: String?
    @State private var saving = false
    @State private var saveError: String?

    @State private var payAmount = ""
    @State private var payCadence = 7
    @State private var payAnchor = Date()
    @State private var payAnchorSet = false

    @State private var goalName = ""
    @State private var goalTarget = ""
    @State private var goalDate = Date()
    @State private var goalDateSet = false

    var body: some View {
        VStack(spacing: 0) {
            LedgerSheetHeader(
                title: "Paycheck & goal",
                leading: {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.deck)
                        .disabled(saving)
                }
            ) {
                Button("Save") { Task { await save() } }
                    .buttonStyle(.deckPrimary)
                    .disabled(saving || loaded == nil)
            }
            Group {
                if let loaded {
                    form(loaded)
                } else if let loadError {
                    VStack(alignment: .leading, spacing: 20) {
                        DeckAlert(.crit, title: "Can't open settings", message: loadError)
                        // The theme is on the phone, not the hub - a hub that
                        // is down must not take it with it.
                        themeSection
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ProgressView().tint(Deck.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Deck.ground)
        .task { await load() }
    }

    @ViewBuilder
    private func form(_ payload: SettingsPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    DeckFormSection(title: "Paycheck") {
                        labelled("Amount") {
                            TextField("0.00", text: $payAmount, prompt: Text("0.00").foregroundStyle(Deck.muted))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(DeckFieldStyle(mono: true))
                                .accessibilityLabel("Paycheck amount")
                        }
                        // Built from the SERVER's list, never a hardcoded one: an
                        // option the hub would then refuse is a form that can only fail.
                        labelled("How often") {
                            DeckMenuPicker(
                                title: "How often", selection: $payCadence,
                                options: payload.cadences.map { ($0.days, $0.label) })
                        }
                        Toggle("Set a payday", isOn: $payAnchorSet)
                            .toggleStyle(DeckCheckToggleStyle())
                            .padding(.horizontal, 14).padding(.vertical, 4)
                        if payAnchorSet {
                            DatePicker("A day you were paid", selection: $payAnchor, displayedComponents: .date)
                                .font(Deck.body)
                                .foregroundStyle(Deck.ink)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    DeckHint("Every future payday is counted from that one. Leave the amount and payday empty to remove the schedule.")
                        .padding(.horizontal, 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    DeckFormSection(title: "Savings goal") {
                        labelled("What for") {
                            TextField("Goal name", text: $goalName, prompt: Text("Goal name").foregroundStyle(Deck.muted))
                                .textFieldStyle(DeckFieldStyle())
                        }
                        labelled("Target") {
                            TextField("0.00", text: $goalTarget, prompt: Text("0.00").foregroundStyle(Deck.muted))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(DeckFieldStyle(mono: true))
                                .accessibilityLabel("Goal target")
                        }
                        Toggle("Set a deadline", isOn: $goalDateSet)
                            .toggleStyle(DeckCheckToggleStyle())
                            .padding(.horizontal, 14).padding(.vertical, 4)
                        if goalDateSet {
                            DatePicker("By when", selection: $goalDate, displayedComponents: .date)
                                .font(Deck.body)
                                .foregroundStyle(Deck.ink)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    DeckHint(
                        "Progress is measured against your real savings balance, so it never needs updating by hand. Leave the name and target empty to remove the goal."
                    )
                    .padding(.horizontal, 2)
                }

                if let saveError {
                    DeckAlert(.crit, message: saveError)
                }

                themeSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(DemoMode.scrollAnchor)
        .disabled(saving)
    }

    /// Auto / Cream / Dark. Applies on tap and is stored on the phone, so it
    /// is outside Save and Cancel - those are for the hub's two facts.
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeckFormSection(title: "Theme") {
                DeckThemePicker()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            DeckHint("Auto follows the phone. Changes right away, without Save.")
                .padding(.horizontal, 2)
        }
    }

    /// A field under its mono label - the web form's .dk-field.
    private func labelled<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).deckLabel().accessibilityHidden(true)
            field()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func load() async {
        do {
            let payload = try await store.loadSettings()
            payAmount = centsToInput(payload.pay?.amount_cents)
            // Falls back to the first cadence the SERVER offers rather than a
            // literal 7 - the two lists must not be able to drift apart.
            payCadence = payload.pay?.cadence_days ?? payload.cadences.first?.days ?? 7
            if let anchor = dateFromISO(payload.pay?.anchor_date) {
                payAnchor = anchor
                payAnchorSet = true
            }
            goalName = payload.goal?.name ?? ""
            goalTarget = centsToInput(payload.goal?.target_cents)
            if let target = dateFromISO(payload.goal?.target_date) {
                goalDate = target
                goalDateSet = true
            }
            loaded = payload
        } catch {
            loadError = (error as? HubError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Each half is all-or-nothing. A paycheck with an amount but no payday is
    /// not a half-saved paycheck, it is a mistake - saving it would put a
    /// payday on screen counted from nothing. Leaving a whole half blank is how
    /// that half gets deleted.
    private func save() async {
        saveError = nil

        var pay: PaySetting??
        if payAmount.trimmingCharacters(in: .whitespaces).isEmpty && !payAnchorSet {
            pay = .some(nil)  // an explicit clear
        } else {
            guard let cents = centsFromInput(payAmount), cents > 0 else {
                saveError = "Enter the paycheck amount, like 1000.00."
                return
            }
            guard payAnchorSet else {
                saveError = "Pick a day you were actually paid."
                return
            }
            pay = .some(
                PaySetting(
                    amount_cents: cents, cadence_days: payCadence,
                    anchor_date: isoFromDate(payAnchor)))
        }

        var goal: GoalSetting??
        let name = goalName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty && goalTarget.trimmingCharacters(in: .whitespaces).isEmpty {
            goal = .some(nil)
        } else {
            guard !name.isEmpty else {
                saveError = "Give the goal a name."
                return
            }
            guard let cents = centsFromInput(goalTarget), cents > 0 else {
                saveError = "Enter what you are saving toward, like 5000.00."
                return
            }
            goal = .some(
                GoalSetting(
                    name: name, target_cents: cents,
                    target_date: goalDateSet ? isoFromDate(goalDate) : nil))
        }

        saving = true
        defer { saving = false }
        do {
            try await store.saveSettings(pay: pay, goal: goal)
            dismiss()
        } catch {
            saveError = (error as? HubError)?.errorDescription ?? error.localizedDescription
        }
    }
}
