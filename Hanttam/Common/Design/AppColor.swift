//
//  AppColor.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AppColor {

    // MARK: - Palette

    private enum Palette {
        static let primary = Color(hex: "005ABC")
        static let success = Color(hex: "6D7F00")
        static let warning = Color(hex: "FF9F0A")
        static let error = Color(hex: "E4572E")

        static let surface = Color(hex: "EEEDF2")
        static let onSurface = Color(hex: "1A1B1F")
        static let inkSoft = Color(hex: "60656F")
        static let inkMuted = Color(hex: "9096A1")

        static let card = Color.white
        static let cardActive = Color(hex: "E4E8F2")
        static let border = Color(hex: "D5D9E2")
        static let separator = Color(hex: "C9CFD8")
        static let ringBackground = Color(hex: "E5E7EE")

        static let overlay = Color.black.opacity(0.4)
        static let overlayStrong = Color.black.opacity(0.55)
        static let inverseText = Color.white
        static let inverseSubtle = Color.white.opacity(0.7)
        static let inverseMuted = Color.white.opacity(0.5)
        static let inverseTertiary = Color.white.opacity(0.35)

        static let dashboardBg = Color(hex: "F6F7FA")
        static let dashboardCard = Color.white
        static let dashboardTooltip = Color(hex: "11151D")
        static let dashboardNeutral = Color(hex: "D7D9DF")

        static let weatherCard = Color.black.opacity(0.6)
        static let chipFill = Color(hex: "E8EBF2")
        static let fillTertiary = Color(hex: "EEF1F5")
        static let hanttamRing = Color(red: 151/255, green: 42/255, blue: 0)

        static let levelYellow = Color.yellow
        static let levelOrange = Color.orange
        static let levelGreen = Color.green
        static let levelBlue = Color.blue
        static let levelPurple = Color.purple
        static let levelVolt = Color(hex: "DFFF00")

        static let chartAccent = Color(red: 0.00, green: 0.31, blue: 0.83)
        static let chartNeutral = Color(red: 0.91, green: 0.91, blue: 0.93)
        static let chartCyan = Color(red: 0.00, green: 0.71, blue: 0.85)
        static let chartMint = Color(red: 0.02, green: 0.84, blue: 0.63)
        static let chartPurple = Color(red: 0.88, green: 0.25, blue: 0.98)
        static let chartYellow = Color(red: 0.99, green: 0.83, blue: 0.00)
        static let pace = Color(red: 0.45, green: 0.78, blue: 0.25)
        static let cadence = Color(red: 0.20, green: 0.70, blue: 0.65)
        static let stride = Color(red: 0.35, green: 0.55, blue: 0.85)
        static let verticalOscillation = Color(red: 0.55, green: 0.45, blue: 0.80)
        static let groundContact = Color(red: 0.85, green: 0.50, blue: 0.30)
        static let power = Color(red: 0.90, green: 0.60, blue: 0.20)
        static let elevation = Color(red: 0.55, green: 0.75, blue: 0.30)
        static let altitude = Color(red: 0.40, green: 0.65, blue: 0.45)
        static let paceGradientTop = Color(red: 0.85, green: 0.90, blue: 0.15)
    }

    // MARK: - Brand / Accent

    static let primary = Palette.primary
    static let success = Palette.success
    static let warning = Palette.warning
    static let red = Palette.error

    // MARK: - Level Colors

    static let levelYellow = Palette.levelYellow
    static let levelOrange = Palette.levelOrange
    static let levelGreen = Palette.levelGreen
    static let levelBlue = Palette.levelBlue
    static let levelPurple = Palette.levelPurple
    static let levelBlack = Palette.onSurface
    static let levelVolt = Palette.levelVolt

    // Compatibility aliases
    static let yellow = levelYellow
    static let orange = levelOrange
    static let green = levelGreen
    static let blue = levelBlue
    static let purple = levelPurple
    static let black = levelBlack
    static let volt = levelVolt

    // MARK: - Background / Surface

    #if os(iOS)
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    static let backgroundGrouped = Color(UIColor.systemGroupedBackground)
    static let backgroundTertiary = Color(UIColor.secondarySystemGroupedBackground)
    #else
    static let backgroundPrimary = Palette.dashboardBg
    static let backgroundSecondary = Palette.surface
    static let backgroundGrouped = Palette.dashboardBg
    static let backgroundTertiary = Palette.surface
    #endif

    static let surface = Palette.surface
    static let surfaceFill = Palette.surface
    static let cardBackground = Palette.card
    static let cardActive = Palette.cardActive
    static let chipBackground = Palette.chipFill
    static let fillTertiary = Palette.fillTertiary
    static let backgroundRing = Palette.ringBackground
    static let hanttamRing = Palette.hanttamRing

    // MARK: - Text

    static let onSurface = Palette.onSurface
    static let textPrimary = Palette.onSurface
    static let textSecondary = Palette.inkSoft
    static let textTertiary = Palette.inkMuted
    static let textInverse = Palette.inverseText
    static let textInverseSecondary = Palette.inverseSubtle
    static let textInverseMuted = Palette.inverseMuted
    static let textInverseTertiary = Palette.inverseTertiary

    // MARK: - Borders / Overlays

    static let border = Palette.border
    static let separator = Palette.separator
    static let overlay = Palette.overlay
    static let overlayStrong = Palette.overlayStrong

    // MARK: - Dashboard

    static let dashboardBg = Palette.dashboardBg
    static let dashboardSecondaryBg = Palette.dashboardCard
    static let dashboardTextDark = Palette.onSurface
    static let dashboardTextGray = Palette.inkSoft
    static let dashboardLabel = Palette.inkSoft
    static let dashboardNeutral = Palette.dashboardNeutral
    static let dashboardTooltipBg = Palette.dashboardTooltip

    // MARK: - Workout

    static let workoutBackground = Palette.surface
    static let workoutBg = Palette.surface
    static let workoutPause = Palette.warning
    static let workoutResume = Palette.success
    static let workoutStop = Palette.error
    static let workoutRoute = Palette.primary
    static let weatherCardBackground = Palette.weatherCard

    // MARK: - Data Viz

    static let chartAccent = Palette.chartAccent
    static let chartNeutral = Palette.chartNeutral
    static let chartCyan = Palette.chartCyan
    static let chartMint = Palette.chartMint
    static let chartPurple = Palette.chartPurple
    static let chartYellow = Palette.chartYellow
    static let pace = Palette.pace
    static let cadence = Palette.cadence
    static let strideLength = Palette.stride
    static let verticalOscillation = Palette.verticalOscillation
    static let groundContactTime = Palette.groundContact
    static let power = Palette.power
    static let cumulativeElevation = Palette.elevation
    static let altitude = Palette.altitude
    static let paceGradientTop = Palette.paceGradientTop
}

