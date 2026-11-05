import Charts
import SwiftUI

/// Spend by category and top merchants for the last 30 days - two views onto
/// the same "where did it go" question, so they share a tab instead of forcing
/// a second navigation stack to answer one question.
///
/// The chart does not scroll. It is an overlay pinned to the top of the scroll
/// view, and the list runs underneath it, fading out as each row passes behind.
/// That is why this is a ScrollView rather than the List it used to be: a List
/// row cannot be given a scroll-driven opacity without fighting the cell
/// recycling, and a chart that scrolls away is a chart you have to scroll back
/// to every time you want to know what a category is.
struct SpendingView: View {
    @Environment(LedgerStore.self) private var store

    /// Shared by the pie AND the ranked list - a slice id (a real category
    /// name, or "Other"), never a raw category, so a tap on either surface
    /// resolves to the same selection on both.
    @State private var selected: String? = DemoMode.slice

    /// The pinned chart's bottom edge in GLOBAL coordinates. Rows compare their
    /// own frame against it to decide how far behind the chart they are. Global
    /// because the two live in different coordinate spaces - the chart is in an
    /// overlay, the rows are inside the scroll content.
    @State private var chartBottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            LedgerHeader("Spending", subtitle: "Last 30 days")
            LedgerSummaryGate { s in content(s) }
        }
        .deckGround()
    }

    @ViewBuilder
    private func content(_ s: Summary) -> some View {
        let slices = categorySlices(from: s.spend)
        let total = s.spendTotal?.total_cents ?? slices.reduce(0) { $0 + $1.total_cents }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Reserves the pinned chart's space so the first row starts
                // below it instead of underneath it on first paint.
                Color.clear.frame(height: chartHeight)

                DeckTableHead("By category")
                    .fadingBehindChart(chartBottom)

                SpendList(
                    spend: s.spend, slices: slices, selected: $selected,
                    chartBottom: chartBottom)
                DeckRule()

                if !s.merchants.isEmpty {
                    DeckTableHead("Top merchants")
                        .padding(.top, 22)
                        .fadingBehindChart(chartBottom)
                    MerchantsList(merchants: s.merchants, chartBottom: chartBottom)
                    DeckRule()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
        .defaultScrollAnchor(DemoMode.scrollAnchor)
        .refreshable { await store.refresh() }
        .overlay(alignment: .top) {
            PinnedChart(
                slices: slices, total: total, count: s.spendTotal?.count,
                selected: $selected
            )
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).maxY
            } action: {
                chartBottom = $0
            }
        }
        .onChange(of: s.spend.map(\.category)) { _, _ in
            // A selection surviving into a window that no longer contains that
            // category would highlight nothing and dim everything.
            if let sel = selected, !slices.contains(where: { $0.id == sel }) { selected = nil }
        }
    }
}

private let chartHeight: CGFloat = 250

// --- Fading behind the pinned chart ---

/// How opaque a row is, given where it sits relative to the pinned chart's
/// bottom edge: 1 while it is clear of the chart, falling to 0 as it slides
/// behind. Mirrors web/pie.js's rowOpacity exactly.
///
/// Pure arithmetic on three numbers, so the rule is stated once and can be
/// reasoned about without a running scroll view.
func rowOpacity(rowBottom: CGFloat, rowHeight: CGFloat, chartBottom: CGFloat) -> Double {
    guard rowHeight > 0 else { return 1 }
    return Double(max(0, min(1, (rowBottom - chartBottom) / rowHeight)))
}

extension View {
    /// `visualEffect` rather than a GeometryReader writing to @State: the
    /// closure is evaluated with live geometry during rendering, so the fade
    /// follows the scroll frame by frame WITHOUT a state write per row per
    /// frame - which would be a layout pass feeding itself.
    ///
    /// Guarded on chartBottom > 0: before the overlay has reported its own
    /// geometry, every row would compute an opacity against zero and the whole
    /// list would paint fully faded for one frame.
    fileprivate func fadingBehindChart(_ chartBottom: CGFloat) -> some View {
        visualEffect { content, proxy in
            let frame = proxy.frame(in: .global)
            return content.opacity(
                chartBottom > 0
                    ? rowOpacity(rowBottom: frame.maxY, rowHeight: frame.height, chartBottom: chartBottom)
                    : 1)
        }
    }
}

// --- Slicing: top 6 categories + "Other" ---

