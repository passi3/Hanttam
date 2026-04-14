//
//  FilmFilterEngine.swift
//  Hanttam
//
//  Created by passi on 4/14/26.
//
//  Film stock emulation pipeline backed by Core Image.
//  Parameters are ported from the reference film-filter definitions
//  (Portra 400, Ektar 100, Gold 200, Superia 400, Pro 400H,
//   CineStill 800T, Tri-X 400, HP5 Plus, Velvia 50, Aerochrome).
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - FilmStock Definition

struct FilmStock: Identifiable, Equatable, Hashable {
    static func == (lhs: FilmStock, rhs: FilmStock) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String
    let name: String
    let brand: String
    let year: String
    let desc: String

    // Tone / color shaping
    let saturation: Double        // 0.0 = grayscale, 1.0 = neutral, >1 = boosted
    let contrast: Double          // around 1.0
    let brightness: Double        // -1..1
    let temperature: Double       // warmth (positive = warm)
    let tint: Double              // green/magenta tint
    let fadeBlacks: Double        // 0..1 lifted blacks
    let highlightRolloff: Double  // 0..1

    // Per-channel curves (10 stops 0..1)
    let rCurve: [CGFloat]
    let gCurve: [CGFloat]
    let bCurve: [CGFloat]

    // Effects
    let grainAmount: Double
    let vignetteAmount: Double
    let vignetteRadius: Double
    let bloomAmount: Double
    let halationAmount: Double
    let halationColor: CIColor

    // Special
    let isBW: Bool
    let bwMix: (r: CGFloat, g: CGFloat, b: CGFloat)?
    let hueShiftDegrees: Double
    let channelSwap: (r: Int, g: Int, b: Int)? // 0=r, 1=g, 2=b

    let tags: [String]
}

// MARK: - Catalog

