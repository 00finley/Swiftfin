//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - Palette

enum AskPalette {

    /// The iridescent sweep used for the sparkle's rim and the screen's glow
    static let spectrum: [Color] = [
        Color(red: 0.62, green: 0.42, blue: 1.00),
        Color(red: 0.31, green: 0.56, blue: 1.00),
        Color(red: 0.33, green: 0.86, blue: 0.96),
        Color(red: 1.00, green: 0.47, blue: 0.70),
        Color(red: 1.00, green: 0.68, blue: 0.38),
        Color(red: 0.62, green: 0.42, blue: 1.00),
    ]

    static let sparkleGradient = LinearGradient(
        colors: [
            Color(red: 0.78, green: 0.66, blue: 1.0),
            Color(red: 0.55, green: 0.80, blue: 1.0),
            Color(red: 1.0, green: 0.78, blue: 0.86)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Sparkle

/// Sparkles on a glass disc with a slowly turning iridescent rim (the Ask Glassfin mark).
/// While `isActive` the rim turns and glows and the sparkles shimmer; otherwise it rests.
struct AskSparkleGlyph: View {

    var size: CGFloat = 96
    var isActive = true
    /// Slower and dimmer, e.g. while waiting to retry
    var isCalm = false

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive || reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let turn = isActive && !reduceMotion ? (seconds / (isCalm ? 9 : 4)).truncatingRemainder(dividingBy: 1) : 0.12
            let breathe = isActive && !reduceMotion ? (sin(seconds * (isCalm ? 1.2 : 2.4)) + 1) / 2 : 0.5

            ZStack {
                // Soft glow behind the disc
                Circle()
                    .fill(AngularGradient(colors: AskPalette.spectrum, center: .center, angle: .degrees(turn * 360)))
                    .blur(radius: size * 0.28)
                    .opacity(isActive ? (isCalm ? 0.32 : 0.42 + 0.18 * breathe) : 0.18)
                    .scaleEffect(1.02 + 0.06 * breathe)

                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.2)), in: .circle)

                Circle()
                    .strokeBorder(
                        AngularGradient(colors: AskPalette.spectrum, center: .center, angle: .degrees(turn * 360)),
                        lineWidth: max(2, size * 0.035)
                    )
                    .opacity(isActive ? 0.95 : 0.55)

                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(AskPalette.sparkleGradient)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActive && !reduceMotion)
                    .scaleEffect(0.96 + 0.06 * breathe)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Placeholders

/// A card-shaped placeholder with a light sweep, the same size as `DiscoverCard`, so results
/// fill in where the placeholders were.
struct AskPlaceholderCard: View {

