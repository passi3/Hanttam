//
//  UserRunningLevel.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import SwiftUI

enum UserRunningLevel: String, CaseIterable {
    case yellow = "Yellow"
    case orange = "Orange"
    case green  = "Green"
    case blue   = "Blue"
    case purple = "Purple"
    case black  = "Black"
    case volt   = "Volt"
    
    static func getLevel(for distance: Double) -> UserRunningLevel {
        switch distance {
        case 0..<50:       return .yellow
        case 50..<250:     return .orange
        case 250..<1000:   return .green
        case 1000..<2500:  return .blue
        case 2500..<5000:  return .purple
        case 5000..<15000: return .black
        default:           return .volt
        }
    }
    
    #if os(iOS)
    var gradeColor: UIColor {
        switch self {
        case .yellow: return AppColor.UI.yellow
        case .orange: return AppColor.UI.orange
        case .green:  return AppColor.UI.green
        case .blue:   return AppColor.UI.blue
        case .purple: return AppColor.UI.purple
        case .black:  return AppColor.UI.black
        case .volt:   return AppColor.UI.volt
        }
    }
    #endif
    
    var swiftUIColor: Color {
        switch self {
        case .yellow: return AppColor.levelYellow
        case .orange: return AppColor.levelOrange
        case .green:  return AppColor.levelGreen
        case .blue:   return AppColor.levelBlue
        case .purple: return AppColor.levelPurple
        case .black:  return AppColor.levelBlack
        case .volt:   return AppColor.levelVolt
        }
    }
    
    var threshold: Double {
        switch self {
        case .yellow: return 0
        case .orange: return 50
        case .green:  return 250
        case .blue:   return 1000
        case .purple: return 2500
        case .black:  return 5000
        case .volt:   return 15000
        }
    }

    var nextThreshold: Double? {
        switch self {
        case .yellow: return 50
        case .orange: return 250
        case .green:  return 1000
        case .blue:   return 2500
        case .purple: return 5000
        case .black:  return 15000
        case .volt:   return nil
        }
    }

    var displayName: String {
        switch self {
        case .yellow: return "옐로"
        case .orange: return "오렌지"
        case .green:  return "그린"
        case .blue:   return "블루"
        case .purple: return "퍼플"
        case .black:  return "블랙"
        case .volt:   return "볼트"
        }
    }

    var iconName: String {
        switch self {
        case .yellow: return "figure.walk"
        case .orange: return "figure.run"
        case .green:  return "figure.run"
        case .blue:   return "figure.run.circle"
        case .purple: return "figure.run.circle.fill"
        case .black:  return "bolt.fill"
        case .volt:   return "bolt.ring.closed"
        }
    }

}
