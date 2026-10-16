//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreImage.CIFilterBuiltins
import JellyfinAPI
import SwiftUI

struct QuickConnectView: View {

    @Router
    private var router

    @State
    private var code: String? = nil
    @State
    private var error: Error? = nil

    let client: JellyfinClient
    let action: (String) async -> Void

    /// Jellyfin web's Quick Connect page with the code pre-filled, so a phone can approve by scanning.
    private func approvalURL(code: String) -> URL? {
        var base = client.configuration.url.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: "\(base)/web/#/quickconnect?code=\(code)")
    }

    private func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }

        return UIImage(cgImage: cgImage)
    }

    @ViewBuilder
    private func qrCard(code: String) -> some View {
        if let url = approvalURL(code: code), let image = qrImage(for: url) {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(UIDevice.isTV ? 24 : 12)
                    .background(.white, in: .rect(cornerRadius: UIDevice.isTV ? 28 : 16))
                    .frame(width: UIDevice.isTV ? 360 : 200, height: UIDevice.isTV ? 360 : 200)
                    .accessibilityHidden(true)

                Text(L10n.quickConnectScanToApprove)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var instructions: some View {
        BulletedList(spacing: 16) {
            Text(L10n.quickConnectStep1)

            Text(L10n.quickConnectStep2)

            Text(L10n.quickConnectStep3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codeLabel(_ code: String) -> some View {
        Text(code)
            .tracking(10)
            .font(.largeTitle)
            .monospacedDigit()
    }

    private func pollingView(code: String) -> some View {
        Group {
            #if os(tvOS)
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 40) {
                    instructions

                    codeLabel(code)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                qrCard(code: code)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            VStack(spacing: 20) {
                instructions

                codeLabel(code)

                qrCard(code: code)
                    .padding(.top, 20)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            #endif
        }
        .edgePadding()
    }

    var body: some View {
        ZStack {
            if let error {
                ErrorView(error: error)
            } else if let code {
                pollingView(code: code)
            } else {
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.2), value: code)
        .edgePadding()
        .task {
            do {
                for try await event in client.quickConnect.connect() {
                    switch event {
                    case let .polling(code: code):
                        self.code = code
                    case let .authenticated(secret: secret):
                        router.dismiss()
                        await action(secret)
                    }
                }
            } catch {
                self.error = error
            }
        }
        .navigationTitle(L10n.quickConnect)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
        #endif
    }
}
