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

    @Default(.Discover.seerrURL)
    private var seerrURL
    @Default(.Discover.seerrAPIKey)
    private var seerrAPIKey

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
                Button {
                    Defaults[.Discover.profile] = .init()
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
}