enum FilmStocks {
    static let all: [FilmStock] = [
        FilmStock(
            id: "portra400", name: "Portra 400", brand: "Kodak", year: "1998",
            desc: "Warm skin tones, pastel highlights",
            saturation: 0.88, contrast: 1.05, brightness: 0.02,
            temperature: 8, tint: 2, fadeBlacks: 0.04, highlightRolloff: 0.92,
            rCurve: [0, 0.02, 0.12, 0.28, 0.48, 0.62, 0.74, 0.85, 0.94, 1.0],
            gCurve: [0, 0.01, 0.10, 0.24, 0.42, 0.58, 0.71, 0.82, 0.91, 0.98],
            bCurve: [0, 0.03, 0.09, 0.20, 0.36, 0.52, 0.66, 0.78, 0.88, 0.95],
            grainAmount: 0.03, vignetteAmount: 0.25, vignetteRadius: 0.75,
            bloomAmount: 0.02, halationAmount: 0.015,
            halationColor: CIColor(red: 1.0, green: 0.70, blue: 0.55),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["portrait", "warm", "pastel"]
        ),
        FilmStock(
            id: "ektar100", name: "Ektar 100", brand: "Kodak", year: "2008",
            desc: "Vivid saturation, ultra-fine grain",
            saturation: 1.25, contrast: 1.15, brightness: -0.01,
            temperature: 3, tint: -1, fadeBlacks: 0.01, highlightRolloff: 0.95,
            rCurve: [0, 0.0, 0.08, 0.22, 0.44, 0.60, 0.75, 0.87, 0.95, 1.0],
            gCurve: [0, 0.0, 0.09, 0.24, 0.43, 0.59, 0.73, 0.85, 0.94, 1.0],
            bCurve: [0, 0.01, 0.07, 0.18, 0.35, 0.52, 0.68, 0.82, 0.92, 0.98],
            grainAmount: 0.015, vignetteAmount: 0.2, vignetteRadius: 0.8,
            bloomAmount: 0.01, halationAmount: 0.008,
            halationColor: CIColor(red: 1.0, green: 0.78, blue: 0.62),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["vivid", "landscape", "saturated"]
        ),
        FilmStock(
            id: "gold200", name: "Gold 200", brand: "Kodak", year: "1988",
            desc: "Golden warmth, nostalgic everyday",
            saturation: 1.05, contrast: 1.08, brightness: 0.03,
            temperature: 14, tint: 4, fadeBlacks: 0.03, highlightRolloff: 0.90,
            rCurve: [0, 0.02, 0.14, 0.30, 0.50, 0.65, 0.77, 0.87, 0.95, 1.0],
            gCurve: [0, 0.01, 0.11, 0.26, 0.44, 0.59, 0.72, 0.83, 0.92, 0.98],
            bCurve: [0, 0.02, 0.08, 0.18, 0.33, 0.48, 0.62, 0.75, 0.86, 0.93],
            grainAmount: 0.04, vignetteAmount: 0.3, vignetteRadius: 0.7,
            bloomAmount: 0.025, halationAmount: 0.02,
            halationColor: CIColor(red: 1.0, green: 0.75, blue: 0.47),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["warm", "golden", "nostalgic"]
        ),
        FilmStock(
            id: "superia400", name: "Superia 400", brand: "Fujifilm", year: "1998",
            desc: "Cool greens, punchy contrast",
            saturation: 1.08, contrast: 1.12, brightness: 0.0,
            temperature: -4, tint: 2, fadeBlacks: 0.025, highlightRolloff: 0.93,
            rCurve: [0, 0.01, 0.09, 0.22, 0.40, 0.56, 0.70, 0.82, 0.92, 0.98],
            gCurve: [0, 0.01, 0.11, 0.26, 0.45, 0.61, 0.75, 0.86, 0.94, 1.0],
            bCurve: [0, 0.02, 0.10, 0.23, 0.40, 0.56, 0.70, 0.82, 0.91, 0.97],
            grainAmount: 0.045, vignetteAmount: 0.28, vignetteRadius: 0.72,
            bloomAmount: 0.015, halationAmount: 0.01,
            halationColor: CIColor(red: 0.78, green: 1.0, blue: 0.78),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["cool", "green", "punchy"]
        ),
        FilmStock(
            id: "pro400h", name: "Pro 400H", brand: "Fujifilm", year: "2004",
            desc: "Soft pastels, ethereal highlights",
            saturation: 0.82, contrast: 0.95, brightness: 0.04,
            temperature: -2, tint: -1, fadeBlacks: 0.05, highlightRolloff: 0.85,
            rCurve: [0, 0.02, 0.11, 0.25, 0.43, 0.58, 0.72, 0.84, 0.93, 0.99],
            gCurve: [0, 0.02, 0.12, 0.27, 0.45, 0.60, 0.74, 0.85, 0.94, 1.0],
            bCurve: [0, 0.03, 0.13, 0.27, 0.44, 0.59, 0.73, 0.84, 0.93, 0.99],
            grainAmount: 0.025, vignetteAmount: 0.18, vignetteRadius: 0.82,
            bloomAmount: 0.035, halationAmount: 0.02,
            halationColor: CIColor(red: 0.78, green: 0.86, blue: 1.0),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["pastel", "soft", "ethereal"]
        ),
        FilmStock(
            id: "cinestill800t", name: "CineStill 800T", brand: "CineStill", year: "2012",
            desc: "Tungsten cinema, red halation",
            saturation: 0.95, contrast: 1.10, brightness: -0.01,
            temperature: -12, tint: -3, fadeBlacks: 0.02, highlightRolloff: 0.88,
            rCurve: [0, 0.01, 0.08, 0.20, 0.38, 0.55, 0.70, 0.83, 0.93, 1.0],
            gCurve: [0, 0.02, 0.10, 0.24, 0.42, 0.58, 0.72, 0.84, 0.93, 0.99],
            bCurve: [0, 0.03, 0.14, 0.30, 0.48, 0.63, 0.76, 0.86, 0.94, 1.0],
            grainAmount: 0.05, vignetteAmount: 0.35, vignetteRadius: 0.65,
            bloomAmount: 0.04, halationAmount: 0.06,
            halationColor: CIColor(red: 1.0, green: 0.31, blue: 0.20),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["cinema", "tungsten", "neon", "night"]
        ),
        FilmStock(
            id: "trix400", name: "Tri-X 400", brand: "Kodak", year: "1954",
            desc: "Iconic B&W, rich tonal range",
            saturation: 0.0, contrast: 1.25, brightness: 0.0,
            temperature: 0, tint: 0, fadeBlacks: 0.03, highlightRolloff: 0.90,
            rCurve: [0, 0.0, 0.06, 0.18, 0.38, 0.56, 0.72, 0.85, 0.94, 1.0],
            gCurve: [0, 0.0, 0.06, 0.18, 0.38, 0.56, 0.72, 0.85, 0.94, 1.0],
            bCurve: [0, 0.0, 0.06, 0.18, 0.38, 0.56, 0.72, 0.85, 0.94, 1.0],
            grainAmount: 0.065, vignetteAmount: 0.32, vignetteRadius: 0.68,
            bloomAmount: 0.02, halationAmount: 0.01,
            halationColor: CIColor(red: 0.78, green: 0.78, blue: 0.78),
            isBW: true, bwMix: (0.35, 0.50, 0.15), hueShiftDegrees: 0, channelSwap: nil,
            tags: ["bw", "classic", "gritty"]
        ),
        FilmStock(
            id: "hp5", name: "HP5 Plus", brand: "Ilford", year: "1989",
            desc: "Smooth B&W, gentle gradation",
            saturation: 0.0, contrast: 1.12, brightness: 0.02,
            temperature: 0, tint: 0, fadeBlacks: 0.05, highlightRolloff: 0.88,
            rCurve: [0, 0.01, 0.08, 0.20, 0.38, 0.55, 0.70, 0.83, 0.93, 1.0],
            gCurve: [0, 0.01, 0.08, 0.20, 0.38, 0.55, 0.70, 0.83, 0.93, 1.0],
            bCurve: [0, 0.01, 0.08, 0.20, 0.38, 0.55, 0.70, 0.83, 0.93, 1.0],
            grainAmount: 0.04, vignetteAmount: 0.22, vignetteRadius: 0.78,
            bloomAmount: 0.015, halationAmount: 0.008,
            halationColor: CIColor(red: 0.71, green: 0.71, blue: 0.71),
            isBW: true, bwMix: (0.30, 0.55, 0.15), hueShiftDegrees: 0, channelSwap: nil,
            tags: ["bw", "smooth", "gentle"]
        ),
        FilmStock(
            id: "velvia50", name: "Velvia 50", brand: "Fujifilm", year: "1990",
            desc: "Hyper-saturated slide film",
            saturation: 1.45, contrast: 1.22, brightness: -0.02,
            temperature: 1, tint: 1, fadeBlacks: 0.0, highlightRolloff: 0.97,
            rCurve: [0, 0.0, 0.06, 0.20, 0.42, 0.60, 0.76, 0.88, 0.96, 1.0],
            gCurve: [0, 0.0, 0.07, 0.22, 0.44, 0.62, 0.77, 0.89, 0.96, 1.0],
            bCurve: [0, 0.0, 0.06, 0.19, 0.40, 0.58, 0.74, 0.87, 0.95, 1.0],
            grainAmount: 0.012, vignetteAmount: 0.15, vignetteRadius: 0.85,
            bloomAmount: 0.008, halationAmount: 0.005,
            halationColor: CIColor(red: 1.0, green: 0.86, blue: 0.70),
            isBW: false, bwMix: nil, hueShiftDegrees: 0, channelSwap: nil,
            tags: ["vivid", "slide", "landscape", "saturated"]
        ),
        FilmStock(
            id: "aerochrome", name: "Aerochrome", brand: "Kodak", year: "1960s",
            desc: "Infrared false-color, surreal pinks",
            saturation: 1.15, contrast: 1.10, brightness: 0.0,
            temperature: 5, tint: 8, fadeBlacks: 0.02, highlightRolloff: 0.90,
            rCurve: [0, 0.01, 0.10, 0.25, 0.45, 0.62, 0.76, 0.87, 0.95, 1.0],
            gCurve: [0, 0.01, 0.08, 0.20, 0.38, 0.54, 0.68, 0.80, 0.90, 0.96],
            bCurve: [0, 0.02, 0.09, 0.20, 0.36, 0.50, 0.64, 0.76, 0.87, 0.94],
            grainAmount: 0.035, vignetteAmount: 0.3, vignetteRadius: 0.7,
            bloomAmount: 0.02, halationAmount: 0.025,
            halationColor: CIColor(red: 1.0, green: 0.39, blue: 0.59),
            isBW: false, bwMix: nil, hueShiftDegrees: 30,
            channelSwap: (r: 1, g: 0, b: 2), // swap R and G (infrared false-color)
            tags: ["infrared", "surreal", "experimental"]
        )
    ]

