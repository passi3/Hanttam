//
//  ChartPhotoShareView.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import SwiftUI
import Combine
import Photos
import AVFoundation

private extension View {
    @ViewBuilder
    func colorInvertIf(_ condition: Bool) -> some View {
        if condition { colorInvert() } else { self }
    }
}

// MARK: - Overlay Text Color Environment

struct OverlayTextColorKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

struct OverlaySubTextColorKey: EnvironmentKey {
    static let defaultValue: Color = .white.opacity(0.5)
}

extension EnvironmentValues {
    var overlayTextColor: Color {
        get { self[OverlayTextColorKey.self] }
        set { self[OverlayTextColorKey.self] = newValue }
    }
    var overlaySubTextColor: Color {
        get { self[OverlaySubTextColorKey.self] }
        set { self[OverlaySubTextColorKey.self] = newValue }
    }
}

// MARK: - Chart Photo Share View

struct ChartPhotoShareView<ChartContent: View>: View {

    private struct SelectedSubjectLayer: Identifiable, Equatable {
        let id: Int
        var isBehindOverlay: Bool
        var isLifted: Bool = false
        var scanProgress: CGFloat = 0
        var topRatio: CGFloat = 0
        var bottomRatio: CGFloat = 1
    }

    @ViewBuilder let chartContent: () -> ChartContent

    @Environment(\.dismiss) private var dismiss

    // Photo
    @State private var photo: UIImage?
    @State private var glassPhoto: UIImage?
    @State private var subjects: [ExtractedSubject] = []
    @State private var selectedSubjects: [SelectedSubjectLayer] = []
    @State private var isExtracting = false

    // Photo list (for swipe navigation)
    @State private var photoAssets: [PHAsset] = []
    @State private var currentAssetIndex: Int = -1
    @State private var adjacentThumbs: [Int: UIImage] = [:]
    @State private var dragBaseIndex: Int = -1

    // Overlay
    @State private var overlayOffset: CGSize = .zero
    @State private var dragAccumulated: CGSize = .zero
    @State private var overlayScale: CGFloat = 0.8
    @State private var scaleAccumulated: CGFloat = 0.8
    @State private var solidTone: Double = 0.0  // -1(흰) ~ 0(투명) ~ +1(검정)
    @State private var bgStyle: OverlayBgStyle = .solid
    @State private var editSegment: EditSegment = .chart
    @State private var subjectFilter: PhotoFilterKind = .original
    @State private var chartFilter: PhotoFilterKind = .original
    @State private var bgFilter: PhotoFilterKind = .original
    @State private var pixelatedBgPhoto: UIImage?
    @State private var pixelatedSubjectPhotos: [Int: UIImage] = [:]
    /// Baked filter results for the background, keyed by filter cacheKey.
    @State private var filteredBgPhotos: [String: UIImage] = [:]
    /// Baked filter results for each subject, keyed by "\(subjectID)_\(cacheKey)".
    @State private var filteredSubjectPhotos: [String: UIImage] = [:]
    @State private var longPressTimer: DispatchWorkItem?
    @State private var guidanceScanProgress: CGFloat = 0
    @State private var touchSubjectID: ExtractedSubject.ID?
    @State private var didHandleTouchAsSubject = false
    @State private var activeDismissSubjectID: ExtractedSubject.ID?

    private let subjectDragDismissThreshold: CGFloat = 24
    private let subjectLongPressMovementThreshold: CGFloat = 10

    private enum OverlayBgStyle: String, CaseIterable {
        case solid = "솔리드"
        case glass = "글래스"
    }

    private enum EditSegment: String, CaseIterable {
        case bg      = "배경"
        case chart   = "차트"
        case subject = "피사체"
    }


    // Camera
    @State private var showCamera = false

    // Save
    @State private var isSaving = false
    @State private var saveResult: ShareSaveResult?
    @State private var shouldDismissAfterAlert = false

    private var selectedSubjectLayers: [SelectedSubjectLayer] { selectedSubjects }

    private var backSubjectLayers: [SelectedSubjectLayer] {
        selectedSubjectLayers.filter(\.isBehindOverlay)
    }

    private var frontSubjectLayers: [SelectedSubjectLayer] {
        selectedSubjectLayers.filter { !$0.isBehindOverlay }
    }

    private var hasSelectedSubjects: Bool { !selectedSubjects.isEmpty }
    private var shouldShowGuidanceScan: Bool { !subjects.isEmpty && selectedSubjects.isEmpty && editSegment == .subject }
    private var subjectGlowColor: Color { RunningLevelManager.shared.accentColor }

    /// solidTone: -1(흰) ~ 0(투명) ~ +1(검정)
    private var solidColor: Color {
        let maxAlpha = bgStyle == .glass ? 0.85 : 1.0
        let alpha = abs(solidTone) * maxAlpha
        return (solidTone < 0 ? Color.white : Color.black).opacity(alpha)
    }

