import SwiftUI
import UIKit

// Ledger's own pieces on top of Deck Cream.
//
// DeckCream.swift and DeckExtras.swift are unedited copies of
// the design system's ios and must stay that way. Everything here
// is built from their tokens only - no colour in this file is a literal - and
// each piece names the web/deck.css component it mirrors, so it can move into
// the shared system later without being redesigned.

// MARK: - Type roles

enum LedgerType {
    /// Money is always IBM Plex Mono: every glyph is the same width, so a column
    /// of amounts lines up on the decimal point (the web's `.tabular`).
    static func money(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Deck.mono(size, .semibold, relativeTo: style)
    }
    /// A row's name - what the row IS. Space Grotesk, like `.row .primary`.
    static let rowTitle = Deck.sans(15, .bold, relativeTo: .body)
    /// The data line under a row - dates, counts, categories.
    static let rowMeta = Deck.mono(12, .medium, relativeTo: .footnote)
}

// MARK: - Screen header (the web's .topbar: rail strip, 3px edge)

/// Title (and an optional mono label line) on the rail, with the screen's
/// controls on the right. Replaces the navigation bar, whose large title and
/// rounded bar buttons cannot be restyled into Deck.
struct LedgerHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// The accent square the web puts before "LEDGER" (`.dk-mark`).
    var mark = false
    @ViewBuilder var trailing: Trailing

    init(
        _ title: String, subtitle: String? = nil, mark: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.mark = mark
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    if mark {
                        Rectangle().fill(Deck.accent)
                            .overlay(Rectangle().strokeBorder(Deck.line, lineWidth: Deck.borderWidth))
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(Deck.title)
                        .textCase(.uppercase)
                        .foregroundStyle(Deck.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle).deckLabel().lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        // One height on every tab, whether a header carries buttons, a label
        // line or neither - so switching tabs never makes the page jump.
        .frame(minHeight: 50)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .deckBar(.top)
    }
}

// MARK: - Titled card (dk-card + dk-card__head + dk-card__body)

/// The 3px/5px Deck card with a rail head strip ruled off from its body -
/// every section on the web dashboard is one of these.
struct LedgerCard<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Deck.label).textCase(.uppercase).tracking(0.66)
                    .foregroundStyle(Deck.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                accessory
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Deck.rail)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Deck.line).frame(height: Deck.borderWidth)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .deckCard()
    }
}

// MARK: - Hatch (--dk-hatch: "mixed / other")

