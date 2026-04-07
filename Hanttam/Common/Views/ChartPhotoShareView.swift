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
        var selectionOrder: Int
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
    @State private var longPressTimer: DispatchWorkItem?
    @State private var subjectSelectionCounter = 0
    @State private var guidanceScanProgress: CGFloat = 0
    @State private var touchSubjectID: ExtractedSubject.ID?
    @State private var didHandleTouchAsSubject = false

    private enum OverlayBgStyle: String, CaseIterable {
        case solid = "솔리드"
        case glass = "글래스"
    }

    // Camera
    @State private var showCamera = false

    // Save
    @State private var isSaving = false
    @State private var saveResult: ShareSaveResult?
    @State private var shouldDismissAfterAlert = false

    private var selectedSubjectLayers: [SelectedSubjectLayer] {
        selectedSubjects.sorted { $0.selectionOrder < $1.selectionOrder }
    }

    private var backSubjectLayers: [SelectedSubjectLayer] {
        selectedSubjectLayers.filter(\.isBehindOverlay)
    }

    private var frontSubjectLayers: [SelectedSubjectLayer] {
        selectedSubjectLayers.filter { !$0.isBehindOverlay }
    }

    private var hasSelectedSubjects: Bool { !selectedSubjects.isEmpty }
    private var shouldShowGuidanceScan: Bool { !subjects.isEmpty && selectedSubjects.isEmpty }
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
            VStack(spacing: 12) {
                // 카드 프리뷰
                ZStack {
                    cardPreview(photo: photo, cardWidth: cardW, cardHeight: cardH)

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
                .frame(width: cardW, height: cardH)

                if hasSelectedSubjects {
                    Text("길게 눌러 선택/해제, 탭으로 순서 올리기")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                } else {
                    Text(subjects.isEmpty ? "" : "피사체를 길게 눌러 선택하세요")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                }

                // 배경 스타일
                VStack(spacing: 10) {
                    Picker("배경", selection: $bgStyle) {
                        ForEach(OverlayBgStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 4) {
                        HStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                            Slider(value: $solidTone, in: -1...1, step: 0.01)
                                .tint(.primary)
                            Circle()
                                .fill(.black)
                                .frame(width: 12, height: 12)
                        }
                        Text(solidToneLabel)
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: bgStyle)

                Spacer(minLength: 0)

                // 하단 썸네일 스트립 (현재 기준 좌우 2장)
                if !photoAssets.isEmpty {
                    photoStrip
                }
            }
            .padding(20)
        }
    }

    // MARK: - Photo Strip (하단 썸네일)

    private var stripRange: [Int] {
        guard currentAssetIndex >= 0 else { return [] }
        let lo = max(0, currentAssetIndex - 2)
        let hi = min(photoAssets.count - 1, currentAssetIndex + 2)
        return Array(lo...hi)
    }

    private var photoStrip: some View {
        HStack(spacing: 6) {
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
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
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
                    let step: CGFloat = 58
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
                    self.clearSelectedSubjects()
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
                prefetchStripThumbs()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let extractedSubjects = ShareCardService.shared.extractSubjects(from: image)
                let glass = ShareCardService.shared.applyGlassDistortion(to: image)
                DispatchQueue.main.async {
                    guard self.currentAssetIndex == index, self.photo != nil else { return }
                    subjects = extractedSubjects
                    clearSelectedSubjects()
                    glassPhoto = glass
                    isExtracting = false
                }
            }
        }
    }

    private func prefetchStripThumbs() {
        guard currentAssetIndex >= 0 else { return }
        let lo = max(0, currentAssetIndex - 2)
        let hi = min(photoAssets.count - 1, currentAssetIndex + 2)
        let scale = UIScreen.main.scale
        let size = CGSize(width: 52 * scale, height: 52 * scale)
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
        ZStack {
            // 배경 사진
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight).clipped()

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
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .center) {
            if !subjects.isEmpty && !hasSelectedSubjects {
                Text("피사체를 길게 눌러 선택")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleSubjectTap(at: value.location, photo: photo, cardSize: CGSize(width: cardWidth, height: cardHeight))
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let cardSize = CGSize(width: cardWidth, height: cardHeight)
                    if touchSubjectID == nil {
                        touchSubjectID = hitTestSubjectID(at: value.startLocation, photo: photo, cardSize: cardSize)
                        didHandleTouchAsSubject = false
                    }

                    guard let touchSubjectID else { return }
                    let moved = abs(value.translation.width) > 5 || abs(value.translation.height) > 5
                    if moved, isSubjectSelected(touchSubjectID), !didHandleTouchAsSubject {
                        longPressTimer?.cancel()
                        longPressTimer = nil
                        deselectSubject(touchSubjectID)
                        didHandleTouchAsSubject = true
                    } else if !moved, longPressTimer == nil, !didHandleTouchAsSubject {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if isSubjectSelected(touchSubjectID) {
                            setLifted(true, for: touchSubjectID)
                            setScanProgress(1, for: touchSubjectID)
                        }
                        let work = DispatchWorkItem {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            toggleSubjectSelection(touchSubjectID)
                            didHandleTouchAsSubject = true
                        }
                        longPressTimer = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                    }
                }
                .onEnded { _ in
                    if let touchSubjectID,
                       !didHandleTouchAsSubject,
                       isSubjectSelected(touchSubjectID) {
                        bringSubjectToTop(touchSubjectID)
                    }
                    longPressTimer?.cancel()
                    longPressTimer = nil
                    if let touchSubjectID {
                        setLifted(false, for: touchSubjectID)
                        setScanProgress(0, for: touchSubjectID)
                    }
                    self.touchSubjectID = nil
                    didHandleTouchAsSubject = false
                }
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
            .environment(\.overlayTextColor, overlayText)
            .environment(\.overlaySubTextColor, overlaySubText)
            .padding(12)
            .background { bg }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(overlayScale)
            .offset(overlayOffset)

        return ZStack {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: cardW, height: cardH).clipped()

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
            Image(uiImage: subject.image)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
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
        ZStack {
            Image(uiImage: subject.image)
                .resizable().scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

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

    private func clearSelectedSubjects() {
        selectedSubjects = []
        subjectSelectionCounter = 0
        guidanceScanProgress = 0
        touchSubjectID = nil
        didHandleTouchAsSubject = false
        longPressTimer?.cancel()
        longPressTimer = nil
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
            selectionOrder: nextSelectionOrder(),
            topRatio: normalizedTopRatio(for: subject),
            bottomRatio: normalizedBottomRatio(for: subject)
        )
    }

    private func nextSelectionOrder() -> Int {
        subjectSelectionCounter += 1
        return subjectSelectionCounter
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

    private func bringSubjectToTop(_ id: ExtractedSubject.ID) {
        guard let index = selectedSubjects.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSubjects[index].selectionOrder = nextSelectionOrder()
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

    private func handleSubjectTap(at point: CGPoint, photo: UIImage, cardSize: CGSize) {
        guard let tappedSubjectID = hitTestSubjectID(at: point, photo: photo, cardSize: cardSize),
              isSubjectSelected(tappedSubjectID)
        else { return }
        bringSubjectToTop(tappedSubjectID)
    }

    private func hitTestSubjectID(at point: CGPoint, photo: UIImage, cardSize: CGSize) -> ExtractedSubject.ID? {
        guard let imagePoint = imagePoint(from: point, photo: photo, cardSize: cardSize) else { return nil }

        let selectedOrder = Dictionary(uniqueKeysWithValues: selectedSubjects.map { ($0.id, $0.selectionOrder) })
        let matchingSubjects = subjects
            .filter { $0.boundingBox.contains(imagePoint) && $0.contains(imagePoint) }
            .sorted {
                let lhsOrder = selectedOrder[$0.id] ?? Int.min
                let rhsOrder = selectedOrder[$1.id] ?? Int.min
                if lhsOrder != rhsOrder {
                    return lhsOrder > rhsOrder
                }
                return $0.area < $1.area
            }

        return matchingSubjects.first?.id
    }

    private func startGuidanceScanIfNeeded() {
        guard shouldShowGuidanceScan else { return }
        guidanceScanProgress = 0
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            guidanceScanProgress = 1
        }
    }

    private func imagePoint(from point: CGPoint, photo: UIImage, cardSize: CGSize) -> CGPoint? {
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

        let normalizedX = (point.x - origin.x) / scale
        let normalizedY = (point.y - origin.y) / scale
        guard normalizedX >= 0, normalizedY >= 0, normalizedX < imageSize.width, normalizedY < imageSize.height else {
            return nil
        }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    // MARK: - Actions

    private func handlePhoto(_ uiImage: UIImage) {
        photo = uiImage
        isExtracting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let extractedSubjects = ShareCardService.shared.extractSubjects(from: uiImage)
            let glass = ShareCardService.shared.applyGlassDistortion(to: uiImage)
            DispatchQueue.main.async {
                guard self.photo === uiImage else { return }
                subjects = extractedSubjects
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
