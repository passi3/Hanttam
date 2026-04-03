//
//  Hanttam_WatchApp.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI

@main
struct Hanttam_Watch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { _ = WatchBridge.shared }
        }
    }
}