/// Muted diagonal stripes on the rail - the web's `--dk-hatch`, and what
/// "Other" is painted with on the pie and in the list. Several categories must
/// not look like one, so Other is a texture rather than one more colour.
struct DeckHatch: View {
    var spacing: CGFloat = 5
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Deck.rail))
            var p = Path()
            var x = -size.height
            while x < size.width + size.height {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(p, with: .color(Deck.muted), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Swatch (the web's .cat-row .swatch)

/// A 12pt square with a 2px ink edge, filled with a slice's colour - or hatched
/// for Other - tying a list row to its pie wedge without a legend.
struct DeckSwatch: View {
    let fill: SliceFill
    var side: CGFloat = 12

    var body: some View {
        ZStack {
            switch fill {
            case .color(let c): Rectangle().fill(c)
            case .hatch: DeckHatch(spacing: 4, lineWidth: 1.5)
            }
        }
        .frame(width: side, height: side)
        .overlay(Rectangle().strokeBorder(Deck.line, lineWidth: Deck.borderWidth))
        .accessibilityHidden(true)
    }
}

/// How a slice is painted: one Deck fill, or the hatch that means "Other".
enum SliceFill: Equatable {
    case color(Color)
    case hatch
}

// MARK: - Bar (dk-meter with any fill)

/// DeckMeter, but the fill can be the hatch - DeckMeter only takes a Color, and
/// Other's bar has to match Other's wedge.
struct LedgerBar: View {
    var fraction: Double
    var fill: SliceFill
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let inner = max(0, geo.size.width - Deck.borderWidth * 2)
            let w = inner * CGFloat(min(1, max(0, fraction)))
            ZStack(alignment: .leading) {
                Rectangle().fill(Deck.surface)
                Group {
                    switch fill {
                    case .color(let c): Rectangle().fill(c)
                    case .hatch: DeckHatch(spacing: 4, lineWidth: 1.5)
                    }
                }
                .frame(width: w)
                .overlay(alignment: .trailing) {
                    if w > 0 && w < inner {
                        Rectangle().fill(Deck.line).frame(width: Deck.borderWidth)
                    }
                }
                .padding(Deck.borderWidth)
            }
            .overlay(Rectangle().strokeBorder(Deck.line, lineWidth: Deck.borderWidth))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Loading / failure (every tab's "no summary yet" states)

/// What a tab shows before it has a summary: a spinner while the one shared
/// fetch runs, the failure once it has failed. Identical on every tab, so it is
/// one view rather than four copies that could drift.
struct LedgerSummaryGate<Content: View>: View {
    @Environment(LedgerStore.self) private var store
    @ViewBuilder var content: (Summary) -> Content

    var body: some View {
        if let s = store.summary {
            content(s)
        } else if store.loading {
            VStack(spacing: 10) {
                ProgressView().tint(Deck.muted)
                Text("Loading").deckLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = store.fatal {
            VStack {
                DeckAlert(.crit, title: "Can't load Ledger", message: e.localizedDescription)
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Checkbox toggle (dk-check as a Toggle)

/// A Toggle drawn as Deck's square checkbox, the label in Space Grotesk. The
/// whole row is the tap target, never less than 44pt tall.
struct DeckCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                DeckCheck(state: configuration.isOn ? .on : .off, side: 22)
                configuration.label
                    .font(Deck.body)
                    .foregroundStyle(Deck.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - Field chrome with a focus flag from outside

/// The DeckFieldStyle look for a field whose focus the SCREEN already drives
/// with its own `.focused(_:equals:)` - DeckFieldStyle keeps a private focus
/// state, and two focus bindings on one field is asking for the keyboard's
/// "next" to land nowhere.
struct DeckFieldChrome: ViewModifier {
    var focused: Bool
    var invalid = false
    var mono = false

    func body(content: Content) -> some View {
        content
            .font(mono ? Deck.number : Deck.body)
            .foregroundStyle(Deck.ink)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(Deck.surface)
            .overlay(Rectangle().strokeBorder(invalid ? Deck.critInk : Deck.line, lineWidth: Deck.borderWidth))
            .background(
                Rectangle().fill(invalid ? Deck.crit : Deck.accent)
                    .offset(x: 3, y: 3).opacity(focused || invalid ? 1 : 0)
            )
            .padding(.trailing, 3).padding(.bottom, 3)
    }
}

extension View {
    func deckFieldChrome(focused: Bool, invalid: Bool = false, mono: Bool = false) -> some View {
        modifier(DeckFieldChrome(focused: focused, invalid: invalid, mono: mono))
    }
}

// MARK: - Menu picker (the web's .dk-select)

/// A Picker behind a Deck field: the current choice in a bordered box with the
/// up/down chevron, the system menu on tap. The system's own menu-style picker
/// label is a tinted plain string that reads as a link, not a control.
struct DeckMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    Text(opt.1).tag(opt.0)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == selection }?.1 ?? "—")
                    .font(Deck.body)
                    .foregroundStyle(Deck.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Deck.ink)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(Deck.surface)
            .overlay(Rectangle().strokeBorder(Deck.line, lineWidth: Deck.borderWidth))
            .background(Rectangle().fill(Deck.shadow).offset(x: Deck.shadowSmall, y: Deck.shadowSmall))
            .padding(.trailing, Deck.shadowSmall).padding(.bottom, Deck.shadowSmall)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
    }
}

// MARK: - Sheet header (dk-dialog head)

/// The rail header a sheet opens with: the title, and the sheet's own buttons
/// where a navigation bar's would be.
struct LedgerSheetHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leading
            Text(title)
                .font(Deck.heading)
                .textCase(.uppercase)
                .foregroundStyle(Deck.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .deckBar(.top)
    }
}

// MARK: - Tab bar (UIKit appearance - SwiftUI has no styling hook for it)

enum DeckTabBar {
    /// Rail background, a 3px ink top edge, Plex Mono titles, accent-ink
    /// selection. Called once from the App's init, after the fonts register -
    /// a UIFont asked for before that falls back to the system face.
    @MainActor
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Deck.rail)
        appearance.shadowColor = nil
        appearance.shadowImage = edgeImage()

        let font =
            UIFont(name: Deck.MonoWeight.semibold.rawValue, size: 10)
            ?? .monospacedSystemFont(ofSize: 10, weight: .semibold)
        let normal = UIColor(Deck.muted)
        let selected = UIColor(Deck.accentInk)
        for item in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.font: font, .foregroundColor: normal, .kern: 0.4]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.font: font, .foregroundColor: selected, .kern: 0.4]
        }

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.tintColor = selected
        bar.unselectedItemTintColor = normal
    }

    /// The top edge as an image, one per appearance: `shadowColor` alone draws
    /// a hairline, and Deck's structural edge is 3pt. Registered on one
    /// UIImageAsset so it flips with the system appearance like every token.
    @MainActor
    private static func edgeImage() -> UIImage {
        let asset = UIImageAsset()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let colour = UIColor(Deck.line).resolvedColor(with: traits)
            let format = UIGraphicsImageRendererFormat(for: traits)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: Deck.borderWidthLarge), format: format)
                .image { ctx in
                    colour.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 1, height: Deck.borderWidthLarge))
                }
            asset.register(image, with: traits)
        }
        return asset.image(with: UITraitCollection(userInterfaceStyle: .light))
    }
}
