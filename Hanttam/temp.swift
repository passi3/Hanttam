//
//  temp.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import SwiftUI

// MARK: - 1. 앱 아이콘용 디자인 뷰 (1024 x 1024)
struct AppIconDesignView: View {
    var body: some View {
        ZStack {
            // ⭐️ 규칙 1: 앱 아이콘은 투명도가 없어야 합니다. 반드시 단색 배경을 꽉 채워주세요.
            Color(red: 240/255, green: 240/255, blue: 245/255)
            
            // 아까 만드신 뷰를 넣고, 1024 사이즈에 맞게 크기를 키웁니다.
            HanttamCirclesView()
                .scaleEffect(4.0)
        }
        // ⭐️ 규칙 2: 앱 아이콘 원본 사이즈는 무조건 1024x1024 픽셀이어야 합니다.
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - 2. 이미지를 추출하고 사진첩에 저장하는 화면
struct IconExporterView: View {
    @State private var showSuccessMessage = false
    
    var body: some View {
        VStack(spacing: 40) {
            Text("앱 아이콘 프리뷰")
                .font(.headline)
            
            // 화면에는 작게 줄여서 보여줍니다 (코너 둥글기는 애플이 알아서 깎아주므로 미리보기용으로만 적용)
            AppIconDesignView()
                .frame(width: 256, height: 256)
                .clipShape(RoundedRectangle(cornerRadius: 56))
                .shadow(radius: 10)
            
            Button(action: exportAndSaveIcon) {
                Text("고화질 이미지로 사진첩에 저장하기")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            
            if showSuccessMessage {
                Text("✅ 사진첩에 저장 완료! (시뮬레이터 사진첩을 확인하세요)")
                    .foregroundColor(.green)
                    .bold()
            }
        }
    }
    
    // MARK: - 렌더링 및 저장 로직
    private func exportAndSaveIcon() {
        // 1. ImageRenderer에 렌더링할 뷰를 넣습니다.
        let renderer = ImageRenderer(content: AppIconDesignView())
        
        // 2. 화면 스케일의 영향을 받지 않고 1024x1024 픽셀을 정확히 뽑기 위해 scale을 1.0으로 고정합니다.
        renderer.scale = 1.0
        
        // 3. UIImage로 변환하여 사진첩에 저장합니다.
        if let uiImage = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
            
            withAnimation {
                showSuccessMessage = true
            }
        }
    }
}

#Preview {
    IconExporterView()
}