    static func stock(for id: String) -> FilmStock? {
        all.first { $0.id == id }
    }
}

// MARK: - Built-in simple filters (non-film)

enum PhotoFilterKind: Hashable {
    case original
    case mono
    case invert
    case pixel
    case film(String) // stock id

    var displayName: String {
        switch self {
        case .original: return "원본"
        case .mono:     return "모노"
        case .invert:   return "반전"
        case .pixel:    return "픽셀"
        case .film(let id):
            return FilmStocks.stock(for: id)?.name ?? id
        }
    }

    var cacheKey: String {
        switch self {
        case .original: return "original"
        case .mono:     return "mono"
        case .invert:   return "invert"
        case .pixel:    return "pixel"
        case .film(let id): return "film_\(id)"
        }
    }

    /// Returns true if this filter requires producing a baked UIImage
    /// (vs. being applied cheaply via SwiftUI view modifiers).
    var requiresBaking: Bool {
        switch self {
        case .original, .mono, .invert: return false
        case .pixel, .film: return true
        }
    }

    /// Full catalogue (simple filters + all film stocks).
    static var allPhotoFilters: [PhotoFilterKind] {
        var base: [PhotoFilterKind] = [.original, .mono, .invert, .pixel]
        base.append(contentsOf: FilmStocks.all.map { .film($0.id) })
        return base
    }

