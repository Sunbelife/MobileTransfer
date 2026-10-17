//
//  CardContentView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct CardContentView<V: View>: View {
    @ViewBuilder
    let content: V

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.background)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct CardContentHeader<V: View>: View {
    let icon: String
    let title: LocalizedStringKey

    @ViewBuilder
    let trailingView: V

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .bold()
            Spacer()
            trailingView
                .transition(.opacity.combined(with: .scale))
        }
    }
}
