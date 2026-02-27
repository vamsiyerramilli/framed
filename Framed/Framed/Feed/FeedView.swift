import SwiftUI

/// The main review feed. Shows photos grouped by day and time-of-day section,
/// with lazy thumbnail loading, keyset pagination, and live-update notification.
struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isEmpty && !viewModel.isLoading {
                EmptyFeedView()
            } else {
                feedScrollView
            }

            // Initial load spinner (only before any days are loaded)
            if viewModel.isLoading && viewModel.days.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - Scroll view

    private var feedScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Invisible anchor at the top for "scroll to top" on banner tap
                    Color.clear
                        .frame(height: 0)
                        .id("feedTop")

                    ForEach(viewModel.days) { day in
                        DaySection(day: day)
                            .padding(.bottom, 24)
                    }

                    // Pagination trigger: becomes visible when the user reaches the bottom
                    if viewModel.hasMorePages {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded() }
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            // "New photos available" banner — floats over the top of the scroll view
            .overlay(alignment: .top) {
                if viewModel.newPhotosAvailable {
                    NewPhotosBanner {
                        Task {
                            await viewModel.reloadWithNewPhotos()
                            proxy.scrollTo("feedTop", anchor: .top)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: viewModel.newPhotosAvailable)
                }
            }
        }
    }
}
