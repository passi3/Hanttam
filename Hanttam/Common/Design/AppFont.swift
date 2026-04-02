//
//  AppFont.swift
//  Hanttam
//
//  Created by passi on 4/2/26.
//

import SwiftUI
import UIKit

struct AppFont {

    // MARK: - Display

    static let displayLG = Font.system(size: 56, weight: .bold)
    static let displayMD = Font.system(size: 36, weight: .black)
    static let displaySM = Font.system(size: 32, weight: .bold)

    // MARK: - Headline / Title

    static let headlineLG = Font.system(size: 28, weight: .bold)
    static let headlineMD = Font.system(size: 28, weight: .semibold)
    static let headlineSM = Font.system(size: 24, weight: .semibold)
    static let titleLG = Font.system(size: 20, weight: .semibold)
    static let titleMD = Font.system(size: 17, weight: .semibold)
    static let titleSM = Font.system(size: 16, weight: .medium)

    // MARK: - Body

    static let bodyLG = Font.system(size: 15, weight: .regular)
    static let bodyMD = Font.system(size: 14, weight: .regular)
    static let bodySM = Font.system(size: 13, weight: .regular)

    // MARK: - Label / Caption / Button

    static let labelLG = Font.system(size: 12, weight: .bold)
    static let labelMD = Font.system(size: 11, weight: .semibold)
    static let labelSM = Font.system(size: 10, weight: .medium)
    static let captionMD = Font.system(size: 10, weight: .regular)
    static let captionSM = Font.system(size: 8, weight: .regular)
    static let buttonMD = Font.system(size: 17, weight: .semibold)

    // MARK: - Numeric / Monospaced

    static let metricDisplayXL = Font.system(size: 96, weight: .bold, design: .monospaced)
    static let metricDisplayLG = Font.system(size: 72, weight: .bold, design: .monospaced)
    static let metricHero = Font.system(size: 28, weight: .semibold, design: .monospaced)
    static let metricTitle = Font.system(size: 22, weight: .semibold, design: .monospaced)
    static let metricBody = Font.system(size: 18, weight: .medium, design: .monospaced)
    static let metricLabel = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let metricCaption = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let metricSmall = Font.system(size: 12, weight: .medium, design: .monospaced)

    // MARK: - Rounded

    static let roundedHeadline = Font.system(size: 28, weight: .medium, design: .rounded)
    static let roundedTitle = Font.system(size: 20, weight: .medium, design: .rounded)

    // MARK: - UIKit Bridge

    enum UI {
        // Display
        static let displayLG = UIFont.systemFont(ofSize: 56, weight: .bold)
        static let displayMD = UIFont.systemFont(ofSize: 36, weight: .black)
        static let displaySM = UIFont.systemFont(ofSize: 32, weight: .bold)

        // Headline / Title
        static let headlineLG = UIFont.systemFont(ofSize: 28, weight: .bold)
        static let headlineMD = UIFont.systemFont(ofSize: 28, weight: .semibold)
        static let headlineSM = UIFont.systemFont(ofSize: 24, weight: .semibold)
        static let titleLG = UIFont.systemFont(ofSize: 20, weight: .semibold)
        static let titleMD = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let titleSM = UIFont.systemFont(ofSize: 16, weight: .medium)

        // Body
        static let bodyLG = UIFont.systemFont(ofSize: 15, weight: .regular)
        static let bodyMD = UIFont.systemFont(ofSize: 14, weight: .regular)
        static let bodySM = UIFont.systemFont(ofSize: 13, weight: .regular)

        // Label / Caption / Button
        static let labelLG = UIFont.systemFont(ofSize: 12, weight: .bold)
        static let labelMD = UIFont.systemFont(ofSize: 11, weight: .semibold)
        static let labelSM = UIFont.systemFont(ofSize: 10, weight: .medium)
        static let captionMD = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let captionSM = UIFont.systemFont(ofSize: 8, weight: .regular)
        static let buttonMD = UIFont.systemFont(ofSize: 17, weight: .semibold)

        // Numeric / Monospaced
        static let metricDisplayXL = UIFont.monospacedDigitSystemFont(ofSize: 96, weight: .bold)
        static let metricDisplayLG = UIFont.monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        static let metricHero = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        static let metricTitle = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        static let metricBody = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        static let metricLabel = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        static let metricCaption = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        static let metricSmall = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        static let metricName = UIFont.monospacedSystemFont(ofSize: 32, weight: .bold)
        static let metricValueLight = UIFont.monospacedSystemFont(ofSize: 22, weight: .ultraLight)
        static let metricLabelLight = UIFont.monospacedSystemFont(ofSize: 11, weight: .light)
        static let metricThreshold = UIFont.monospacedSystemFont(ofSize: 10, weight: .light)
        static let metricRow = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

        // Rounded
        static let roundedHeadline = UIFont.systemFont(ofSize: 28, weight: .medium)
        static let roundedTitle = UIFont.systemFont(ofSize: 20, weight: .medium)
    }
}
