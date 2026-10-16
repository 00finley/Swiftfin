//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

// MARK: - Disk cache

/// A small keyed JSON cache in Caches with per-entry expiry, loaded on first use and saved
/// a moment after the last change.
@MainActor
final class DiscoverKeyedCache<Value: Codable> {

    private struct Entry: Codable {
        let value: Value
        let expires: Date
    }

    private let url: URL
    private let maxEntries: Int
    private var entries: [String: Entry]?
    private var saveTask: Task<Void, Never>?

    init(fileName: String, maxEntries: Int = 4000) {
        url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        self.maxEntries = maxEntries
    }

    private var loaded: [String: Entry] {
        if let entries {
            return entries
        }
        let now = Date.now
        let decoded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let fresh = decoded.filter { $0.value.expires > now }
        entries = fresh
        return fresh
    }

    func value(for key: String) -> Value? {
        guard let entry = loaded[key], entry.expires > .now else { return nil }

        return entry.value
    }

    func set(_ value: Value, for key: String, ttl: TimeInterval) {
        var entries = loaded
        entries[key] = Entry(value: value, expires: .now.addingTimeInterval(ttl))
        if entries.count > maxEntries {
            // Drop the entries closest to expiring
            for (key, _) in entries.sorted(by: { $0.value.expires < $1.value.expires }).prefix(entries.count - maxEntries) {
                entries[key] = nil
            }
        }
        self.entries = entries
        scheduleSave()
    }

    func removeAll() {
        entries = [:]
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: url)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, let entries = self.entries,
                  let data = try? JSONEncoder().encode(entries)
            else { return }

            let url = self.url
            await Task.detached(priority: .utility) {
                try? data.write(to: url, options: .atomic)
            }.value
        }
    }
}

// MARK: - Card artwork

/// The art to draw on a 16:9 card: a backdrop with the title on it, or a logo for the textless one.
struct DiscoverArtworkPick: Codable, Hashable {

    /// English-language backdrop (these carry the title treatment)
    var titledBackdropPath: String?
    /// English logo for the textless backdrop, when there's no titled backdrop
    var logoPath: String?

    var isEmpty: Bool {
        titledBackdropPath == nil && logoPath == nil
    }

    init(titledBackdropPath: String? = nil, logoPath: String? = nil) {
        self.titledBackdropPath = titledBackdropPath
        self.logoPath = logoPath
    }

    init(images: TMDBImages) {
        let titled = (images.backdrops ?? [])
            .filter { image in
                guard image.iso_639_1 == "en" else { return false }
                guard let width = image.width, let height = image.height, height > 0 else { return true }

                return abs(Double(width) / Double(height) - 16 / 9) < 0.12
            }
            .min(by: TMDBImages.Image.isBetter)

        if let titled {
            self.init(titledBackdropPath: titled.file_path)
            return
        }

        // PNG first; TMDB renders SVG logos as PNG when asked for .png
        let logos = (images.logos ?? []).filter { $0.iso_639_1 == "en" }.sorted(by: TMDBImages.Image.isBetter)
        let logo = logos.first { $0.file_path.hasSuffix(".png") } ?? logos.first { $0.file_path.hasSuffix(".svg") }
        self.init(logoPath: logo.map { path in
            path.file_path.hasSuffix(".svg") ? String(path.file_path.dropLast(4)) + ".png" : path.file_path
        })
    }
}

/// Picks card art per title and remembers it in memory and on disk (3 weeks; 3 days when nothing
/// was found, so new titles pick up art later). Requests for the same title are shared and cancelled
/// once every card waiting on them has scrolled away.
@MainActor
final class DiscoverArtworkStore {

    static let shared = DiscoverArtworkStore()

    private let cache = DiscoverKeyedCache<DiscoverArtworkPick>(fileName: "DiscoverArtwork.json")
    private var inFlight: [String: (task: Task<DiscoverArtworkPick?, Never>, waiters: Int)] = [:]

    func cached(_ title: DiscoverTitle) -> DiscoverArtworkPick? {
        cache.value(for: title.id)
    }

    func pick(for title: DiscoverTitle) async -> DiscoverArtworkPick? {
        let key = title.id
        if let cached = cache.value(for: key) {
            return cached
        }

        let task: Task<DiscoverArtworkPick?, Never>
        if let entry = inFlight[key] {
            task = entry.task
            inFlight[key] = (task, entry.waiters + 1)
        } else {
            let kind = title.kind
            let id = title.tmdbID
            task = Task {
                guard let images = try? await TMDBClient.shared.images(kind: kind, id: id) else { return nil }

                return DiscoverArtworkPick(images: images)
            }
            inFlight[key] = (task, 1)
        }

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.leave(key, task: task) }
        }

        if inFlight[key]?.task == task {
            inFlight[key] = nil
        }
        if let result {
            cache.set(result, for: key, ttl: result.isEmpty ? 3 * 86400 : 21 * 86400)
        }
        return result
    }

    func clear() {
        cache.removeAll()
    }

    private func leave(_ key: String, task: Task<DiscoverArtworkPick?, Never>) {
        guard let entry = inFlight[key], entry.task == task else { return }

        if entry.waiters <= 1 {
            task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = (task, entry.waiters - 1)
        }
    }
}