    var width: CGFloat = CategoriesLayout.resultWidth
    /// Staggers the sweep across a row
    var delay: Double = 0
    var isDimmed = false

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let period = 1.8
            let t = (context.date.timeIntervalSinceReferenceDate - delay).truncatingRemainder(dividingBy: period) / period
            let sweep = reduceMotion ? 0.5 : t * 1.6 - 0.3

            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.07))
                    .overlay {
                        shimmer(sweep)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                    .frame(width: width, height: width * 9 / 16)

                VStack(alignment: .leading, spacing: 12) {
                    bar(width: width * 0.58, height: 24, sweep: sweep)
                    bar(width: width * 0.92, height: 16, sweep: sweep)
                    bar(width: width * 0.7, height: 16, sweep: sweep)
                }
                .padding(.top, 2)
            }
            .opacity(isDimmed ? 0.55 : 1)
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat, sweep: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.07))
            .overlay {
                shimmer(sweep)
                    .clipShape(.capsule)
            }
            .frame(width: width, height: height)
    }

    private func shimmer(_ sweep: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: max(0, sweep - 0.25)),
                .init(color: .white.opacity(0.11), location: min(1, max(0, sweep))),
                .init(color: .white.opacity(0), location: min(1, sweep + 0.25)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Working states

/// "Asking Glassfin…" over two rows of placeholder cards; after a while it says it's still working.
/// While the helper is busy it counts down to the next try instead.
struct AskWorkingView: View {

    enum Mode: Equatable {
        case thinking(since: Date)
        case waiting(until: Date)
    }

    let query: String
    let mode: Mode

    private let columns = Array(
        repeating: GridItem(.fixed(CategoriesLayout.resultWidth), spacing: CategoriesLayout.gap, alignment: .top),
        count: 4
    )

    private var isWaiting: Bool {
        if case .waiting = mode {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            HStack(alignment: .center, spacing: 32) {
                AskSparkleGlyph(size: 92, isCalm: isWaiting)

                VStack(alignment: .leading, spacing: 8) {
                    Text(isWaiting ? L10n.askGlassfinBusy : L10n.askGlassfinThinking)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .accessibilityIdentifier("ask.working.title")

                    Text(L10n.askGlassfinQuoted(query))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(detail(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: detail(at: context.date))
                    }
                }
                .frame(maxWidth: 1300, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(isWaiting ? "ask.state.busy" : "ask.state.thinking")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                ForEach(0 ..< 8, id: \.self) { index in
                    AskPlaceholderCard(delay: Double(index % 4) * 0.14, isDimmed: isWaiting || index >= 4)
                }
            }
            .mask {
                // Fade the second row so the placeholders read as "more to come"
                LinearGradient(
                    stops: [.init(color: .black, location: 0.5), .init(color: .black.opacity(0.15), location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .transition(.opacity)
    }

    private func detail(at date: Date) -> String {
        switch mode {
        case let .thinking(since):
            let elapsed = date.timeIntervalSince(since)
            if elapsed > 45 {
                return L10n.askGlassfinTakingAWhile + "  ·  " + L10n.askGlassfinCancelHint
            }
            if elapsed > 18 {
                return L10n.askGlassfinStillThinking + "  ·  " + L10n.askGlassfinCancelHint
            }
            return L10n.askGlassfinCancelHint

        case let .waiting(until):
            let seconds = max(0, Int(until.timeIntervalSince(date).rounded(.up)))
            return L10n.askGlassfinRetryingIn(seconds) + "  ·  " + L10n.askGlassfinCancelHint
        }
    }
}

// MARK: - Message states

/// A centered state (offline, cap reached, turned off, an error): symbol on a glass disc, a title,
/// the explanation and optional actions.
struct AskMessageView<Actions: View>: View {

    let systemImage: String
    let title: String
    let message: String
    var footnote: String?
    var identifier: String
    @ViewBuilder
    var actions: () -> Actions

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 112, height: 112)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 1040)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)

            HStack(spacing: 24) {
                actions()
            }
            .padding(.top, 8)
            .focusSection()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .transition(.opacity)
    }
}

extension AskMessageView where Actions == EmptyView {

    init(systemImage: String, title: String, message: String, footnote: String? = nil, identifier: String) {
        self.init(systemImage: systemImage, title: title, message: message, footnote: footnote, identifier: identifier) {
            EmptyView()
        }
    }
}

// MARK: - Entry points

/// "✦ Ask Glassfin" glass chip for the Categories header.
struct AskGlassfinButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.askGlassfin, systemImage: "sparkles")
                .padding(.vertical, 8)
        }
        .buttonStyle(GlassChipButtonStyle())
        .accessibilityIdentifier("categories.ask")
    }
}

/// The Search tab's Ask action, right under the system search field: a glass capsule that sends the
/// typed text as a question ("✦ Ask Glassfin  “cozy shows to fall asleep to”"), or opens Ask Glassfin.
struct AskSearchAction: View {

    let query: String
    let action: () -> Void

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.askGlassfin)
                    .fontWeight(.semibold)
                Text(trimmed.isEmpty ? L10n.askGlassfinSearchHint : L10n.askGlassfinQuoted(trimmed))
                    .fontWeight(.regular)
                    .opacity(0.68)
                    .lineLimit(1)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(GlassChipButtonStyle())
        .accessibilityLabel(L10n.askGlassfin)
        .accessibilityValue(trimmed)
        .accessibilityIdentifier("search.ask")
        .animation(.easeOut(duration: 0.2), value: trimmed.isEmpty)
    }
}
