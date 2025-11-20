//
//  LoadingView.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("Loading...").font(.headline).foregroundColor(.secondary)
        }
    }
}

#Preview {
    LoadingView()
}
