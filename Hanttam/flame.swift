//
//  flame.swift
//  Hanttam
//
//  Created by passi on 3/17/26.
//
import SwiftUI

struct FlameEclipseView: View {
    @State private var phase = 0.0
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. 뒤쪽에서 타오르는 불꽃 날개들
            ZStack {
                // 왼쪽 날개
                FlameWing(color: .red, angle: -25, scale: 1.1, speed: 0.8, phase: phase)
                // 중앙 상단 메인 불꽃
                FlameWing(color: .orange, angle: 0, scale: 1.2, speed: 1.2, phase: phase)
                // 오른쪽 날개
                FlameWing(color: .yellow, angle: 20, scale: 1.0, speed: 1.0, phase: phase)
                // 뒤쪽 번짐 효과
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
            }
            .offset(y: -40) // 위쪽으로 타오르게 배치

            // 2. 아래쪽을 감싸는 얇은 불꽃 테두리 (Halo)
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(
                    LinearGradient(colors: [.clear, .orange, .yellow, .orange, .clear],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 175, height: 175)
                .rotationEffect(.degrees(90))
                .offset(y: 5 * sin(phase))

            // 3. 상호작용 가능한 중앙 검은색 서클
            Circle()
                .fill(Color.black)
                .frame(width: 170, height: 170)
                .overlay(Circle().stroke(Color.orange.opacity(0.2), lineWidth: 1))
                .onTapGesture {
                    print("Center Circle Tapped")
                }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// 개별 불꽃 조각(날개) 컴포넌트
struct FlameWing: View {
    let color: Color
    let angle: Double
    let scale: CGFloat
    let speed: Double
    let phase: Double
    
    var body: some View {
        FlameLeafShape()
            .fill(color)
            .frame(width: 70, height: 150)
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale + 0.1 * sin(phase * speed))
            .offset(y: -10 + 5 * cos(phase * speed))
            .blendMode(.screen)
    }
}

// 뾰족한 잎사귀 모양의 불꽃
struct FlameLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX * 1.5, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX * -0.5, y: rect.midY))
        return path
    }
}


#Preview {
    FlameEclipseView()
}
