//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct DiscoverSettingsView: View {

    @Default(.Discover.providers)
    private var providers
    @Default(.Discover.region)
    private var region
    @Default(.Discover.showOnHome)
    private var showOnHome
    @Default(.Discover.searchIncludesRequestable)
    private var searchIncludesRequestable
    @Default(.Discover.seasonalCollections)
    private var seasonalCollections
    @Default(.Discover.funDays)
    private var funDays

    @Default(.Discover.seerrURL)
    private var seerrURL
    @Default(.Discover.seerrAPIKey)
    private var seerrAPIKey

    @Default(.Discover.profile)
    private var profile

    @Default(.Discover.askEnabled)
    private var askEnabled
    @Default(.Discover.askRemaining)
    private var askRemaining
    /// From `/health` when the last count is from an earlier day
    @State
    private var freshAskRemaining: Int?
    @State
    private var isCheckingAsk = false

    @Router
    private var router

    @State
    private var didReset = false
    @State
    private var connection: ConnectionState = .idle

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case connected
        case failed(String)
    }

    private func testConnection() {
        connection = .testing
        Task {
            do {
                try await SeerrClient.shared.ping()
                connection = .connected
            } catch {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    private let regions = ["US", "CA", "GB", "AU", "IE", "NZ"]

    var body: some View {
        Form(systemImage: "sparkles.tv") {
            Section {
                Toggle(L10n.discoverShowOnHome, isOn: $showOnHome)
            } header: {
                Text(L10n.home)
            } footer: {
                Text(L10n.discoverShowOnHomeDescription)
            }

            Section {
                Toggle(L10n.collectionsSeasonal, isOn: $seasonalCollections)
                Toggle(L10n.collectionsFunDays, isOn: $funDays)
                    .disabled(!seasonalCollections)
            } header: {
                Text(L10n.collections)
            } footer: {
                Text(L10n.collectionsDescription)
            }

            Section {
                Toggle(L10n.searchIncludeRequestable, isOn: $searchIncludesRequestable)
            } header: {
                Text(L10n.search)
            } footer: {
                Text(L10n.searchIncludeRequestableDescription)
            }

            if AskGlassfin.isConfigured {
                askSection
            }

            Section(L10n.discoverStreamingServices) {
                ForEach(DiscoverProvider.supported) { provider in
                    Toggle(provider.name, isOn: Binding(
                        get: { providers.contains(provider.id) },
                        set: { isOn in
                            if isOn {
                                providers.append(provider.id)
                            } else {
                                providers.removeAll { $0 == provider.id }
                            }
                        }
                    ))
                }
            }

            Section {
                Picker(L10n.discoverRegion, selection: $region) {
                    ForEach(regions, id: \.self) { code in
                        Text(Locale.current.localizedString(forRegionCode: code) ?? code)
                            .tag(code)
                    }
                }
            }

            Section {
                TextField(L10n.seerrServerURL, text: $seerrURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                SecureField(L10n.seerrAPIKey, text: $seerrAPIKey)

                Button(action: testConnection) {
                    HStack {
                        Text(L10n.seerrTestConnection)
                        Spacer()
                        switch connection {
                        case .idle:
                            EmptyView()

                        case .testing:
                            ProgressView()

                        case .connected:
                            Label(L10n.seerrConnected, systemImage: "checkmark")
                                .foregroundStyle(.secondary)

                        case let .failed(message):
                            Text(message)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(!SeerrClient.isConfigured || connection == .testing)
            } header: {
                Text(L10n.seerrRequests)
            } footer: {
                Text(L10n.seerrRequestsDescription)
            }
            .onChange(of: seerrURL) {
                connection = .idle
                SeerrStatusStore.shared.reset()
                SeerrStatusStore.installRequestHandler()
            }
            .onChange(of: seerrAPIKey) {
                connection = .idle
                SeerrStatusStore.shared.reset()
                SeerrStatusStore.installRequestHandler()
            }

            Section {
                ChevronButton(
                    L10n.discoverYourRatings,
                    content: "\(profile.ratedTitles().values.count(where: { $0.level != .neutral }))"
                ) {
                    router.route(to: .discoverRatings)
                }

                Button {
                    Defaults[.Discover.profile] = .init()
                    DiscoverArtworkStore.shared.clear()
                    Task { await TMDBClient.shared.clearCache() }
                    didReset = true
                } label: {
                    HStack {
                        Text(L10n.discoverResetRecommendations)
                        Spacer()
                        if didReset {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } header: {
                Text(L10n.discoverPersonalization)
            } footer: {
                Text(L10n.discoverPersonalizationDescription)
            }
        }
        .navigationTitle(L10n.discover)
    }

    // MARK: - Ask Glassfin

    /// What's left today: the last count the helper reported, or a fresh day's cap from `/health`.
    private var askRemainingText: String {
        if let askRemaining, askRemaining.isToday {
            return "\(askRemaining.count)"
        }
        if let freshAskRemaining {
            return "\(freshAskRemaining)"
        }
        return "—"
    }

    private func refreshAskRemaining() {
        guard !isCheckingAsk else { return }

        isCheckingAsk = true
        Task {
            freshAskRemaining = await AskGlassfin.health()?.freshRemaining
            isCheckingAsk = false
        }
    }

    private var askSection: some View {
        Section {
            Toggle(isOn: $askEnabled) {
                Label(L10n.askGlassfin, systemImage: "sparkles")
            }

            if askEnabled {
                Button(action: refreshAskRemaining) {
                    HStack {
                        Text(L10n.askGlassfinQuestionsLeft)
                        Spacer()
                        if isCheckingAsk {
                            ProgressView()
                        } else {
                            Text(askRemainingText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityIdentifier("settings.askRemaining")
                .task {
                    if askRemaining?.isToday != true {
                        refreshAskRemaining()
                    }
                }
            }
        } header: {
            Text(L10n.askGlassfin)
        } footer: {
            Text(L10n.askGlassfinDescription)
        }
    }
}
