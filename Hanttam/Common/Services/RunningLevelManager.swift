//
//  RunningLevelManager.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import UIKit

import SwiftUI
import Combine

final class RunningLevelManager: ObservableObject {
    static let shared = RunningLevelManager()
    static let levelDidCahngeNotification = Notification.Name("RunningLevelDidChange")
    
    private static let levelKey = "userRunningLevel"
    
    @Published var totalDistance: Double = 0
    @Published var level: UserRunningLevel = .yellow {
        didSet {
            UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey)
        }
    }
    
    var accentColor: Color { level.swiftUIColor }
    #if os(iOS)
    var accentUIColor: UIColor { level.accentColor}
    #endif
    
    var progress: Double {
        guard let next = level.nextThreshold else { return 1.0 }
        let base = level.threshold
        let range = next - base
        guard range > 0 else { return 1.0 }
        return min((totalDistance - base) / range, 1.0)
    }
    
    var remainingDist: Double {
        guard let next = level.nextThreshold else { return 0 }
        return max(next - totalDistance, 0)
    }
    
    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.levelKey),
           let saved = UserRunningLevel(rawValue: raw) {
            _level = Published(initialValue: saved)
        }
    }
    
    func update(with records: [RunningRecord], completion: (() -> Void)? = nil) {
        let total = records.reduce(0) { $0 + $1.distance} / 1000
        let newLevel = UserRunningLevel.getLevel(for: total)
        DispatchQueue.main.async {
            self.totalDistance = total
            self.level = newLevel
            NotificationCenter.default.post(
                name: Self.levelDidCahngeNotification,
                object: nil)
            completion?()
        }
    }
}
