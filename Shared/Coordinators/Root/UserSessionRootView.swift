//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

struct UserSessionRootView: View {

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    var body: some View {
        ZStack {
            switch userSessionManager.state {
            case .initial:
                ProgressView()

            case .signedOut:
                NavigationInjectionView(coordinator: .init()) {
                    SelectUserView()
                }

            case .signedIn:
                PosterPreferencesEnvironment {
                    MainTabView()
                }
                .id(userSessionManager.currentSession?.user.id)
            }
        }
        .animation(.linear(duration: 0.1), value: userSessionManager.state)
        .task {
            await userSessionManager.start()
        }
        #if os(tvOS)
        .task(id: userSessionManager.currentSession?.user.id) {
            // Let Siri learn the library's titles for "Play <show> in Glassfin"
            guard userSessionManager.currentSession != nil else { return }

            GlassfinShortcuts.updateAppShortcutParameters()
        }
        #endif
        .onOpenURL { url in
            #if os(tvOS)
            // glassfin://play?title=..., glassfin://continue (the Siri intents' actions)
            if let action = PlaybackURLAction(url) {
                Task { await action.perform() }
                return
            }
            #endif

            guard let authenticationAction else { return }

            Task {
                await userSessionManager.handleOpenURL(
                    url,
                    authenticationAction: authenticationAction
                )
            }
        }
    }
}

private struct PosterPreferencesEnvironment<Content: View>: View {

    @Default(.Customization.Poster.configuration)
    private var posterConfiguration

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.posterConfiguration, posterConfiguration)
    }
}