    /// Limited set for chart overlay (only cheap modifiers).
    static var chartFilters: [PhotoFilterKind] {
        [.original, .mono]
    }
}

// MARK: - Film Filter Engine

final class FilmFilterEngine {
    static let shared = FilmFilterEngine()

    private let context: CIContext
    private init() {
        self.context = CIContext(options: [.cacheIntermediates: false])
    }

    // MARK: Public API

    /// Apply a film stock to an image, returning a UIImage. Heavy — run off-main.
    func apply(stock: FilmStock, to image: UIImage, intensity: Double = 1.0) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)
        let extent = ci.extent
        ci = pipeline(ci: ci, stock: stock, intensity: intensity, extent: extent)
        guard let outCG = context.createCGImage(ci, from: extent) else { return nil }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Apply a simple filter (mono/invert/original/pixel) — returns baked UIImage.
    func applySimple(kind: PhotoFilterKind, to image: UIImage) -> UIImage? {
        switch kind {
        case .original:
            return image
        case .mono:
            guard let cg = image.cgImage else { return nil }
            let ci = CIImage(cgImage: cg)
            let filter = CIFilter.colorControls()
            filter.inputImage = ci
            filter.saturation = 0
            guard let out = filter.outputImage,
                  let outCG = context.createCGImage(out, from: ci.extent) else { return nil }
            return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
        case .invert:
            guard let cg = image.cgImage else { return nil }
            let ci = CIImage(cgImage: cg)
            let filter = CIFilter.colorInvert()
            filter.inputImage = ci
            guard let out = filter.outputImage,
                  let outCG = context.createCGImage(out, from: ci.extent) else { return nil }
            return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
        case .pixel:
            return ShareCardService.shared.pixelate(image)
        case .film(let id):
            guard let stock = FilmStocks.stock(for: id) else { return nil }
            return apply(stock: stock, to: image)
        }
    }

    /// Downscale an image for thumbnail rendering.
    func downscale(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let maxSide = max(w, h)
        guard maxSide > maxDim else { return image }
        let scale = maxDim / maxSide
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: Pipeline

    private func pipeline(ci: CIImage, stock: FilmStock, intensity: Double, extent: CGRect) -> CIImage {
        var image = ci

        // 1. Channel swap (infrared)
        if let swap = stock.channelSwap {
            image = applyChannelSwap(image, swap: swap)
        }

        // 2. Hue shift
        if abs(stock.hueShiftDegrees) > 0.01 {
            let hue = CIFilter.hueAdjust()
            hue.inputImage = image
            hue.angle = Float(stock.hueShiftDegrees * .pi / 180.0) * Float(intensity)
            if let out = hue.outputImage { image = out }
        }

        // 3. B&W channel mix (if defined) — approximated via color matrix
        if stock.isBW, let bw = stock.bwMix {
            image = applyBWChannelMix(image, mix: bw)
        }

        // 4. Temperature / Tint
        if abs(stock.temperature) > 0.01 || abs(stock.tint) > 0.01 {
            let tt = CIFilter.temperatureAndTint()
            tt.inputImage = image
            // Map abstract temperature (-12..14) to kelvin. Neutral = 6500K.
            // Positive values = warmer (lower kelvin in neutral input).
            let kelvinShift = stock.temperature * 220.0 * intensity
            tt.neutral = CIVector(x: CGFloat(6500 - kelvinShift), y: CGFloat(stock.tint * 6 * intensity))
            tt.targetNeutral = CIVector(x: 6500, y: 0)
            if let out = tt.outputImage { image = out }
        }

        // 5. Brightness / Contrast / Saturation
        let cc = CIFilter.colorControls()
        cc.inputImage = image
        cc.brightness = Float(stock.brightness * intensity)
        cc.contrast = Float(1 + (stock.contrast - 1) * intensity)
        cc.saturation = Float(1 + (stock.saturation - 1) * intensity)
        if let out = cc.outputImage { image = out }

        // 6. Curves per channel (approximate via CIToneCurve with 5 points each)
        image = applyCurves(image, stock: stock, intensity: intensity)

        // 7. Fade blacks (lifted shadows)
        if stock.fadeBlacks > 0.001 {
            image = applyFadeBlacks(image, fade: stock.fadeBlacks * intensity)
        }

        // 8. Vignette
        if stock.vignetteAmount > 0.001 {
            let vig = CIFilter.vignette()
            vig.inputImage = image
            vig.intensity = Float(stock.vignetteAmount * 2.5 * intensity)
            vig.radius = Float((1.1 - stock.vignetteRadius) * 3.0)
            if let out = vig.outputImage { image = out }
        }

        // 9. Bloom (soft glow)
        if stock.bloomAmount > 0.001 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = image
            bloom.radius = 20
            bloom.intensity = Float(stock.bloomAmount * 3 * intensity)
            if let out = bloom.outputImage { image = out.cropped(to: extent) }
        }

        // 10. Halation (colored glow from highlights)
        if stock.halationAmount > 0.001 {
            image = applyHalation(image, stock: stock, intensity: intensity, extent: extent)
        }

        // 11. Grain
        if stock.grainAmount > 0.001 {
            image = applyGrain(image, amount: stock.grainAmount * intensity, extent: extent, luminanceOnly: true)
        }

        return image.cropped(to: extent)
    }

    // MARK: - Individual filter steps

    private func applyChannelSwap(_ image: CIImage, swap: (r: Int, g: Int, b: Int)) -> CIImage {
        // CIColorMatrix picks channels via rVector/gVector/bVector
        let vectors: [CIVector] = [
            CIVector(x: 1, y: 0, z: 0, w: 0),
            CIVector(x: 0, y: 1, z: 0, w: 0),
            CIVector(x: 0, y: 0, z: 1, w: 0)
        ]
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = vectors[swap.r]
        matrix.gVector = vectors[swap.g]
        matrix.bVector = vectors[swap.b]
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage ?? image
    }

    private func applyBWChannelMix(_ image: CIImage, mix: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let row = CIVector(x: mix.r, y: mix.g, z: mix.b, w: 0)
        matrix.rVector = row
        matrix.gVector = row
        matrix.bVector = row
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage ?? image
    }

    private func applyCurves(_ image: CIImage, stock: FilmStock, intensity: Double) -> CIImage {
        // Pick 5 representative points (indices 0, 2, 4, 6, 9) from the 10-point curve
        func five(_ c: [CGFloat]) -> [CGFloat] {
            guard c.count >= 10 else { return c }
            return [c[0], c[2], c[4], c[6], c[9]]
        }

        // Shared luminance curve (average of channels) for overall tone
        let r5 = five(stock.rCurve)
        let g5 = five(stock.gCurve)
        let b5 = five(stock.bCurve)
        var luma: [CGFloat] = []
        for i in 0..<5 {
            luma.append((r5[i] + g5[i] + b5[i]) / 3)
        }
        let identityPoints: [CGFloat] = [0, 0.25, 0.5, 0.75, 1.0]
        var lumaMixed: [CGFloat] = []
        for i in 0..<5 {
            let id = identityPoints[i]
            lumaMixed.append(id + (luma[i] - id) * CGFloat(intensity))
        }

        let tc = CIFilter.toneCurve()
        tc.inputImage = image
        tc.point0 = CGPoint(x: 0.0,  y: lumaMixed[0])
        tc.point1 = CGPoint(x: 0.25, y: lumaMixed[1])
        tc.point2 = CGPoint(x: 0.5,  y: lumaMixed[2])
        tc.point3 = CGPoint(x: 0.75, y: lumaMixed[3])
        tc.point4 = CGPoint(x: 1.0,  y: lumaMixed[4])
        guard let outLuma = tc.outputImage else { return image }

        // Per-channel bias: shift each channel using relative difference between channel curve and luma curve
        // Approximate by applying a color matrix nudge on midpoint offsets
        let midR = r5[2] - lumaMixed[2]
        let midG = g5[2] - lumaMixed[2]
        let midB = b5[2] - lumaMixed[2]
        let bias = CIVector(x: midR * CGFloat(intensity) * 0.35,
                            y: midG * CGFloat(intensity) * 0.35,
                            z: midB * CGFloat(intensity) * 0.35,
                            w: 0)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = outLuma
        matrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = bias
        return matrix.outputImage ?? outLuma
    }

    private func applyFadeBlacks(_ image: CIImage, fade: Double) -> CIImage {
        // Lifted blacks: compress shadows by adding a floor — simulated via color polynomial
        let poly = CIFilter.colorPolynomial()
        poly.inputImage = image
        let f = CGFloat(fade)
        let coeff = CIVector(x: f, y: 1 - f, z: 0, w: 0)
        poly.redCoefficients = coeff
        poly.greenCoefficients = coeff
        poly.blueCoefficients = coeff
        return poly.outputImage ?? image
    }

    private func applyHalation(_ image: CIImage, stock: FilmStock, intensity: Double, extent: CGRect) -> CIImage {
        // Extract highlights → tint → blur → screen-blend over image
        // Threshold highlights using color controls (high contrast + bias)
        let highlights: CIImage = {
            let exp = CIFilter.exposureAdjust()
            exp.inputImage = image
            exp.ev = -1.0
            let base = exp.outputImage ?? image
            let ctrl = CIFilter.colorControls()
            ctrl.inputImage = base
            ctrl.contrast = 4.0
            ctrl.brightness = -0.4
            return ctrl.outputImage ?? base
        }()

        // Tint highlights with halation color
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = highlights
        let c = stock.halationColor
        colorMatrix.rVector = CIVector(x: c.red,   y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: c.green, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: c.blue, w: 0)
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let tinted = colorMatrix.outputImage ?? highlights

        // Blur
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = tinted.clampedToExtent()
        blur.radius = 18
        let blurred = (blur.outputImage ?? tinted).cropped(to: extent)

        // Modulate halation strength
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = blurred
        let strength = CGFloat(stock.halationAmount * 6 * intensity) // visible bump
        alpha.rVector = CIVector(x: strength, y: 0, z: 0, w: 0)
        alpha.gVector = CIVector(x: 0, y: strength, z: 0, w: 0)
        alpha.bVector = CIVector(x: 0, y: 0, z: strength, w: 0)
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let scaled = alpha.outputImage ?? blurred

        // Additive composite
        let composite = CIFilter.additionCompositing()
        composite.inputImage = scaled.cropped(to: extent)
        composite.backgroundImage = image
        return composite.outputImage ?? image
    }

    private func applyGrain(_ image: CIImage, amount: Double, extent: CGRect, luminanceOnly: Bool) -> CIImage {
        // Generate colored noise then desaturate if luminance-only.
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
        let cropped = noise.cropped(to: extent)

        // Desaturate to luminance gray noise
        let mono = CIFilter.colorControls()
        mono.inputImage = cropped
        mono.saturation = luminanceOnly ? 0 : 0.5
        mono.brightness = -0.5
        mono.contrast = 1.0
        let grainBase = mono.outputImage ?? cropped

        // Fade grain amount via opacity (alpha premultiplication)
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = grainBase
        let a = CGFloat(min(0.9, amount * 3.5))
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: a)
        alpha.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let grainLayer = alpha.outputImage ?? grainBase

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = grainLayer
        composite.backgroundImage = image
        return composite.outputImage ?? image
    }
}

