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

    @ViewBuilder let chartContent: () -> ChartContent

    @Environment(\.dismiss) private var dismiss

    // Photo
    @State private var photo: UIImage?
    @State private var glassPhoto: UIImage?
    @State private var subjectImage: UIImage?
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
    @State private var behindSubject = false
    @State private var subjectLifted = false
    @State private var subjectScanProgress: CGFloat = 0  // 0→1 빛 스캔 진행도
    @State private var subjectTopRatio: CGFloat = 0     // 피사체 상단 위치 (0~1)
    @State private var subjectBottomRatio: CGFloat = 1  // 피사체 하단 위치 (0~1)
    @State private var longPressTimer: DispatchWorkItem?

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

    private var hasSubject: Bool { subjectImage != nil }

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

                if hasSubject {
                    Text("길게 눌러 피사체 앞/뒤 전환")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                } else {
                    Text("")
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
        subjectImage = nil
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
                let subject = ShareCardService.shared.extractSubject(from: fullImage)
                let glass = ShareCardService.shared.applyGlassDistortion(to: fullImage)
                DispatchQueue.main.async {
                    guard self.currentAssetIndex == index, self.photo != nil else { return }
                    self.subjectImage = subject
                    self.glassPhoto = glass
                    self.isExtracting = false
                    if let subject { self.updateSubjectBounds(subject) }
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
                subjectImage = nil
                glassPhoto = nil
                prefetchStripThumbs()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let subject = ShareCardService.shared.extractSubject(from: image)
                let glass = ShareCardService.shared.applyGlassDistortion(to: image)
                DispatchQueue.main.async {
                    guard self.currentAssetIndex == index, self.photo != nil else { return }
                    subjectImage = subject
                    glassPhoto = glass
                    isExtracting = false
                    if let subject { updateSubjectBounds(subject) }
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

            // 차트가 피사체 뒤에 있을 때
            if behindSubject && hasSubject {
                chartOverlay(photo: photo, cardHeight: cardHeight)
            }

            // 피사체 레이어 (터치 통과 — 차트 드래그 방해하지 않음)
            if let subject = subjectImage {
                ZStack {
                    Image(uiImage: subject)
                        .resizable().scaledToFill()
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()

                    // 빛 띠 스캔 — 피사체 상단→하단 훑기
                    if subjectScanProgress > 0 {
                        let bandWidth: CGFloat = 0.12
                        // progress 0→1을 피사체 실제 상하 범위로 매핑
                        let center = subjectTopRatio + subjectScanProgress * (subjectBottomRatio - subjectTopRatio)
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: max(0, center - bandWidth)),
                                .init(color: Color.white.opacity(0.3), location: max(0, center - bandWidth * 0.4)),
                                .init(color: Color.white.opacity(0.7), location: center),
                                .init(color: Color.white.opacity(0.3), location: min(1, center + bandWidth * 0.4)),
                                .init(color: .clear, location: min(1, center + bandWidth))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: cardWidth, height: cardHeight)
                        .blendMode(.softLight)
                        .mask {
                            Image(uiImage: subject)
                                .resizable().scaledToFill()
                                .frame(width: cardWidth, height: cardHeight)
                        }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .scaleEffect(subjectLifted ? 1.05 : 1.0)
                .shadow(
                    color: .black.opacity(subjectLifted ? 0.5 : 0),
                    radius: subjectLifted ? 20 : 0,
                    y: subjectLifted ? 10 : 0
                )
                .allowsHitTesting(false)
            }

            // 차트가 피사체 앞에 있을 때
            if !behindSubject || !hasSubject {
                chartOverlay(photo: photo, cardHeight: cardHeight)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard hasSubject else { return }
                    let moved = abs(value.translation.width) > 5 || abs(value.translation.height) > 5
                    if moved {
                        // 드래그 감지 → 타이머 취소
                        longPressTimer?.cancel()
                        longPressTimer = nil
                        if subjectLifted {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                subjectLifted = false
                                subjectScanProgress = 0
                            }
                        }
                    } else if longPressTimer == nil && !subjectLifted {
                        // 첫 터치 → 타이머 시작
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            subjectLifted = true
                        }
                        subjectScanProgress = 0
                        withAnimation(.easeInOut(duration: 1.2)) {
                            subjectScanProgress = 1
                        }
                        let work = DispatchWorkItem {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                behindSubject.toggle()
                                subjectLifted = false
                                subjectScanProgress = 0
                            }
                        }
                        longPressTimer = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
                    }
                }
                .onEnded { _ in
                    // 손을 떼면 취소
                    longPressTimer?.cancel()
                    longPressTimer = nil
                    if subjectLifted {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            subjectLifted = false
                            subjectScanProgress = 0
                        }
                    }
                }
        )
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

            if behindSubject && hasSubject { overlayView }

            if behindSubject, let subject = subjectImage {
                Image(uiImage: subject)
                    .resizable().scaledToFill()
                    .frame(width: cardW, height: cardH).clipped()
            }

            if !behindSubject || !hasSubject { overlayView }
        }
        .frame(width: cardW, height: cardH)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Subject Bounds

    private func updateSubjectBounds(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let w = cgImage.width, h = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let alphaOffset = cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first ? 0 : bytesPerPixel - 1

        var topRow = h, bottomRow = 0
        for y in 0..<h {
            for x in 0..<w {
                let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + alphaOffset]
                if alpha > 10 {
                    topRow = min(topRow, y)
                    bottomRow = max(bottomRow, y)
                    break
                }
            }
        }
        if topRow <= bottomRow {
            subjectTopRatio = CGFloat(topRow) / CGFloat(h)
            subjectBottomRatio = CGFloat(bottomRow) / CGFloat(h)
        }
    }

    // MARK: - Actions

    private func handlePhoto(_ uiImage: UIImage) {
        photo = uiImage
        isExtracting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let subject = ShareCardService.shared.extractSubject(from: uiImage)
            let glass = ShareCardService.shared.applyGlassDistortion(to: uiImage)
            DispatchQueue.main.async {
                guard self.photo === uiImage else { return }
                subjectImage = subject
                glassPhoto = glass
                isExtracting = false
                if let subject { updateSubjectBounds(subject) }
            }
        }
        prefetchStripThumbs()
    }

    private func resetState() {
        photo = nil
        glassPhoto = nil
        subjectImage = nil
        overlayOffset = .zero
        dragAccumulated = .zero
        overlayScale = 0.8
        scaleAccumulated = 0.8
        solidTone = 0.0
        bgStyle = .solid
        behindSubject = false
        subjectLifted = false
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

    private let spacing: CGFloat = 1.5
    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 1.5), count: 3
    )

    var body: some View {
        ZStack {
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

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .onAppear { loader.fetchRecent() }
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

    func fetchRecent() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            loadAssets()
        } else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    DispatchQueue.main.async { self?.loadAssets() }
                }
            }
        }
    }

    private func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // fetchLimit을 설정하지 않으면 모든 이미지를 가져옵니다.
        
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
