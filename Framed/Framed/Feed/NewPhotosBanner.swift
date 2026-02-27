import SwiftUI

/// Floating banner shown when new photos arrive mid-session via ValueObservation.
/// Tapping it triggers a feed reload and scroll to top. Does not auto-dismiss.
struct NewPhotosBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                Text("New photos available")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.blue, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }
}