/// One wedge of the pie. `members` is `[category]` for a real top-6 category,
/// or every rolled-up category name for "Other" - that list is what lets
/// Other's detail say what it actually contains instead of just a number.
struct CategorySlice: Identifiable {
    let id: String
    let total_cents: Int
    let count: Int
    let members: [String]
}

/// The live data has fifteen categories, and a fifteen-slice pie is unreadable
/// - most wedges would be too thin to tell apart by colour or to tap
/// accurately. Only the six biggest get their own wedge; the tail folds into
/// one "Other" wedge, which is still selectable and whose detail names the
/// categories inside it. Mirrors web/pie.js's categorySlices exactly.
func categorySlices(from spend: [CategorySpend], max: Int = 6) -> [CategorySlice] {
    let ranked = spend.sorted { $0.total_cents > $1.total_cents }
    let asSlice = { (s: CategorySpend) in
        CategorySlice(id: s.category, total_cents: s.total_cents, count: s.count, members: [s.category])
    }
    guard ranked.count > max else { return ranked.map(asSlice) }
    let rest = ranked.suffix(from: max)
    return ranked.prefix(max).map(asSlice) + [
        CategorySlice(
            id: "Other",
            total_cents: rest.reduce(0) { $0 + $1.total_cents },
            count: rest.reduce(0) { $0 + $1.count },
            members: rest.map(\.category),
        )
    ]
}

/// Maps a real category name back to the slice that represents it - itself, if
/// it made the top six, or "Other" if it did not. The one function keeping the
/// chart's selection and the list's talking about the same thing.
func sliceId(for category: String, in slices: [CategorySlice]) -> String {
    slices.first(where: { $0.members.contains(category) })?.id ?? category
}

/// Six Deck fills for up to six real categories, in ranked order - the SAME
/// order as ledger web/pie.js's SLICE_COLORS, so a category is the same colour
/// on the phone and in the browser. Crit red is left out on purpose: beside
/// accent orange it is the one pair the eye cannot split at swatch size, and a
/// category drawn in the alarm colour reads as an alarm.
let slicePalette: [Color] = [Deck.accent, Deck.blue, Deck.ok, Deck.warn, Deck.ink, Deck.muted]

/// "Other" is hatched rather than filled regardless of position - it is not
/// one category, so it gets no place in a categorical palette meant to
/// distinguish single ones. Same roles as web/pie.js's sliceColor.
func sliceFill(_ slice: CategorySlice, at index: Int) -> SliceFill {
    slice.id == "Other" ? .hatch : .color(slicePalette[index % slicePalette.count])
}

/// The flat colour a SectorMark is filled with. For Other that is the hatch's
/// rail ground; the stripes are drawn over it by the ring overlay, because a
/// chart mark takes a fill, not a texture.
func sliceColor(_ slice: CategorySlice, at index: Int) -> Color {
    switch sliceFill(slice, at: index) {
    case .color(let c): c
    case .hatch: Deck.rail
    }
}

// --- Ring geometry ---
//
// The same ring the SectorMarks draw - centred in the plot, sized off its
// SHORTER side, starting at twelve o'clock and running clockwise - so the ink
// edges and Other's hatch land exactly on the wedges Charts filled.
//
// Measured, not assumed: a SectorMark's `innerRadius: .ratio` is a fraction
// of THAT SECTOR'S outer radius, not of the plot. A resting wedge's hole
// edge is at 0.62 x 0.9 of the plot radius, and a selected wedge moves its
// inner edge out along with its outer one. (sliceHit below still tests the
// hole against 0.62 of the plot radius - left exactly as it was, since
// changing what a tap selects is behaviour, not style.)

private let innerRatio: CGFloat = 0.62
private let restingRatio: CGFloat = 0.9
private let selectedRatio: CGFloat = 1.0

/// One wedge's outline: outer arc clockwise, inner arc back. Angles are
/// clockwise from twelve o'clock, in radians.
private func ringSector(
    center c: CGPoint, inner: CGFloat, outer: CGFloat,
    start: Double, end: Double
) -> Path {
    // Path angles run from three o'clock, increasing clockwise on a y-down
    // canvas - hence the quarter turn back.
    let a0 = Angle.radians(start - .pi / 2)
    let sweep = Angle.radians(end - start)
    var p = Path()
    p.addRelativeArc(center: c, radius: outer, startAngle: a0, delta: sweep)
    p.addRelativeArc(center: c, radius: inner, startAngle: a0 + sweep, delta: -sweep)
    p.closeSubpath()
    return p
}

