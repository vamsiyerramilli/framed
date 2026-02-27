//
//  ContentView.swift
//  Framed
//
//  Created by Vamsi Yerramilli on 27/02/26.
//

import SwiftUI

/// Minimal app shell for Slice 1 — the pipeline is the deliverable, not the UI.
/// This view is replaced by the review feed in Slice 2.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Framed")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Insert an SD card to begin ingesting photos.\nProgress is logged to the console.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .padding(40)
        .frame(width: 480, height: 300)
    }
}

#Preview {
    ContentView()
}
