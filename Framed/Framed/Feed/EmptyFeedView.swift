import SwiftUI

/// Shown when the database has no photos yet.
struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No photos yet")
                .font(.title3)
                .fontWeight(.medium)

            Text("Insert an SD card or use File → Test Ingest to add photos.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.body)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
