import SwiftUI
import UsageMeterCore

/// A labelled utilization bar (used for 5h, 7d and per-model rows).
/// `title` is already display-ready (a localized label or a model name).
struct UsageBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                }
            }
            .frame(height: 6)
            if let reset = ResetCountdown.value(until: resetsAt, now: Date()) {
                Text(Localized.reset(reset))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The popover content of the menu-bar item.
struct MenuContent: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var muse: PollingStore<MuseUsage>
    @EnvironmentObject var updates: UpdateStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.showPerModel) private var showPerModel = false

    private var rules: ColorRules { UserDefaults.standard.colorRules }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let usage = store.usage {
                windows(usage)
                let scoped = showPerModel ? usage.perModelLimits : usage.elevatedPerModelLimits
                if !scoped.isEmpty {
                    Divider()
                    perModel(scoped)
                }
                if let spend = usage.spend, spend.enabled == true, let used = spend.used {
                    Divider()
                    HStack {
                        Text("Spend").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2f %@", used.amount, used.currency))
                            .font(.system(size: 12).monospacedDigit())
                    }
                }
            } else if store.isLoading {
                Text("Loading…").foregroundStyle(.secondary).font(.system(size: 12))
            }

            if let err = store.lastError {
                if store.usage == nil && (err == .notLoggedIn || err == .signedOut) {
                    signInPrompt(err)
                } else {
                    Text(Localized.error(err))
                        .font(.system(size: 11))
                        .foregroundStyle(store.usage == nil ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
            museSection

            if let release = updates.available {
                Divider()
                Button {
                    NSWorkspace.shared.open(release.url)
                } label: {
                    Label(
                        Localized.string("update.available", release.version.description),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            // Opening the panel always tries to bring data up to date (and
            // recovers immediately if a transient error is showing).
            // Muse se obnovuje jen když jsou data starší než 4 minuty —
            // každý jeho poll je placený API call.
            Task {
                await store.refreshIfStale()
                await muse.refreshIfStale(240)
            }
        }
    }

    /// Empty state for "no credentials anywhere" / "sign-in died": explain and
    /// offer the fix instead of a bare error caption.
    private func signInPrompt(_ err: UsageErrorKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                Localized.string(err == .signedOut ? "empty.signed_out.body" : "empty.not_logged_in.body"),
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                openWindow(id: "signin")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("signin.button")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Text("signin.claude_code_hint")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack {
            Text("Usage").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { Task {
                await store.refreshNow()
                await muse.refreshNow()
            } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(Text("Refresh now"))
            .disabled(store.isLoading)
        }
    }

    private func windows(_ usage: Usage) -> some View {
        VStack(spacing: 12) {
            UsageBar(
                title: Localized.string("window.5h"),
                percent: usage.fiveHour?.utilization,
                resetsAt: usage.fiveHour?.resetsAt,
                color: rules.color(percent: usage.fiveHour?.utilization ?? 0, severity: usage.sessionSeverity)
            )
            UsageBar(
                title: Localized.string("window.weekly"),
                percent: usage.sevenDay?.utilization,
                resetsAt: usage.sevenDay?.resetsAt,
                color: rules.color(percent: usage.sevenDay?.utilization ?? 0, severity: usage.weeklySeverity)
            )
        }
    }

    /// Muse sekce: stejné UsageBar řádky jako Claude (5h + weekly s countdownem),
    /// ale bez severity (API ji nehlásí — barva jen z procent) a bez sign-in CTA
    /// (Muse login se dělá v terminálu přes `muse login`, ne v appce).
    private var museSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = muse.value {
                museWindows(m)
                if let err = muse.lastError {
                    Text(Localized.error(err))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if muse.isLoading {
                Text("Loading…").foregroundStyle(.secondary).font(.system(size: 12))
            } else if let err = muse.lastError {
                Text(err == .notLoggedIn ? Localized.string("muse.not_logged_in") : Localized.error(err))
                    .font(.system(size: 11))
                    .foregroundStyle(err == .notLoggedIn ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func museWindows(_ m: MuseUsage) -> some View {
        VStack(spacing: 12) {
            if let w = m.window {
                UsageBar(
                    title: Localized.string("muse.window"),
                    percent: w.usedPercent,
                    resetsAt: w.resetsAt,
                    color: rules.color(percent: w.usedPercent)
                )
            }
            if let week = m.weekly {
                UsageBar(
                    title: Localized.string("muse.weekly"),
                    percent: week.usedPercent,
                    resetsAt: week.resetsAt,
                    color: rules.color(percent: week.usedPercent)
                )
            }
            if m.window == nil && m.weekly == nil {
                Text("muse.no_quota")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func perModel(_ limits: [UsageLimit]) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(limits.enumerated()), id: \.offset) { _, limit in
                UsageBar(
                    title: limit.label,
                    percent: limit.percent,
                    resetsAt: limit.resetsAt,
                    color: rules.color(percent: limit.percent, severity: limit.severity)
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text(Localized.updatedAt(updated))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Preferences…") {
                openWindow(id: "preferences")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
    }
}
