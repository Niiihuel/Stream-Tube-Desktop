import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [FfiFeedItem] = []
    @State private var continuation: String?
    @State private var feedSource: String = "explore"
    @State private var categories: [FfiExploreCategory] = []
    @State private var selectedCategoryId: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Category Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryChip(title: "Para ti", isSelected: selectedCategoryId == nil) {
                                selectedCategoryId = nil
                                Task { await loadFeed() }
                            }
                            ForEach(categories, id: \.channelId) { cat in
                                CategoryChip(title: cat.name, isSelected: selectedCategoryId == cat.channelId) {
                                    selectedCategoryId = cat.channelId
                                    Task { await loadFeed() }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if isLoading && items.isEmpty {
                        ProgressView("Cargando videos sin anuncios…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if let errorText, items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Reintentar") {
                                Task { await loadFeed() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                FeedItemRow(item: item)
                                    .onAppear {
                                        if index >= items.count - 4 {
                                            Task { await loadMoreIfNeeded() }
                                        }
                                    }
                            }

                            if isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 16)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                    }
                }
                .padding(.top, 6)
            }
            .navigationTitle("Stream Tube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(Color(hex: 0xFF0033))
                        Text("Stream Tube")
                            .font(.headline.weight(.bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Ad-Free")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable {
                await loadFeed()
            }
            .task {
                if categories.isEmpty {
                    categories = appState.client.exploreCategories()
                }
                if items.isEmpty {
                    await loadFeed()
                }
            }
        }
    }

    private func loadFeed() async {
        isLoading = true
        errorText = nil
        do {
            let page: FfiFeedPage
            if let catId = selectedCategoryId {
                page = try await appState.fetchExploreFeed(channelId: catId)
            } else {
                page = try await appState.fetchHomeFeed()
            }
            items = page.items
            continuation = page.continuation
            feedSource = page.source
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMoreIfNeeded() async {
        guard !isLoadingMore, !isLoading, let token = continuation else { return }
        isLoadingMore = true
        if let page = try? await appState.continueFeed(token: token, source: feedSource) {
            items.append(contentsOf: page.items)
            continuation = page.continuation
        }
        isLoadingMore = false
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.white : Color(white: 0.16),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