// --- The pinned chart ---

private struct PinnedChart: View {
    let slices: [CategorySlice]
    let total: Int
    let count: Int?
    @Binding var selected: String?

    var body: some View {
        VStack(spacing: 2) {
            if slices.isEmpty || total == 0 {
                Text("No spending recorded in the last 30 days.")
                    .font(Deck.body)
                    .foregroundStyle(Deck.muted)
                    .frame(height: chartHeight)
            } else {
                chart
                if selected == "Other", let other = slices.first(where: { $0.id == "Other" }) {
                    Text("Other: \(other.members.joined(separator: ", "))")
                        .font(LedgerType.rowMeta)
                        .foregroundStyle(Deck.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(height: chartHeight, alignment: .top)
        // No background of its own, deliberately: the rows are meant to be seen
        // passing behind it and fading out, which a filled background would hide.
        .background(.clear)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                let isSelected = selected == slice.id
                SectorMark(
                    angle: .value("Spend", Double(slice.total_cents)),
                    // Selection pulls the wedge out by growing ITS radius while
                    // the rest stay put; combined with the opacity dip below
                    // this is meant to be unmissable at a glance rather than on
                    // close inspection.
                    innerRadius: .ratio(innerRatio),
                    outerRadius: .ratio(isSelected ? selectedRatio : restingRatio)
                )
                // No inset and no corner radius: neighbours meet edge to edge
                // under the 2px ink separator the overlay draws, like the web
                // ring's stroked paths.
                .foregroundStyle(sliceColor(slice, at: index))
                .opacity(selected == nil || isSelected ? 1.0 : 0.3)
                .accessibilityLabel(slice.id)
                .accessibilityValue(formatCents(slice.total_cents))
            }
        }
        .chartLegend(.hidden)
        // The label never takes a tap: it is laid out across the whole plot
        // area, so without this it swallows every tap meant for a wedge.
        //
        // Sized to the HOLE, measured off the plot like the ring itself, so at
        // the largest Dynamic Type sizes the figures shrink inside it rather
        // than running under the wedges.
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let plot = geo[frame]
                    let hole = min(plot.width, plot.height) * restingRatio * innerRatio
                    centerLabel
                        .frame(width: hole * 0.84)
                        .position(x: plot.midX, y: plot.midY)
                }
            }
            .allowsHitTesting(false)
        }
        // Selection is handled here, by hand, rather than with
        // `chartAngleSelection`. That modifier stopped delivering anything at
        // all once the chart moved into a pinned overlay above a ScrollView -
        // no error, no log line, the wedges simply went dead. Rather than
        // guess at whose gesture wins, the tap is taken explicitly on an
        // overlay above the marks and converted with the same arithmetic
        // web/pie.js uses, so the phone and the browser resolve a tap on the
        // same spot to the same wedge.
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
                ZStack {
                    RingEdges(slices: slices, selected: selected, plot: plot)
                        .allowsHitTesting(false)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { point in
                            let plot = geo[proxy.plotFrame!]
                            guard let id = sliceHit(at: point, in: plot, slices: slices) else {
                                selected = nil  // the hole, or outside the ring
                                return
                            }
                            // Tapping the already-selected wedge deselects it - the
                            // same toggle as tapping a row in the list.
                            selected = (selected == id) ? nil : id
                        }
                }
            }
        }
        .frame(height: 206)
        // Room for a selected wedge to pull out without touching the header.
        .padding(.top, 8)
    }

    /// The label in the hole: the window's total by default, the tapped
    /// category BY NAME when there is one. Naming it is the point - a wedge
    /// showing only a dollar amount makes you match colours against a legend to
    /// know what you just tapped.
    @ViewBuilder
    private var centerLabel: some View {
        if let id = selected, let slice = slices.first(where: { $0.id == id }) {
            VStack(spacing: 3) {
                Text(id)
                    .font(Deck.label).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Deck.muted)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(formatCents(slice.total_cents))
                    .font(LedgerType.money(19, relativeTo: .title3))
                    .foregroundStyle(Deck.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(total > 0 ? "\(Int((Double(slice.total_cents) / Double(total) * 100).rounded()))% of spending" : "")
                    .font(Deck.mono(11, .medium, relativeTo: .caption))
                    .foregroundStyle(Deck.muted)
                    .lineLimit(1).minimumScaleFactor(0.4)
            }
        } else {
            VStack(spacing: 3) {
                Text("Last 30 days")
                    .font(Deck.label).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Deck.muted)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(formatCents(total))
                    .font(LedgerType.money(19, relativeTo: .title3))
                    .foregroundStyle(Deck.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                if let count {
                    Text("\(count) transaction\(count == 1 ? "" : "s")")
                        .font(Deck.mono(11, .medium, relativeTo: .caption))
                        .foregroundStyle(Deck.muted)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
        }
    }
}

/// The ink the SectorMarks cannot draw themselves: a 2px `Deck.line` edge round
/// every wedge - which is what keeps two neighbouring fills apart in both
/// themes, whatever their colours - and the hatch that marks Other. Dimmed with
/// its wedge, so a deselected slice's edge fades with it.
private struct RingEdges: View {
    let slices: [CategorySlice]
    let selected: String?
    let plot: CGRect

    var body: some View {
        Canvas { ctx, _ in
            let total = Double(slices.reduce(0) { $0 + $1.total_cents })
            guard total > 0, plot.width > 0 else { return }
            let center = CGPoint(x: plot.midX, y: plot.midY)
            let radius = min(plot.width, plot.height) / 2

            // One wedge is the whole ring: two circles, not a sector whose
            // start and end coincide (which would draw a seam at twelve).
            if slices.count == 1, let only = slices.first {
                let outer = radius * (selected == only.id ? selectedRatio : restingRatio)
                let inner = outer * innerRatio
                var ring = Path()
                ring.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
                ring.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
                if only.id == "Other" { hatch(ring, in: &ctx, eoFill: true) }
                ctx.stroke(ring, with: .color(Deck.line), lineWidth: Deck.borderWidth)
                return
            }

            var start = 0.0
            for slice in slices {
                let end = start + Double(slice.total_cents) / total * 2 * .pi
                let on = selected == slice.id
                let outer = radius * (on ? selectedRatio : restingRatio)
                let inner = outer * innerRatio
                let path = ringSector(center: center, inner: inner, outer: outer, start: start, end: end)
                var layer = ctx
                layer.opacity = selected == nil || on ? 1 : 0.3
                if slice.id == "Other" { hatch(path, in: &layer, eoFill: false) }
                layer.stroke(
                    path, with: .color(Deck.line),
                    style: StrokeStyle(lineWidth: Deck.borderWidth, lineJoin: .miter))
                start = end
            }
        }
    }

    /// Muted diagonal stripes clipped to `path` - the same --dk-hatch as the
    /// list swatch, over the rail the SectorMark already filled.
    private func hatch(_ path: Path, in ctx: inout GraphicsContext, eoFill: Bool) {
        var clipped = ctx
        clipped.clip(to: path, style: FillStyle(eoFill: eoFill))
        let box = path.boundingRect
        var lines = Path()
        var x = box.minX - box.height
        while x < box.maxX {
            lines.move(to: CGPoint(x: x, y: box.maxY))
            lines.addLine(to: CGPoint(x: x + box.height, y: box.minY))
            x += 5
        }
        clipped.stroke(lines, with: .color(Deck.muted), lineWidth: 2)
    }
}

/// Which wedge a tap landed on, or nil for the hole in the middle and for
/// anything outside the ring.
///
/// Free function, not a method, so the arithmetic can be reasoned about (and
/// tested) without a chart, a gesture, or a running app. The ring geometry has
/// to match the SectorMarks above: `innerRadius` .ratio(0.62), `outerRadius`
/// up to .ratio(1.0) when a wedge is selected and pulled out.
func sliceHit(
    at point: CGPoint, in plot: CGRect, slices: [CategorySlice],
    innerRatio: CGFloat = 0.62, outerRatio: CGFloat = 1.0
) -> String? {
    let total = slices.reduce(0) { $0 + $1.total_cents }
    guard total > 0 else { return nil }

    let center = CGPoint(x: plot.midX, y: plot.midY)
    // Swift Charts sizes a sector chart off the SHORTER side of the plot, so
    // the ring is always a circle rather than an ellipse.
    let radius = min(plot.width, plot.height) / 2
    let dx = point.x - center.x
    let dy = point.y - center.y
    let distance = (dx * dx + dy * dy).squareRoot()
    guard distance >= radius * innerRatio, distance <= radius * outerRatio else { return nil }

    // atan2 measures from three o'clock counter-clockwise in maths, but the
    // wedges start at twelve and run clockwise - hence the +90 degrees, and the
    // wrap into 0..<2pi so a tap in the top-left quadrant is not negative.
    var angle = atan2(dy, dx) + .pi / 2
    if angle < 0 { angle += 2 * .pi }

    let value = Double(angle / (2 * .pi)) * Double(total)
    var cumulative = 0.0
    for slice in slices {
        cumulative += Double(slice.total_cents)
        // STRICTLY less-than. A tap landing exactly on a boundary belongs to
        // the wedge that starts there, not the one that ends there - with `<=`
        // every boundary resolves backwards, which on an evenly-divided ring
        // shifts the answer a whole wedge for a tap dead-centre on a spoke.
        if value < cumulative { return slice.id }
    }
    return slices.last?.id
}

// --- Ranked list ---
//
// The pie is bad at showing small wedges apart - past a handful they blur into
// slivers of similar size and colour. This list is how those get read: every
// real category, ranked, with its own exact figure, even the ones folded into
// "Other" on the chart. Selecting one of those selects "Other" (there is
// nowhere else for it to point) and every row inside that wedge highlights
// together, so it is visible which ones the wedge stands for.

private struct SpendList: View {
    let spend: [CategorySpend]
    let slices: [CategorySlice]
    @Binding var selected: String?
    let chartBottom: CGFloat

    var body: some View {
        if spend.isEmpty {
            Text("No spending recorded in the last 30 days.")
                .font(Deck.body)
                .foregroundStyle(Deck.muted)
                .deckRow(separator: false)
        } else {
            let maxTotal = spend.map(\.total_cents).max() ?? 0
            ForEach(Array(spend.enumerated()), id: \.element.category) { position, row in
                let fraction = maxTotal > 0 ? Double(row.total_cents) / Double(maxTotal) : 0
                let id = sliceId(for: row.category, in: slices)
                let index = slices.firstIndex { $0.id == id } ?? 0
                let isSelected = selected == id
                // The swatch and the bar are what tie a row to its wedge
                // without a legend; rows folded into Other all carry Other's
                // hatch, which is the honest answer to "which wedge is this in".
                let fill = sliceFill(
                    slices.indices.contains(index)
                        ? slices[index]
                        : CategorySlice(id: id, total_cents: 0, count: 0, members: []),
                    at: index)

                Button {
                    selected = isSelected ? nil : id
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            DeckSwatch(fill: fill)
                            Text(row.category)
                                .font(LedgerType.rowTitle)
                                .foregroundStyle(Deck.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(formatCents(row.total_cents))
                                .font(LedgerType.money(15))
                                .foregroundStyle(Deck.ink)
                                .fixedSize()
                        }
                        // Drawn with plain shapes - no charting library needed
                        // for a single-value bar, unlike the pie.
                        LedgerBar(fraction: fraction, fill: fill, height: 12)
                        Text("\(row.count) transaction\(row.count == 1 ? "" : "s")")
                            .font(LedgerType.rowMeta)
                            .foregroundStyle(Deck.muted)
                    }
                    .padding(.vertical, 4)
                    // Deck's selected row: rail fill plus the 5px accent bar -
                    // the bar is the cue, so selection never rides on colour.
                    .deckRow(selected: isSelected, separator: position > 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .fadingBehindChart(chartBottom)
            }
        }
    }
}

// --- Top merchants ---

private struct MerchantsList: View {
    let merchants: [Merchant]
    let chartBottom: CGFloat

    var body: some View {
        ForEach(Array(merchants.enumerated()), id: \.element.id) { position, m in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.label)
                        .font(LedgerType.rowTitle)
                        .foregroundStyle(Deck.ink)
                        .lineLimit(2)
                    Text("\(m.count) transaction\(m.count == 1 ? "" : "s") · last \(formatShortDate(m.last_on))")
                        .font(LedgerType.rowMeta)
                        .foregroundStyle(Deck.muted)
                }
                Spacer(minLength: 8)
                Text(formatCents(m.total_cents))
                    .font(LedgerType.money(15))
                    .foregroundStyle(Deck.ink)
                    .fixedSize()
            }
            .padding(.vertical, 2)
            .deckRow(separator: position > 0)
            .accessibilityElement(children: .combine)
            .fadingBehindChart(chartBottom)
        }
    }
}