/// 16:9 card art with the title on it, like the Apple TV app and the library's Thumb images:
/// a titled backdrop when TMDB has one, otherwise the textless backdrop with the English logo
/// bottom-left, otherwise the plain backdrop.
///
/// Art is looked up only while the card is near the screen, after a short pause so cards that
/// fly past during fast scrolling never ask.
struct DiscoverCardArtwork: View {

    let title: DiscoverTitle
    let width: CGFloat

    @State
    private var pick: DiscoverArtworkPick?
    @State
    private var isResolved: Bool
    @State
    private var isNearScreen = false

    init(title: DiscoverTitle, width: CGFloat) {
        self.title = title
        self.width = width
        let cached = DiscoverArtworkStore.shared.cached(title)
        _pick = State(initialValue: cached)
        _isResolved = State(initialValue: cached != nil || !TMDBClient.isAvailable)
    }

    private var height: CGFloat {
        width * 9 / 16
    }

    private var backdropPath: String? {
        pick?.titledBackdropPath ?? title.backdropPath
    }

    private var logoPath: String? {
        pick?.titledBackdropPath == nil ? pick?.logoPath : nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)

            if isResolved {
                ImageView(TMDBClient.imageURL(backdropPath, size: "w780"))
                    .placeholder { _ in Color.clear }
                    .failure { Color.clear }
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(.opacity)

                if let logoPath {
                    // Soft scrim in the logo's corner so light art keeps it legible
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.5), location: 0),
                            .init(color: .black.opacity(0.18), location: 0.45),
                            .init(color: .clear, location: 0.8),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    .transition(.opacity)

                    ImageView(TMDBClient.imageURL(logoPath, size: "w500"))
                        .placeholder { _ in EmptyView() }
                        .failure { EmptyView() }
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: width * 0.45, maxHeight: height * 0.36, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                        .padding(.leading, width * 0.055)
                        .padding(.bottom, height * 0.08)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: width, height: height)
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .global)
            // tvOS lays out at 1920×1080 points
            let screen = CGSize(width: 1920, height: 1080)
            return frame.maxX > -screen.width * 0.3 && frame.minX < screen.width * 1.3 &&
                frame.maxY > -screen.height * 0.5 && frame.minY < screen.height * 1.5
        } action: { isNear in
            isNearScreen = isNear
        }
        .task(id: isNearScreen ? title.id : nil) {
            guard isNearScreen, pick == nil else { return }

            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            // Don't leave an empty tile if TMDB is slow; show the plain backdrop meanwhile
            let fallback = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, !isResolved else { return }

                withAnimation(.easeOut(duration: 0.25)) { isResolved = true }
            }
            defer { fallback.cancel() }

            let result = await DiscoverArtworkStore.shared.pick(for: title)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.25)) {
                pick = result
                isResolved = true
            }
        }
    }
}

// MARK: - Title info

/// Name, genres and keywords for a title: taste input and seed names.
struct DiscoverTitleInfo: Codable, Hashable {
    let title: DiscoverTitle
    let keywords: [Int]
}

/// Title info cached on disk for 30 days, so a long seed list costs requests once a month.
@MainActor
final class DiscoverTitleInfoStore {

    static let shared = DiscoverTitleInfoStore()

    private let cache = DiscoverKeyedCache<DiscoverTitleInfo>(fileName: "DiscoverTitleInfo.json")
    private var inFlight: [String: Task<DiscoverTitleInfo?, Never>] = [:]

    func cached(_ key: String) -> DiscoverTitleInfo? {
        cache.value(for: key)
    }

    func info(kind: DiscoverTitle.Kind, id: Int) async -> DiscoverTitleInfo? {
        let key = "\(kind.rawValue)-\(id)"
        if let cached = cache.value(for: key) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task { try? await TMDBClient.shared.titleInfo(kind: kind, id: id) }
        inFlight[key] = task
        let info = await task.value
        inFlight[key] = nil
        if let info {
            cache.set(info, for: key, ttl: 30 * 86400)
        }
        return info
    }

    /// Info for many titles at once (TMDBClient limits concurrency), keyed by TMDB key.
    func infos(for keys: [String]) async -> [String: DiscoverTitleInfo] {
        var result: [String: DiscoverTitleInfo] = [:]
        var missing: [(kind: DiscoverTitle.Kind, id: Int)] = []
        for key in Set(keys) {
            if let cached = cache.value(for: key) {
                result[key] = cached
            } else if let kind = DiscoverTitle.Kind(rawValue: String(key.prefix { $0 != "-" })),
                      let id = Int(key.split(separator: "-").last ?? "")
            {
                missing.append((kind, id))
            }
        }
        guard missing.isNotEmpty else { return result }

        await withTaskGroup(of: (String, DiscoverTitleInfo?).self) { group in
            for (kind, id) in missing {
                group.addTask { @MainActor in
                    await ("\(kind.rawValue)-\(id)", self.info(kind: kind, id: id))
                }
            }
            for await (key, info) in group {
                result[key] = info
            }
        }
        return result
    }
}
