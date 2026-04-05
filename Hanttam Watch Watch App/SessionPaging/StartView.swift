//
//  StartView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/4/26.
//

import SwiftUI
internal import HealthKit

struct StartView: View {
    var workoutTypes: [HKWorkoutActivityType] = [.cycling, .running, .walking]
    
    var body: some View {
        List(workoutTypes, id: \.self) { workoutType in
            NavigationLink(
                "\(workoutType)",
                destination: SessionPagingView()
            ).padding(
                EdgeInsets(top: 15, leading: 5, bottom: 15, trailing: 5)
            )
        }
        .listStyle(.carousel)
        .navigationBarTitle("workouts")
    }
}

#Preview {
    StartView()
}
