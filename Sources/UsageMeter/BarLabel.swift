import SwiftUI
import UsageMeterCore

/// The compact view shown in the menu bar.
///
/// macOS renders a MenuBarExtra label as a *template* image — it recolours
/// everything to match the bar, so `.foregroundColor` on Text/Shapes is ignored
/// (percentages come out plain white/black). To keep our severity colours we
/// rasterize the content into a **non-template** NSImage and show that; a
/// non-template image with `.renderingMode(.original)` displays its real colours.
struct BarLabel: View {
    let usage: Usage?
    let error: UsageErrorKind?
    let muse: MuseUsage?
    let showMuse: Bool
    let codex: CodexUsage?
    let showCodex: Bool
    let mode: BarDisplayMode
    let rules: ColorRules

    /// Čtení vzhledu má dva účely: rendereru předáme správnou appearance (jinak
    /// by pekl vždy světlou) a změna vzhledu automaticky překreslí label.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: rendered)
            .renderingMode(.original)
    }

    @MainActor private var rendered: NSImage {
        let content = LabelContent(usage: usage, error: error, muse: muse, showMuse: showMuse, codex: codex, showCodex: showCodex, mode: mode, rules: rules)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage(size: .zero) }
        image.isTemplate = false   // keep our colours instead of being tinted
        return image
    }
}

/// The actual visual (dot + coloured percentages). Rendered off-screen to an
/// image by `BarLabel`, so ordinary SwiftUI colours work here.
private struct LabelContent: View {
    let usage: Usage?
    let error: UsageErrorKind?
    let muse: MuseUsage?
    let showMuse: Bool
    let codex: CodexUsage?
    let showCodex: Bool
    let mode: BarDisplayMode
    let rules: ColorRules

    private var hasError: Bool { error != nil }
    /// No credentials at all / sign-in dead — a state the user can fix by
    /// signing in, so show a person glyph instead of the generic warning.
    private var needsSignIn: Bool { error == .notLoggedIn || error == .signedOut }
    private var fiveHour: Double? { usage?.fiveHour?.utilization }
    private var sevenDay: Double? { usage?.sevenDay?.utilization }
    /// Muse 5h okno pro duální label. Záměrně jen window (ne weekly) — menu bar
    /// má místo na jedno číslo; weekly je v panelu.
    private var museFiveHour: Double? { muse?.window?.usedPercent }
    /// Codex primary okno (typicky 5h) — stejný důvod.
    private var codexPrimary: Double? { codex?.primary?.usedPercent }
    /// The dot answers "is anything close to blocking me?", so it keeps the
    /// worst-across-all severity. The percentages answer "how full is *this*
    /// window?" and must only ever reflect their own limit.
    /// Tečka identifikuje providera brand barvou (severity dál nesou procenta).
    /// Při chybě pollu zešedne jako signál zastaralosti.
    private var dotColor: Color {
        hasError ? .secondary : .claudeBrand
    }
    private var fiveHourColor: Color {
        hasError ? .secondary : rules.color(percent: fiveHour ?? 0, severity: usage?.sessionSeverity ?? .normal)
    }
    private var weeklyColor: Color {
        hasError ? .secondary : rules.color(percent: sevenDay ?? 0, severity: usage?.weeklySeverity ?? .normal)
    }
    private var museColor: Color {
        rules.color(percent: museFiveHour ?? 0)
    }
    private var codexColor: Color {
        rules.color(percent: codexPrimary ?? 0)
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasError && usage == nil {
                Image(systemName: needsSignIn ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                switch mode {
                case .dotOnly:
                    dot
                case .fiveHourOnly:
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                case .fiveAndSeven:
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                        + Text(" · ").foregroundColor(.primary)
                        + Text(pct(sevenDay)).foregroundColor(weeklyColor)
                case .dotAndFiveHour:
                    dot
                    Text(pct(fiveHour)).foregroundColor(fiveHourColor)
                }
            }
            if showMuse, let mpct = museFiveHour {
                Circle().fill(Color.museBrand).frame(width: 7, height: 7)
                Text(pct(mpct)).foregroundColor(museColor)
            }
            if showCodex, let cpct = codexPrimary {
                Circle().fill(Color.codexBrand).frame(width: 7, height: 7)
                Text(pct(cpct)).foregroundColor(codexColor)
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .padding(.vertical, 1)
    }

    private var dot: some View {
        Circle().fill(dotColor).frame(width: 7, height: 7)
    }

    private func pct(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }
}

/// Brand barvy providerů pro tečky v menu baru.
extension Color {
    /// Claude oranžová (#D97757).
    static let claudeBrand = Color(red: 0.851, green: 0.467, blue: 0.341)
    /// Meta modrá (#0064E0).
    static let museBrand = Color(red: 0.0, green: 0.392, blue: 0.878)
    /// ChatGPT zelená (#10A37C).
    static let codexBrand = Color(red: 0.063, green: 0.639, blue: 0.486)
}
