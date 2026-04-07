//
//  ShareCardService.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import SwiftUI
import Vision
import CoreImage.CIFilterBuiltins

struct ExtractedSubject: Identifiable, Equatable {
    let id: Int
    let image: UIImage
    let boundingBox: CGRect
    let area: CGFloat

    func contains(_ point: CGPoint, alphaThreshold: UInt8 = 10) -> Bool {
        guard boundingBox.contains(point),
              let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else { return false }

        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return false }

        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
        let bytesPerRow = cgImage.bytesPerRow
        let alphaOffset = cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first ? 0 : bytesPerPixel - 1
        let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + alphaOffset]
        return alpha > alphaThreshold
    }
}

// MARK: - Share Card Service

final class ShareCardService: NSObject {

    static let shared = ShareCardService()
    private override init() { super.init() }

    private var saveCompletion: ((Bool) -> Void)?

    // MARK: - UIView → UIImage

    func captureView(_ view: UIView) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: - SwiftUI View → UIImage

    @MainActor
    func renderSwiftUIView<V: View>(_ view: V, scale: CGFloat? = nil) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale ?? UIScreen.main.scale
        return renderer.uiImage
    }

    // MARK: - 사진 저장

    func saveToPhotos(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        self.saveCompletion = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        saveCompletion?(error == nil)
        saveCompletion = nil
    }

    // MARK: - 리퀴드 글래스 효과

    func applyGlassDistortion(to image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        // CIBumpDistortion: 미세한 렌즈 굴절
        let bump = CIFilter.bumpDistortion()
        bump.inputImage = ciImage
        bump.center = CGPoint(x: ciImage.extent.midX, y: ciImage.extent.midY)
        bump.radius = Float(min(ciImage.extent.width, ciImage.extent.height)) * 0.6
        bump.scale = 0.1  // 미세한 굴절

        guard let bumped = bump.outputImage else { return nil }

        // 극미세 블러 (유리 산란)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = bumped
        blur.radius = 1.5

        guard let output = blur.outputImage,
              let cgOutput = context.createCGImage(output, from: ciImage.extent)
        else { return nil }

        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - 피사체 추출

    func extractSubjects(from photo: UIImage) -> [ExtractedSubject] {
        guard let cgImage = photo.cgImage else { return [] }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return [] }

            let originalCI = CIImage(cgImage: cgImage)
            let ciContext = CIContext()
            let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)

            return result.allInstances.compactMap { instance in
                do {
                    let instanceID = Int(instance)
                    let maskPixelBuffer = try result.generateScaledMaskForImage(
                        forInstances: IndexSet(integer: instanceID),
                        from: handler
                    )
                    let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)

                    let blendFilter = CIFilter.blendWithMask()
                    blendFilter.inputImage = originalCI
                    blendFilter.backgroundImage = CIImage.empty()
                    blendFilter.maskImage = maskCI

                    guard let outputCI = blendFilter.outputImage,
                          let outputCG = ciContext.createCGImage(outputCI, from: originalCI.extent)
                    else { return nil }

                    let subjectImage = UIImage(cgImage: outputCG, scale: photo.scale, orientation: photo.imageOrientation)
                    guard let boundingBox = self.alphaBoundingBox(in: outputCG), !boundingBox.isEmpty else { return nil }

                    let clippedBox = boundingBox.intersection(imageRect)
                    guard !clippedBox.isEmpty else { return nil }

                    return ExtractedSubject(
                        id: instanceID,
                        image: subjectImage,
                        boundingBox: clippedBox,
                        area: clippedBox.width * clippedBox.height
                    )
                } catch {
                    return nil
                }
            }
        } catch {
            return []
        }
    }

    func extractSubject(from photo: UIImage) -> UIImage? {
        extractSubjects(from: photo).first?.image
    }

    private func alphaBoundingBox(in cgImage: CGImage, alphaThreshold: UInt8 = 10) -> CGRect? {
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
        let bytesPerRow = cgImage.bytesPerRow
        let alphaOffset = cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first ? 0 : bytesPerPixel - 1

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + alphaOffset]
                guard alpha > alphaThreshold else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

}

// MARK: - Save Result

enum ShareSaveResult {
    case success
    case failure(String)

    var title: String {
        switch self {
        case .success: return "저장 완료"
        case .failure: return "저장 실패"
        }
    }

    var message: String {
        switch self {
        case .success: return "사진첩에 저장되었습니다."
        case .failure(let msg): return msg
        }
    }
}
