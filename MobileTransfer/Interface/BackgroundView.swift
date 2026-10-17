//
//  BackgroundView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct BackgroundView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Ellipse()
                .fill(Color(red: 0.72, green: 0.81, blue: 0.94).opacity(0.28))
                .frame(width: 520, height: 300)
                .blur(radius: 90)
                .offset(x: 210, y: -180)

            Ellipse()
                .fill(Color(red: 0.80, green: 0.73, blue: 0.89).opacity(0.20))
                .frame(width: 420, height: 340)
                .blur(radius: 90)
                .offset(x: -220, y: 180)
        }
        .ignoresSafeArea()
    }
}
