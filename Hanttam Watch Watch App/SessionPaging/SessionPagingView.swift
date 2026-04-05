//
//  SessionPagingView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/4/26.
//

import SwiftUI
import WatchKit

struct SessionPagingView: View {
    enum Tab {
        case controls, metrics, nowPlaying
    }
    
    @State private var selection: Tab = .metrics
    
    var body: some View {
        TabView(selection: $selection) {
            ControlsView().tag(Tab.controls)
            MetricsView().tag(Tab.metrics)
            NowPlayingView().tag(Tab.nowPlaying)
        }
    }
}

#Preview {
    SessionPagingView()
}