// MARK: - UIKit Bridge

extension AppColor {
    enum UI {
        // Brand / semantic
        static let primary = UIColor(hex: "005ABC")
        static let success = UIColor(hex: "6D7F00")
        static let warning = UIColor(hex: "FF9F0A")
        static let red = UIColor(hex: "E4572E")
        static let surface = UIColor(hex: "EEEDF2")
        static let onSurface = UIColor(hex: "1A1B1F")
        static let textPrimary = onSurface
        static let textSecondary = UIColor(hex: "60656F")
        static let textTertiary = UIColor(hex: "9096A1")

        // Levels
        static let levelYellow = UIColor(hex: "FFD60A")
        static let levelOrange = UIColor(hex: "FF9F0A")
        static let levelGreen = UIColor(hex: "34C759")
        static let levelBlue = UIColor(hex: "0A84FF")
        static let levelPurple = UIColor(hex: "BF5AF2")
        static let levelBlack = onSurface
        static let levelVolt = UIColor(hex: "DFFF00")

        // Compatibility aliases
        static let yellow = levelYellow
        static let orange = levelOrange
        static let green = levelGreen
        static let blue = levelBlue
        static let purple = levelPurple
        static let black = levelBlack
        static let volt = levelVolt

        // Backgrounds
        static let backgroundPrimary = UIColor(hex: "FFFFFF")
        static let backgroundSecondary = UIColor(hex: "F6F7FA")
        static let backgroundGrouped = UIColor(hex: "F2F4F7")
        static let backgroundTertiary = UIColor(hex: "ECEFF4")
        static let cardBackground = UIColor(hex: "FFFFFF")
        static let cardActive = UIColor(hex: "E4E8F2")
        static let border = UIColor(hex: "D5D9E2")
        static let separator = UIColor(hex: "C9CFD8")
        static let tertiarySystemFill = UIColor(hex: "EEF1F5")
        static let hanttamRing = UIColor(red: 151/255, green: 42/255, blue: 0, alpha: 1)
        static let systemGray5 = UIColor(hex: "E5E5EA")
        static let systemGray6 = UIColor(hex: "F2F2F7")
        static let systemBlue = UIColor(hex: "0A84FF")

        // Dashboard
        static let dashboardBg = UIColor(hex: "F6F7FA")
        static let dashboardSecondaryBg = UIColor.white
        static let dashboardTextDark = onSurface
        static let dashboardTextGray = textSecondary
        static let dashboardTooltipBg = UIColor(hex: "11151D")

        // Workout
        static let workoutBg = surface
        static let workoutPause = warning
        static let workoutResume = success
        static let workoutStop = red
        static let workoutRoute = primary
        static let weatherCard = UIColor.black.withAlphaComponent(0.6)

        // Overlay / inverse
        static let overlay = UIColor.black.withAlphaComponent(0.4)
        static let overlayStrong = UIColor.black.withAlphaComponent(0.55)
        static let textInverse = UIColor.white
        static let textInverseSecondary = UIColor.white.withAlphaComponent(0.7)
        static let textInverseMuted = UIColor.white.withAlphaComponent(0.5)
        static let textInverseTertiary = UIColor.white.withAlphaComponent(0.35)
    }
}

// MARK: - Helpers

fileprivate extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

fileprivate extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
