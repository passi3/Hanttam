//
//  PhotoFilterPicker.swift
//  Hanttam
//
//  Created by passi on 4/14/26.
//
//  Horizontal thumbnail-based filter picker. Shows a preview of how each
//  filter looks when applied to the current source image.
//

import SwiftUI
import UIKit
import Combine

struct PhotoFilterPicker: View {
    let filters: [PhotoFilterKind]
    let source: UIImage?
    @Binding var selection: PhotoFilterKind

    @StateObject private var store = ThumbnailStore()
    private let thumbSize: CGFloat = 64
    private let cardWidth: CGFloat = 76

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filters, id: \.cacheKey) { filter in
                    Button {
                        selection = filter
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(for: filter)
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            selection == filter ? Color.accentColor : Color.black.opacity(0.08),
                                            lineWidth: selection == filter ? 2 : 0.5
                                        )
                                )

                            Text(filter.displayName)
                                .font(.system(size: 10, weight: selection == filter ? .semibold : .regular))
                                .foregroundStyle(selection == filter ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: cardWidth)
                        }
                        .frame(width: cardWidth)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(height: thumbSize + 28)
        .onAppear { store.prepare(source: source, filters: filters) }
        .onChange(of: sourceIdentity) { _, _ in
            store.prepare(source: source, filters: filters)
        }
    }

    /// Use the object identity of UIImage to trigger updates without requiring
    /// UIImage to conform to Equatable in the expected way.
    private var sourceIdentity: Int {
        guard let source else { return 0 }
        return ObjectIdentifier(source).hashValue
    }

    @ViewBuilder
    private func thumbnail(for filter: PhotoFilterKind) -> some View {
        ZStack {
            Color(UIColor.secondarySystemBackground)
            if let img = store.thumbnails[filter.cacheKey] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if source != nil {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Thumbnail Store

final class ThumbnailStore: ObservableObject {
    @Published private(set) var thumbnails: [String: UIImage] = [:]

    private var currentSourceID: ObjectIdentifier?
    private let queue = DispatchQueue(label: "com.hanttam.thumbnailStore", qos: .userInitiated)

    func prepare(source: UIImage?, filters: [PhotoFilterKind]) {
        guard let source else {
            thumbnails = [:]
            currentSourceID = nil
            return
        }
        let sourceID = ObjectIdentifier(source)
        if sourceID == currentSourceID, !thumbnails.isEmpty { return }
        currentSourceID = sourceID
        thumbnails = [:]

        queue.async { [weak self] in
            let base = FilmFilterEngine.shared.downscale(source, maxDim: 160)
            for filter in filters {
                let rendered = FilmFilterEngine.shared.applySimple(kind: filter, to: base) ?? base
                let key = filter.cacheKey
                DispatchQueue.main.async {
                    guard let self, self.currentSourceID == sourceID else { return }
                    self.thumbnails[key] = rendered
                }
            }
        }
    }
}