    private var solidToneLabel: String {
        if abs(solidTone) < 0.01 { return "투명" }
        let pct = Int(abs(solidTone) * 100)
        return solidTone < 0 ? "흰색 \(pct)%" : "검정 \(pct)%"
    }

    /// 배경 톤에 따른 텍스트 색상
    private var overlayText: Color {
        if solidTone < -0.3 {
            return .black
        } else if solidTone < 0 {
            let t = Double(-solidTone) / 0.3
            return Color(white: 1 - t)
        } else {
            return .white
        }
    }

    private var overlaySubText: Color {
        overlayText.opacity(0.5)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let photo {
                    cardEditor(photo: photo)
                } else {
                    photoPicker
                }
            }
            .background(AppColor.backgroundTertiary)
            .navigationTitle("공유 카드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if photo != nil {
                        Button("취소") {
                            withAnimation {
                                resetState()
                            }
                        }
                        .disabled(isExtracting)
                    } else {
                        Button("닫기") { dismiss() }
                    }
                }
                if photo != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let photo { saveToPhotos(photo: photo) }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(isSaving || isExtracting)
                    }
                }
            }
            .alert(
                saveResult?.title ?? "",
                isPresented: .init(
                    get: { saveResult != nil },
                    set: { if !$0 {
                        let success = shouldDismissAfterAlert
                        saveResult = nil
                        shouldDismissAfterAlert = false
                        if success {
                            dismiss()
                        }
                    } }
                )
            ) {
                Button("확인") { }
            } message: {
                Text(saveResult?.message ?? "")
            }
        }
    }

    // MARK: - Photo Picker

    private var photoPicker: some View {
        PhotoGridPicker { image, assets, index in
            photoAssets = assets
            currentAssetIndex = index
            handlePhoto(image)
        }
    }

    // MARK: - Card Editor

    private func cardEditor(photo: UIImage) -> some View {
        GeometryReader { geo in
            let cardW = geo.size.width - 40
            let cardH = cardW * 4 / 3
            VStack(spacing: 8) {
                editSegmentPicker
                cardPreviewStack(photo: photo, cardWidth: cardW, cardHeight: cardH)
                editSegmentControls
                Spacer(minLength: 0)
                if !photoAssets.isEmpty { photoStrip }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var editSegmentPicker: some View {
        Picker("편집 대상", selection: $editSegment) {
            ForEach(subjects.isEmpty ? [.bg, .chart] : EditSegment.allCases, id: \.self) { seg in
                Text(seg.rawValue).tag(seg)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: subjects) { _, newSubjects in
            if newSubjects.isEmpty && editSegment == .subject {
                editSegment = .chart
            }
        }
    }

    @ViewBuilder
    private func cardPreviewStack(photo: UIImage, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ZStack {
            cardPreview(photo: photo, cardWidth: cardWidth, cardHeight: cardHeight)
            if isExtracting {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                            .scaleEffect(1.2)
                        Text("로딩 중...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExtracting)
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private var editSegmentControls: some View {
        if editSegment == .subject {
            PhotoFilterPicker(
                filters: PhotoFilterKind.allPhotoFilters,
                source: subjects.first?.image ?? photo,
                selection: $subjectFilter
            )
            .onChange(of: subjectFilter) { _, newVal in
                handleSubjectFilterChange(newVal)
            }
        } else if editSegment == .bg {
            PhotoFilterPicker(
                filters: PhotoFilterKind.allPhotoFilters,
                source: photo,
                selection: $bgFilter
            )
            .onChange(of: bgFilter) { _, newVal in
                handleBgFilterChange(newVal)
                subjectFilter = newVal
            }
        } else {
            VStack(spacing: 6) {
                Picker("배경", selection: $bgStyle) {
                    ForEach(OverlayBgStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    Slider(value: $solidTone, in: -1...1, step: 0.01)
                        .tint(.primary)
                    Circle()
                        .fill(.black)
                        .frame(width: 10, height: 10)
                    Text(solidToneLabel)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .leading)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bgStyle)
        }
    }

    // MARK: - Photo Strip (하단 썸네일)

    private var stripRange: [Int] {
        guard currentAssetIndex >= 0 else { return [] }
        let lo = max(0, currentAssetIndex - 3)
        let hi = min(photoAssets.count - 1, currentAssetIndex + 3)
        return Array(lo...hi)
    }

    private var photoStrip: some View {
        HStack(spacing: 4) {
            ForEach(stripRange, id: \.self) { idx in
                let isCurrent = idx == currentAssetIndex
                ZStack {
                    Color(AppColor.UI.systemGray5)
                    if let thumb = adjacentThumbs[idx] {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                )
                .opacity(isCurrent ? 1.0 : 0.6)
                .scaleEffect(isCurrent ? 1.0 : 0.9)
                .onTapGesture { loadPhotoAtIndex(idx) }
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if dragBaseIndex < 0 { dragBaseIndex = currentAssetIndex }
                    let step: CGFloat = 48
                    let delta = Int(round(-value.translation.width / step))
                    let target = max(0, min(photoAssets.count - 1, dragBaseIndex + delta))
                    if target != currentAssetIndex {
                        scrubToIndex(target)
                    }
                }
                .onEnded { _ in
                    dragBaseIndex = -1
                    finishScrub()
                }
        )
    }

    // MARK: - Photo Navigation

    /// 드래그 중 경량 로드 — 인덱스 즉시 반영, 빠른 해상도로 사진만 교체
    private func scrubToIndex(_ index: Int) {
        guard index >= 0, index < photoAssets.count, index != currentAssetIndex else { return }
        currentAssetIndex = index
        clearSelectedSubjects()
        glassPhoto = nil
        pixelatedBgPhoto = nil
        pixelatedSubjectPhotos = [:]
        filteredBgPhotos = [:]
        filteredSubjectPhotos = [:]
        prefetchStripThumbs()

        let asset = photoAssets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let targetIndex = index
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 900, height: 1200),
            contentMode: .aspectFit, options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                guard self.currentAssetIndex == targetIndex else { return }
                self.photo = image
            }
        }
    }

    /// 드래그 종료 — 고해상도 + 피사체 추출
    private func finishScrub() {
        let index = currentAssetIndex
        guard index >= 0, index < photoAssets.count, let currentPhoto = photo else { return }

        isExtracting = true
        let asset = photoAssets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit, options: options
        ) { image, _ in
            let fullImage = image ?? currentPhoto
            DispatchQueue.main.async {
                guard self.currentAssetIndex == index, self.photo != nil else { return }
                self.photo = fullImage
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let extractedSubjects = ShareCardService.shared.extractSubjects(from: fullImage)
                let glass = ShareCardService.shared.applyGlassDistortion(to: fullImage)
                DispatchQueue.main.async {
                    guard self.currentAssetIndex == index, self.photo != nil else { return }
                    self.subjects = extractedSubjects
                    if !extractedSubjects.isEmpty { self.editSegment = .subject }
                    self.clearSelectedSubjects()
                    self.pixelatedSubjectPhotos = [:]
                    self.filteredSubjectPhotos = [:]
                    self.glassPhoto = glass
                    self.isExtracting = false
                }
            }
        }
    }

    private func loadPhotoAtIndex(_ index: Int) {
        guard index >= 0, index < photoAssets.count, index != currentAssetIndex else { return }

        let asset = photoAssets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        isExtracting = true
        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit, options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                guard self.photo != nil else { return }
                currentAssetIndex = index
                photo = image
                clearSelectedSubjects()
                glassPhoto = nil
                pixelatedBgPhoto = nil
                pixelatedSubjectPhotos = [:]
                prefetchStripThumbs()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let extractedSubjects = ShareCardService.shared.extractSubjects(from: image)
                let glass = ShareCardService.shared.applyGlassDistortion(to: image)
                DispatchQueue.main.async {
                    guard self.currentAssetIndex == index, self.photo != nil else { return }
                    subjects = extractedSubjects
                    if !extractedSubjects.isEmpty { editSegment = .subject }
                    clearSelectedSubjects()
                    glassPhoto = glass
                    isExtracting = false
                }
            }
        }
    }

    private func prefetchStripThumbs() {
        guard currentAssetIndex >= 0 else { return }
        let lo = max(0, currentAssetIndex - 3)
        let hi = min(photoAssets.count - 1, currentAssetIndex + 3)
        let scale = UIScreen.main.scale
        let size = CGSize(width: 44 * scale, height: 44 * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        for idx in lo...hi {
            if adjacentThumbs[idx] != nil { continue }
            let asset = photoAssets[idx]
            PHImageManager.default().requestImage(
                for: asset, targetSize: size,
                contentMode: .aspectFill, options: options
            ) { image, _ in
                if let image {
                    DispatchQueue.main.async { adjacentThumbs[idx] = image }
                }
            }
        }
    }

    // MARK: - Card Preview (interactive)

    private func cardPreview(photo: UIImage, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let displayBg = bgDisplayImage(photo: photo)
        return ZStack {
            // 배경 사진
            Image(uiImage: displayBg)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight).clipped()
                .saturation(bgFilter == .mono ? 0 : 1)
                .colorInvertIf(bgFilter == .invert)

            if !backSubjectLayers.isEmpty {
                subjectLayersView(backSubjectLayers, cardWidth: cardWidth, cardHeight: cardHeight)
            }

            if shouldShowGuidanceScan {
                guidanceLayersView(cardWidth: cardWidth, cardHeight: cardHeight)
            }

            if !backSubjectLayers.isEmpty {
                chartOverlay(photo: photo, cardHeight: cardHeight)
            }

            if backSubjectLayers.isEmpty {
                chartOverlay(photo: photo, cardHeight: cardHeight)
            }

            if !frontSubjectLayers.isEmpty {
                subjectLayersView(frontSubjectLayers, cardWidth: cardWidth, cardHeight: cardHeight)
                subjectDismissInteractionLayers(
                    frontSubjectLayers,
                    photo: photo,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight
                )
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .center) {
            if !subjects.isEmpty && !hasSelectedSubjects && editSegment == .subject {
                Text("피사체를 길게 눌러 선택")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .simultaneousGesture(
            subjectSelectionTrackingGesture(photo: photo, cardSize: CGSize(width: cardWidth, height: cardHeight)),
            isEnabled: editSegment == .subject
        )
        .onAppear { startGuidanceScanIfNeeded() }
        .onChange(of: shouldShowGuidanceScan) { _, shouldShow in
            if shouldShow {
                startGuidanceScanIfNeeded()
            } else {
                guidanceScanProgress = 0
            }
        }
    }

    // MARK: - Chart Overlay

    @ViewBuilder
    private func glassRefraction(photo: UIImage, tint: Color, offset: CGSize, scale: CGFloat, cardHeight: CGFloat) -> some View {
        ZStack {
            // backdrop blur — 뒤 사진 투과
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)

            // 색상 틴트 (최대 불투명도가 제한된 tint 사용)
            RoundedRectangle(cornerRadius: 12)
                .fill(tint)

            // 상단 스페큘러 (틴트 위에 배치하여 글래스 질감 유지)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.white.opacity(0.15), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func chartOverlay(photo: UIImage, cardHeight: CGFloat) -> some View {
        chartContent()
            .saturation(chartFilter == .mono ? 0 : 1)
            .environment(\.overlayTextColor, overlayText)
            .environment(\.overlaySubTextColor, overlaySubText)
            .padding(12)
            .background {
                switch bgStyle {
                case .solid:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(solidColor)
                case .glass:
                    glassRefraction(photo: photo, tint: solidColor, offset: overlayOffset, scale: overlayScale, cardHeight: cardHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(
                color: bgStyle == .glass ? .black.opacity(0.2) : .clear,
                radius: 8, x: 0, y: 4
            )
            .scaleEffect(overlayScale)
            .offset(overlayOffset)
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        overlayOffset = CGSize(
                            width: dragAccumulated.width + value.translation.width,
                            height: dragAccumulated.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragAccumulated = overlayOffset }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        overlayScale = scaleAccumulated * value.magnification
                    }
                    .onEnded { _ in
                        scaleAccumulated = overlayScale
                    }
            )
    }

    // MARK: - Render Content (for ImageRenderer, solid bg instead of material)

    private func renderContent(photo: UIImage) -> some View {
        let cardW = UIScreen.main.bounds.width - 40
        let cardH = cardW * 4 / 3
        let bg: AnyView = {
            switch bgStyle {
            case .solid:
                return AnyView(RoundedRectangle(cornerRadius: 12).fill(solidColor))
            case .glass:
                return AnyView(glassRefraction(photo: photo, tint: solidColor, offset: overlayOffset, scale: overlayScale, cardHeight: cardH))
            }
        }()

        let overlayView = chartContent()
            .saturation(chartFilter == .mono ? 0 : 1)
            .environment(\.overlayTextColor, overlayText)
            .environment(\.overlaySubTextColor, overlaySubText)
            .padding(12)
            .background { bg }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(overlayScale)
            .offset(overlayOffset)

        let displayBg = bgDisplayImage(photo: photo)
        return ZStack {
            Image(uiImage: displayBg)
                .resizable().scaledToFill()
                .frame(width: cardW, height: cardH).clipped()
                .saturation(bgFilter == .mono ? 0 : 1)
                .colorInvertIf(bgFilter == .invert)

            ForEach(backSubjectLayers) { layer in
                if let subject = subject(for: layer.id) {
                    subjectImageView(
                        subject,
                        layer: layer,
                        cardWidth: cardW,
                        cardHeight: cardH,
                        showsScan: false,
                        showsInteractionEffect: false
                    )
                }
            }

            overlayView

            ForEach(frontSubjectLayers) { layer in
                if let subject = subject(for: layer.id) {
                    subjectImageView(
                        subject,
                        layer: layer,
                        cardWidth: cardW,
                        cardHeight: cardH,
                        showsScan: false,
                        showsInteractionEffect: false
                    )
                }
            }
        }
        .frame(width: cardW, height: cardH)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Subject Helpers

    @ViewBuilder
    private func subjectLayersView(_ layers: [SelectedSubjectLayer], cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ForEach(layers) { layer in
            if let subject = subject(for: layer.id) {
                subjectImageView(
                    subject,
                    layer: layer,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    showsScan: layer.scanProgress > 0,
                    showsInteractionEffect: layer.isLifted || layer.scanProgress > 0
                )
            }
        }
    }

    @ViewBuilder
    private func guidanceLayersView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ForEach(subjects) { subject in
            let displayImg = subjectDisplayImage(subject)
            Image(uiImage: displayImg)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .saturation(subjectFilter == .mono ? 0 : 1)
                .colorInvertIf(subjectFilter == .invert)
                .overlay {
                    subjectGlowOverlay(
                        image: subject.image,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        intensity: guidanceScanProgress
                    )
                }
                .opacity(0.92)
                .allowsHitTesting(false)
        }
    }

    private func subjectImageView(
        _ subject: ExtractedSubject,
        layer: SelectedSubjectLayer,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        showsScan: Bool,
        showsInteractionEffect: Bool
    ) -> some View {
        let displayImg = subjectDisplayImage(subject)
        return ZStack {
            Image(uiImage: displayImg)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .saturation(subjectFilter == .mono ? 0 : 1)
                .colorInvertIf(subjectFilter == .invert)

            if showsScan {
                subjectGlowOverlay(
                    image: subject.image,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    intensity: layer.scanProgress
                )
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(showsInteractionEffect && layer.isLifted ? 1.05 : 1.0)
        .shadow(
            color: .black.opacity(showsInteractionEffect && layer.isLifted ? 0.5 : 0),
            radius: showsInteractionEffect && layer.isLifted ? 20 : 0,
            y: showsInteractionEffect && layer.isLifted ? 10 : 0
        )
        .overlay {
            if showsInteractionEffect {
                Image(uiImage: subject.image)
                    .resizable().scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay(Color.white.opacity(0.18))
                    .mask(
                        Image(uiImage: subject.image)
                            .resizable().scaledToFill()
                            .frame(width: cardWidth, height: cardHeight)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func subjectGlowOverlay(image: UIImage, cardWidth: CGFloat, cardHeight: CGFloat, intensity: CGFloat) -> some View {
        let baseOpacity = 0.25 + 0.35 * intensity
        return ZStack {
            ForEach([20.0, 12.0, 6.0], id: \.self) { radius in
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .colorMultiply(subjectGlowColor)
                    .blur(radius: radius)
                    .opacity(baseOpacity * (radius == 20.0 ? 0.35 : radius == 12.0 ? 0.5 : 0.75))
            }

            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .colorMultiply(subjectGlowColor)
                .blur(radius: 1.8)
                .opacity(0.28 + 0.22 * intensity)
        }
        .blendMode(.screen)
    }

    @ViewBuilder
    private func subjectDismissInteractionLayers(
        _ layers: [SelectedSubjectLayer],
        photo: UIImage,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> some View {
        let cardSize = CGSize(width: cardWidth, height: cardHeight)
        ForEach(layers) { layer in
            if let subject = subject(for: layer.id),
               let frame = subjectFrame(for: subject, photo: photo, cardSize: cardSize) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: subjectDragDismissThreshold)
                            .onChanged { value in
                                handleSelectedSubjectDismissDrag(
                                    subjectID: layer.id,
                                    localStart: value.startLocation,
                                    frame: frame,
                                    photo: photo,
                                    cardSize: cardSize
                                )
                            }
                            .onEnded { _ in
                                if activeDismissSubjectID == layer.id {
                                    activeDismissSubjectID = nil
                                }
                            }
                    )
            }
        }
    }

    private func clearSelectedSubjects() {
        selectedSubjects = []
        guidanceScanProgress = 0
        activeDismissSubjectID = nil
        cancelSubjectTracking()
    }

    private func subject(for id: ExtractedSubject.ID) -> ExtractedSubject? {
        subjects.first(where: { $0.id == id })
    }

    private func isSubjectSelected(_ id: ExtractedSubject.ID) -> Bool {
        selectedSubjects.contains(where: { $0.id == id })
    }

    private func normalizedTopRatio(for subject: ExtractedSubject) -> CGFloat {
        guard let photo, let cgImage = photo.cgImage, cgImage.height > 0 else { return 0 }
        return max(0, min(1, subject.boundingBox.minY / CGFloat(cgImage.height)))
    }

    private func normalizedBottomRatio(for subject: ExtractedSubject) -> CGFloat {
        guard let photo, let cgImage = photo.cgImage, cgImage.height > 0 else { return 1 }
        return max(0, min(1, subject.boundingBox.maxY / CGFloat(cgImage.height)))
    }

    private func makeLayer(for subject: ExtractedSubject) -> SelectedSubjectLayer {
        SelectedSubjectLayer(
            id: subject.id,
            isBehindOverlay: false,
            topRatio: normalizedTopRatio(for: subject),
            bottomRatio: normalizedBottomRatio(for: subject)
        )
    }

    private func deselectSubject(_ id: ExtractedSubject.ID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSubjects.removeAll(where: { $0.id == id })
        }
    }

    private func selectSubject(_ subject: ExtractedSubject) {
        guard !isSubjectSelected(subject.id) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSubjects.append(makeLayer(for: subject))
        }
    }

    private func toggleSubjectSelection(_ id: ExtractedSubject.ID) {
        if isSubjectSelected(id) {
            deselectSubject(id)
        } else if let subject = subject(for: id) {
            selectSubject(subject)
        }
    }

    private func setLifted(_ isLifted: Bool, for id: ExtractedSubject.ID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            if let index = selectedSubjects.firstIndex(where: { $0.id == id }) {
                selectedSubjects[index].isLifted = isLifted
            }
        }
    }

    private func setScanProgress(_ progress: CGFloat, for id: ExtractedSubject.ID) {
        if let index = selectedSubjects.firstIndex(where: { $0.id == id }) {
            selectedSubjects[index].scanProgress = progress
        }
    }

    private func subjectSelectionTrackingGesture(photo: UIImage, cardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchSubjectID == nil {
                    touchSubjectID = hitTestSubjectID(at: value.startLocation, photo: photo, cardSize: cardSize)
                    didHandleTouchAsSubject = false

                    guard let touchSubjectID else { return }

                    let work = DispatchWorkItem {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        toggleSubjectSelection(touchSubjectID)
                        didHandleTouchAsSubject = true
                    }
                    longPressTimer = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                }

                guard touchSubjectID != nil else { return }
                let moved = hypot(value.translation.width, value.translation.height) >= subjectLongPressMovementThreshold
                if moved, !didHandleTouchAsSubject {
                    cancelSubjectTracking()
                }
            }
            .onEnded { _ in
                cancelSubjectTracking()
            }
    }

    private func hitTestSubjectID(at point: CGPoint, photo: UIImage, cardSize: CGSize) -> ExtractedSubject.ID? {
        guard let imagePoint = imagePoint(from: point, photo: photo, cardSize: cardSize) else { return nil }

        let matchingSubjects = subjects
            .filter { $0.boundingBox.contains(imagePoint) && $0.contains(imagePoint) }
            .sorted {
                return $0.area < $1.area
            }

        return matchingSubjects.first?.id
    }

    private func handleSelectedSubjectDismissDrag(
        subjectID: ExtractedSubject.ID,
        localStart: CGPoint,
        frame: CGRect,
        photo: UIImage,
        cardSize: CGSize
    ) {
        guard activeDismissSubjectID != subjectID else { return }

        let cardPoint = CGPoint(x: frame.minX + localStart.x, y: frame.minY + localStart.y)
        guard subjectContains(subjectID, at: cardPoint, photo: photo, cardSize: cardSize) else { return }

        activeDismissSubjectID = subjectID
        cancelSubjectTracking()
        deselectSubject(subjectID)
    }

    private func subjectContains(
        _ subjectID: ExtractedSubject.ID,
        at point: CGPoint,
        photo: UIImage,
        cardSize: CGSize
    ) -> Bool {
        guard let subject = subject(for: subjectID),
              let imagePoint = imagePoint(from: point, photo: photo, cardSize: cardSize) else {
            return false
        }

        return subject.boundingBox.contains(imagePoint) && subject.contains(imagePoint)
    }

    private func startGuidanceScanIfNeeded() {
        guard shouldShowGuidanceScan else { return }
        guidanceScanProgress = 0
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            guidanceScanProgress = 1
        }
    }

    private func imagePoint(from point: CGPoint, photo: UIImage, cardSize: CGSize) -> CGPoint? {
        guard let geometry = imageDisplayGeometry(for: photo, cardSize: cardSize) else {
            return nil
        }

        let normalizedX = (point.x - geometry.origin.x) / geometry.scale
        let normalizedY = (point.y - geometry.origin.y) / geometry.scale
        guard normalizedX >= 0,
              normalizedY >= 0,
              normalizedX < geometry.imageSize.width,
              normalizedY < geometry.imageSize.height else {
            return nil
        }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private func subjectFrame(for subject: ExtractedSubject, photo: UIImage, cardSize: CGSize) -> CGRect? {
        guard let geometry = imageDisplayGeometry(for: photo, cardSize: cardSize) else { return nil }
        return CGRect(
            x: geometry.origin.x + subject.boundingBox.minX * geometry.scale,
            y: geometry.origin.y + subject.boundingBox.minY * geometry.scale,
            width: subject.boundingBox.width * geometry.scale,
            height: subject.boundingBox.height * geometry.scale
        )
    }

    private func imageDisplayGeometry(for photo: UIImage, cardSize: CGSize) -> (imageSize: CGSize, scale: CGFloat, origin: CGPoint)? {
        guard let cgImage = photo.cgImage else { return nil }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard imageSize.width > 0, imageSize.height > 0, cardSize.width > 0, cardSize.height > 0 else {
            return nil
        }

        let scale = max(cardSize.width / imageSize.width, cardSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (cardSize.width - displayedSize.width) / 2,
            y: (cardSize.height - displayedSize.height) / 2
        )
        return (imageSize, scale, origin)
    }

    private func cancelSubjectTracking() {
        longPressTimer?.cancel()
        longPressTimer = nil

        if let touchSubjectID {
            setLifted(false, for: touchSubjectID)
            setScanProgress(0, for: touchSubjectID)
        }

        touchSubjectID = nil
        didHandleTouchAsSubject = false
    }

    // MARK: - Filter helpers

    /// Returns the image to display for the background, accounting for the current bgFilter.
    private func bgDisplayImage(photo: UIImage) -> UIImage {
        switch bgFilter {
        case .original, .mono, .invert:
            return photo
        case .pixel:
            return pixelatedBgPhoto ?? photo
        case .film:
            return filteredBgPhotos[bgFilter.cacheKey] ?? photo
        }
    }

    /// Returns the image to display for a subject, accounting for the current subjectFilter.
    private func subjectDisplayImage(_ subject: ExtractedSubject) -> UIImage {
        switch subjectFilter {
        case .original, .mono, .invert:
            return subject.image
        case .pixel:
            return pixelatedSubjectPhotos[subject.id] ?? subject.image
        case .film:
            let key = "\(subject.id)_\(subjectFilter.cacheKey)"
            return filteredSubjectPhotos[key] ?? subject.image
        }
    }

    private func handleBgFilterChange(_ newVal: PhotoFilterKind) {
        switch newVal {
        case .original, .mono, .invert:
            break
        case .pixel:
            pixelateBg()
        case .film:
            bakeBgFilter(newVal)
        }
    }

    private func handleSubjectFilterChange(_ newVal: PhotoFilterKind) {
        switch newVal {
        case .original, .mono, .invert:
            break
        case .pixel:
            pixelateSubjects()
        case .film:
            bakeSubjectFilter(newVal)
        }
    }

    private func pixelateBg() {
        guard let photo else { return }
        if pixelatedBgPhoto != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ShareCardService.shared.pixelate(photo)
            DispatchQueue.main.async { pixelatedBgPhoto = result }
        }
    }

    private func pixelateSubjects() {
        for subject in subjects {
            if pixelatedSubjectPhotos[subject.id] != nil { continue }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ShareCardService.shared.pixelate(subject.image)
                DispatchQueue.main.async {
                    if let result { pixelatedSubjectPhotos[subject.id] = result }
                }
            }
        }
    }

    private func bakeBgFilter(_ filter: PhotoFilterKind) {
        guard case .film = filter, let photo else { return }
        let key = filter.cacheKey
        if filteredBgPhotos[key] != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FilmFilterEngine.shared.applySimple(kind: filter, to: photo)
            DispatchQueue.main.async {
                if let result, self.bgFilter.cacheKey == key {
                    filteredBgPhotos[key] = result
                }
            }
        }
    }

    private func bakeSubjectFilter(_ filter: PhotoFilterKind) {
        guard case .film = filter else { return }
        let key = filter.cacheKey
        for subject in subjects {
            let subjectKey = "\(subject.id)_\(key)"
            if filteredSubjectPhotos[subjectKey] != nil { continue }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FilmFilterEngine.shared.applySimple(kind: filter, to: subject.image)
                DispatchQueue.main.async {
                    if let result, self.subjectFilter.cacheKey == key {
                        filteredSubjectPhotos[subjectKey] = result
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handlePhoto(_ uiImage: UIImage) {
        photo = uiImage
        pixelatedBgPhoto = nil
        pixelatedSubjectPhotos = [:]
        filteredBgPhotos = [:]
        filteredSubjectPhotos = [:]
        isExtracting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let extractedSubjects = ShareCardService.shared.extractSubjects(from: uiImage)
            let glass = ShareCardService.shared.applyGlassDistortion(to: uiImage)
            DispatchQueue.main.async {
                guard self.photo === uiImage else { return }
                subjects = extractedSubjects
                if !extractedSubjects.isEmpty { editSegment = .subject }
                clearSelectedSubjects()
                glassPhoto = glass
                isExtracting = false
            }
        }
        prefetchStripThumbs()
    }

    private func resetState() {
        photo = nil
        glassPhoto = nil
        subjects = []
        clearSelectedSubjects()
        overlayOffset = .zero
        dragAccumulated = .zero
        overlayScale = 0.8
        scaleAccumulated = 0.8
        solidTone = 0.0
        bgStyle = .solid
        editSegment = .chart
        subjectFilter = .original
        chartFilter = .original
        bgFilter = .original
        pixelatedBgPhoto = nil
        pixelatedSubjectPhotos = [:]
        filteredBgPhotos = [:]
        filteredSubjectPhotos = [:]
        shouldDismissAfterAlert = false
        currentAssetIndex = -1
        adjacentThumbs = [:]
    }

    @MainActor
    private func saveToPhotos(photo: UIImage) {
        isSaving = true
        let content = renderContent(photo: photo)
        guard let image = ShareCardService.shared.renderSwiftUIView(content) else {
            saveResult = .failure("이미지 렌더링에 실패했습니다.")
            isSaving = false
            return
        }
        ShareCardService.shared.saveToPhotos(image) { success in
            DispatchQueue.main.async {
                if success {
                    saveResult = .success
                    shouldDismissAfterAlert = true
                } else {
                    saveResult = .failure("사진첩 저장에 실패했습니다.")
                    shouldDismissAfterAlert = false
                }
                isSaving = false
            }
        }
    }
}

// MARK: - Photo Grid Picker

struct PhotoGridPicker: View {
    let onSelect: (UIImage, [PHAsset], Int) -> Void

    @StateObject private var loader = PhotoGridLoader()
    @State private var showCamera = false
    @State private var isLoading = false
    @State private var filter: PhotoGridFilter = .all

    private let spacing: CGFloat = 1.5
    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 1.5), count: 3
    )

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Picker("사진 필터", selection: $filter) {
                    ForEach(PhotoGridFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if loader.assets.isEmpty, filter == .favorites {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("즐겨찾기 사진이 없습니다")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("전체 보기로 전환하거나 사진 앱에서 즐겨찾기를 추가해보세요.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            // 카메라 실시간 프리뷰 타일
                            Button {
                                showCamera = true
                            } label: {
                                GeometryReader { geo in
                                    ZStack {
                                        CameraPreviewTile()
                                            .frame(width: geo.size.width, height: geo.size.width)

                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Image(systemName: "camera.fill")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(.black.opacity(0.5), in: Circle())
                                                    .padding(6)
                                            }
                                        }
                                    }
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }

                            // 사진 타일
                            ForEach(Array(loader.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                PhotoThumbnail(asset: asset, isLoading: $isLoading) { image in
                                    onSelect(image, loader.assets, index)
                                }
                            }
                        }
                    }
                }
            }

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .onAppear { loader.fetchRecent(filter: filter) }
        .onChange(of: filter) { _, newValue in
            loader.fetchRecent(filter: newValue)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                onSelect(image, [], -1)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Photo Grid Loader

final class PhotoGridLoader: ObservableObject {
    @Published var assets: [PHAsset] = []

    fileprivate func fetchRecent(filter: PhotoGridFilter) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            loadAssets(filter: filter)
        } else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    DispatchQueue.main.async { self?.loadAssets(filter: filter) }
                }
            }
        }
    }

    private func loadAssets(filter: PhotoGridFilter) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if filter == .favorites {
            options.predicate = NSPredicate(format: "favorite == YES")
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var fetched: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                fetched.append(asset)
            }
            DispatchQueue.main.async {
                self.assets = fetched
            }
        }
    }
}

