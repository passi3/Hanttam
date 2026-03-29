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
    
    //MARK: - Brand Palette
    
    private enum Palette {
        static let yellow = Color.yellow
        static let orange = Color.orange
        static let green  = Color.green
        static let blue   = Color.blue
        static let purple = Color.purple
        static let black  = Color.primary
        static let volt   = Color(red: 0.8, green: 1.0, blue: 0.0)
        
        static let chartAccent    = Color(red: 0, green: 0.31, blue: 0.83)
        static let chartNeutral   = Color(red: 0.91, green: 0.91, blue: 0.93)
        static let chartLabel     = Color(red: 0.35, green: 0.36, blue: 0.37)
        static let chartTextDark  = Color(red: 0.18, green: 0.18, blue: 0.19)
        static let chartTooltipBg = Color(red: 0.965, green: 0.965, blue: 0.976)
        
        static let workoutF6 = Color(red: 0.965, green: 0.965, blue: 0.976) // #F6F6F9
        static let orangeFF8 = Color(red: 1.0, green: 0.55, blue: 0.16)    // #FF8D28
    }
    
    //MARK: - Levle Colors
    
    static let levelYellow  = Palette.yellow
    static let levelOrange  = Palette.orange
    static let levelGreen   = Palette.green
    static let levelBlue    = Palette.blue
    static let levelPurple  = Palette.purple
    static let levelBlack   = Palette.black
    static let levelVolt    = Palette.volt
    
    //MARK: - Backgrounds
    
    #if os(iOS)
    static let bgPrimary   = Color(.systemBackground)
    static let bgSecondary = Color(.secondarySystemBackground)
    static let bgTertiary  = Color(.tertiarySystemGroupedBackground)
    static let bgGrouped   = Color(UIColor.systemGroupedBackground)
    #else
    static let bgPrimary   = Color.black
    static let bgSecondary = Color(white: 0.1)
    static let bgTertiary  = Color(white: 0.2)
    static let bgGrouped   = Color.black
    #endif
    
    static let bgRing      = Color(red: 242/255, green: 242/255, blue: 247/255)
    static let surfaceFill = Color(red: 0.96, green: 0.96, blue: 0.98)
    
    
    //MARK: - Semantic Colors
    //Text
    static let textLbel      = Color.primary
    static let textSecondary = Color.secondary
    
    #if os(iOS)
    static let textTertiary = Color(UIColor.tertiaryLabel)
    #else
    static let textTertiary = Color.gray
    #endif
    
    //Components
    static let separator      = Color(UIColor.separator)
    static let border         = Color(UIColor.separator)
    static let cardBackground = bgSecondary
    static let cardActive     = bgTertiary
    
    // MARK: - Feature: Dashboard
    
    static let dashboardAccent = Palette.chartAccent
    static let dashboardNeutral = Palette.chartNeutral
    static let dashboardLabel = Palette.chartLabel
    static let dashboardTextDark = Palette.chartTextDark
    static let dashboardTooltipBg = Palette.chartTooltipBg
    static let dashboardBg = Palette.chartTooltipBg // #F6F6F9
    static let dashboardSecondaryBg = Color(red: 0.94, green: 0.94, blue: 0.95)
    static let dashboardVolt = Color(red: 0.765, green: 0.957, blue: 0)

    // MARK: - Feature: Workout
    
    static let workoutBackground = Palette.workoutF6
    static let workoutControlBg = Palette.workoutF6
    static let workoutPause = Palette.orangeFF8
    static let workoutResume = Color.green
    static let workoutStop = Color.red
    static let workoutRoute = Color.blue
}

//MARK: - UIKit Bridge
#if os(iOS)
extension AppColor {
    /// UIColor로의 편리한 접근을 위한 브릿지
    enum UI {
        static let yellow = UIColor.systemYellow
        static let orange = UIColor.systemOrange
        static let green = UIColor.systemGreen
        static let blue = UIColor.systemBlue
        static let purple = UIColor.systemPurple
        static let black = UIColor.label
        static let volt = UIColor(red: 0.8, green: 1.0, blue: 0.0, alpha: 1.0)
        static let red = UIColor.systemRed
        
        static let backgroundPrimary = UIColor.systemBackground
        static let backgroundSecondary = UIColor.secondarySystemBackground
        static let backgroundTertiary = UIColor.tertiarySystemGroupedBackground
        static let backgroundGrouped = UIColor.systemGroupedBackground
        
        static let textPrimary = UIColor.label
        static let textSecondary = UIColor.secondaryLabel
        static let textTertiary = UIColor.tertiaryLabel
        
        static let separator = UIColor.separator
        static let tertiarySystemFill = UIColor.tertiarySystemFill
        static let systemBlue = UIColor.systemBlue
        static let systemGray5 = UIColor.systemGray5
        static let systemGray6 = UIColor.systemGray6
        
        static let dashboardBg = UIColor(red: 0.965, green: 0.965, blue: 0.976, alpha: 1)
        static let dashboardSecondaryBg = UIColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
        static let dashboardAccent = UIColor(red: 0, green: 0.31, blue: 0.83, alpha: 1)
        static let dashboardTextDark = UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1)
        static let dashboardTextGray = UIColor(red: 0.35, green: 0.36, blue: 0.37, alpha: 1)
        static let dashboardVolt = UIColor(red: 0.765, green: 0.957, blue: 0, alpha: 1)
        
        static let workoutBg = UIColor(red: 0.965, green: 0.965, blue: 0.976, alpha: 1)
        static let workoutPause = UIColor(red: 1.0, green: 0.55, blue: 0.16, alpha: 1)
        static let workoutResume = UIColor.systemGreen
        static let workoutStop = UIColor.systemRed
        static let workoutRoute = UIColor.systemBlue
    }
}
#endif
