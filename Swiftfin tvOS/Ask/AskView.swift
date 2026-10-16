//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Ask Glassfin: describe what you're in the mood for ("something like Ghosts but a little darker")
/// and get picks you can play or request.
///
/// The glass field brings up the tvOS keyboard (so the Siri Remote's mic dictates into it); closing the
/// keyboard or pressing its return key asks. Suggestion and recent-question chips ask with one press.
/// Results keep Claude's order, with its one-line reason under each card.
struct AskView: View {

    let initialQuery: String?

    @StateObject
    private var viewModel = AskViewModel()
    @StateObject
    private var feed = DiscoverViewModel.shared

    @Default(.Discover.askHistory)
    private var history
    @Default(.Discover.profile)
    private var profile

    @State
    private var text = ""

    @Router
    private var router

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private let columns = Array(
        repeating: GridItem(.fixed(CategoriesLayout.resultWidth), spacing: CategoriesLayout.gap, alignment: .top),
        count: 4
    )

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 56) {
                title

                fieldRow
                    .focusSection()

                content
            }
            .padding(.horizontal, CategoriesLayout.margin)
            .padding(.top, 50)
            .padding(.bottom, 80)
            .animation(.easeInOut(duration: 0.35), value: viewModel.phase)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(background.ignoresSafeArea())
        .onExitCommand(perform: viewModel.phase.isWorking ? { viewModel.cancel() } : nil)
        .onFirstAppear {
            SeerrStatusStore.installRequestHandler()
            feed.ensureLibrary()
            viewModel.prepareTaste()
            if let initialQuery {
                text = initialQuery
                viewModel.ask(initialQuery)
            } else {
                viewModel.checkAvailability()
            }
        }
    }

    // MARK: - Header

    private var title: some View {
        HStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(AskPalette.sparkleGradient)
                .accessibilityHidden(true)

            Text(L10n.askGlassfin)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var fieldRow: some View {
        HStack(spacing: 24) {
            GlassSearchField(
                text: $text,
                prompt: L10n.askGlassfinPrompt,
                systemImage: "sparkles",
                returnKeyType: .go,
                autocorrects: true,
                accessibilityID: "askField",
                onSubmit: askIfNew,
                onEndEditing: askIfNew
            )

            Button {
                ask(text)
            } label: {
                Label(L10n.askGlassfinAsk, systemImage: "arrow.up")
                    .padding(.vertical, 11)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(GlassChipButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("ask.askButton")
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > AskGlassfin.maxQueryLength {
                text = String(newValue.prefix(AskGlassfin.maxQueryLength))
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            CategoriesLayout.background

            // A faint iridescent wash behind the title, brighter while thinking
            Ellipse()
                .fill(AngularGradient(colors: AskPalette.spectrum, center: .center))
                .frame(width: 1500, height: 700)
                .blur(radius: 220)
                .opacity(viewModel.phase.isWorking ? 0.2 : 0.1)
                .offset(x: -420, y: -380)
                .animation(.easeInOut(duration: 1.2), value: viewModel.phase.isWorking)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            chips

        case let .thinking(query, since):
            AskWorkingView(query: query, mode: .thinking(since: since))

        case let .waitingToRetry(query, until):
            AskWorkingView(query: query, mode: .waiting(until: until))

        case let .results(answer):
            results(answer)

        case let .capReached(resetsAt, household):
            VStack(alignment: .leading, spacing: 56) {
                AskMessageView(
                    systemImage: "moon.stars",
                    title: L10n.askGlassfinCapTitle,
                    message: household ? L10n.askGlassfinCapGlobal(resetTime(resetsAt)) : L10n.askGlassfinCapProfile(resetTime(resetsAt)),
                    footnote: history.isEmpty ? nil : L10n.askGlassfinCapCached,
                    identifier: "ask.state.cap"
                )
                recentChips
            }

        case .offline:
            AskMessageView(
                systemImage: "wifi.slash",
                title: L10n.askGlassfinOfflineTitle,
                message: L10n.askGlassfinOffline,
                identifier: "ask.state.offline"
            ) {
                tryAgainButton
            }

        case let .notOnHomeNetwork(message):
            AskMessageView(
                systemImage: "house",
                title: L10n.askGlassfinHomeNetworkTitle,
                message: message ?? L10n.askGlassfinHomeNetwork,
                identifier: "ask.state.network"
            ) {
                tryAgainButton
            }

        case let .disabled(message):
            AskMessageView(
                systemImage: "power",
                title: L10n.askGlassfinDisabledTitle,
                message: message ?? L10n.askGlassfinDisabled,
                identifier: "ask.state.disabled"
            )

        case let .failed(message):
            AskMessageView(
                systemImage: "exclamationmark.bubble",
                title: L10n.askGlassfinFailedTitle,
                message: message,
                identifier: "ask.state.failed"
            ) {
                tryAgainButton
            }
        }
    }

    @ViewBuilder
    private var tryAgainButton: some View {
        Button {
            if viewModel.lastAsked != nil {
                viewModel.retry()
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
                ask(text)
            } else {
                viewModel.cancel()
                viewModel.checkAvailability()
            }
        } label: {
            Label(L10n.askGlassfinTryAgain, systemImage: "arrow.clockwise")
        }
        .buttonStyle(GlassChipButtonStyle())
        .accessibilityIdentifier("ask.tryAgain")
    }

    // MARK: Chips

    private struct Suggestion: Identifiable {
        let id: String
        let title: String
        let query: String
        let systemImage: String
    }

    private var suggestions: [Suggestion] {
        let loved = AskTaste.lovedTitleName(profile: profile)
        return [
            Suggestion(
                id: "love",
                title: L10n.askGlassfinSuggestionLove,
                query: loved.map(L10n.askGlassfinSomethingLike) ?? L10n.askGlassfinSuggestionLove,
                systemImage: "heart"
            ),
            Suggestion(
                id: "cozy",
                title: L10n.askGlassfinSuggestionCozy,
                query: L10n.askGlassfinSuggestionCozy,
                systemImage: "cup.and.saucer"
            ),
            Suggestion(
                id: "laugh",
                title: L10n.askGlassfinSuggestionLaugh,
                query: L10n.askGlassfinSuggestionLaugh,
                systemImage: "face.smiling"
            ),
            Suggestion(
                id: "animated",
                title: L10n.askGlassfinSuggestionAnimated,
                query: L10n.askGlassfinSuggestionAnimated,
                systemImage: "paintpalette"
            ),
            Suggestion(id: "short", title: L10n.askGlassfinSuggestionShort, query: L10n.askGlassfinSuggestionShort, systemImage: "clock"),
        ]
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 56) {
            chipSection(L10n.askGlassfinTryAsking) {
                ForEach(suggestions) { suggestion in
                    Button {
                        ask(suggestion.query)
                    } label: {
                        Label(suggestion.title, systemImage: suggestion.systemImage)
                    }
                    .buttonStyle(GlassChipButtonStyle())
                    .accessibilityIdentifier("ask.suggestion.\(suggestion.id)")
                }
            }

            recentChips
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var recentChips: some View {
        if history.isNotEmpty {
            chipSection(L10n.askGlassfinRecent) {
                ForEach(Array(history.enumerated()), id: \.element) { index, question in
                    Button {
                        ask(question)
                    } label: {
                        Label {
                            Text(question)
                                .frame(maxWidth: 760, alignment: .leading)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(GlassChipButtonStyle())
                    .accessibilityIdentifier("ask.recent.\(index)")
                }
            }
        }
    }

    private func chipSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityAddTraits(.isHeader)

            ChipFlowLayout(spacing: 20, lineSpacing: 24) {
                content()
            }
        }
        .focusSection()
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ answer: AskViewModel.Answer) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            if let interpretation = answer.interpretation, interpretation.isNotEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AskPalette.sparkleGradient)
                        .accessibilityHidden(true)
                    Text(interpretation)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                .font(.callout)
                .frame(maxWidth: 1500, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ask.interpretation")
            }

            if answer.items.isEmpty {
                AskMessageView(
                    systemImage: "sparkle.magnifyingglass",
                    title: L10n.askGlassfinNoMatchesTitle,
                    message: L10n.askGlassfinNoMatches,
                    identifier: "ask.state.empty"
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                    ForEach(answer.items) { item in
                        let card = displayItem(item)

                        DiscoverCard(item: card, viewModel: feed, width: CategoriesLayout.resultWidth, subtitleLineLimit: 3) {
                            open(card)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("ask.result.\(item.id)")
                    }
                }
                .focusSection()

                Text(L10n.discoverAttribution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: 1100, alignment: .leading)
            }

            recentChips
                .padding(.top, 16)
        }
        .transition(.opacity)
    }

    /// The library state can arrive after the answer; streaming badges load after it too.
    private func displayItem(_ item: DiscoverItem) -> DiscoverItem {
        var item = item
        item.libraryItemID = feed.libraryItemIDs[item.id] ?? item.libraryItemID
        item.providers = viewModel.providers[item.id] ?? item.providers
        return item
    }

    private func open(_ item: DiscoverItem) {
        if let libraryItemID = item.libraryItemID {
            router.route(to: .item(id: libraryItemID))
        } else {
            router.route(to: .discoverTitle(item: item, feed: feed))
        }
    }

    // MARK: - Actions

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return }

        text = trimmed
        viewModel.ask(trimmed)
    }

    /// Return key or closing the keyboard: ask when the text is new.
    private func askIfNew() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty, trimmed != viewModel.lastAsked else { return }

        ask(trimmed)
    }

    private func resetTime(_ date: Date?) -> String {
        // Retry-After counts whole seconds to midnight, so round up to the minute (12:00 AM, not 11:59 PM)
        let reset = date.map { Date(timeIntervalSinceReferenceDate: ($0.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60) }
            ?? Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        return reset.formatted(date: .omitted, time: .shortened)
    }
}

private extension String {

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension NavigationRoute {

    /// Ask Glassfin, optionally asking `query` right away (from the Search tab).
    @MainActor
    static func askGlassfin(query: String? = nil) -> NavigationRoute {
        NavigationRoute(id: "askGlassfin-\(query ?? "")") {
            AskView(initialQuery: query)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