fileprivate enum PhotoGridFilter: CaseIterable {
    case all
    case favorites

    var title: String {
        switch self {
        case .all: return "전체"
        case .favorites: return "즐겨찾기"
        }
    }
}

// MARK: - Photo Thumbnail

struct PhotoThumbnail: View {
    let asset: PHAsset
    @Binding var isLoading: Bool
    let onSelect: (UIImage) -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            loadFullImage()
        } label: {
            GeometryReader { geo in
                ZStack {
                    Color(AppColor.UI.systemGray6)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipped()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .contentShape(Rectangle())
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let scale = UIScreen.main.scale
        let size = CGSize(width: 150 * scale, height: 150 * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset, targetSize: size,
            contentMode: .aspectFill, options: options
        ) { image, _ in
            DispatchQueue.main.async { thumbnail = image }
        }
    }

    private func loadFullImage() {
        isLoading = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit, options: options
        ) { image, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let image { onSelect(image) }
            }
        }
    }
}

// MARK: - Camera Preview Tile

struct CameraPreviewTile: UIViewRepresentable {

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class CameraPreviewUIView: UIView {

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppColor.UI.systemGray5
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        setupSession()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.sessionPreset = .low
        if session.canAddInput(input) {
            session.addInput(input)
        }
        previewLayer.session = session

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
