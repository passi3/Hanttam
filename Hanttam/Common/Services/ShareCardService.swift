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

    func extractSubject(from photo: UIImage) -> UIImage? {
        guard let cgImage = photo.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }

            let maskPixelBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            let ciContext = CIContext()
            let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
            let originalCI = CIImage(cgImage: cgImage)

            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = originalCI
            blendFilter.backgroundImage = CIImage.empty()
            blendFilter.maskImage = maskCI

            guard let outputCI = blendFilter.outputImage,
                  let outputCG = ciContext.createCGImage(outputCI, from: originalCI.extent)
            else { return nil }

            return UIImage(cgImage: outputCG, scale: photo.scale, orientation: photo.imageOrientation)
        } catch {
            return nil
        }
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

