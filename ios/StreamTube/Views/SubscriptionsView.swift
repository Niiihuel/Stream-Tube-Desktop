import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var videos: [FfiVideoItem] = []
    @State private var selectedChannelId: String?
    @State private var isRefreshing = false
    @State private var showManageSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.subscriptions.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Sin suscripciones aún")
                            .font(.headline)
                        Text("Suscribite a tus canales favoritos de forma 100% local (sin cuenta) o importá tus suscripciones desde Biblioteca → Ajustes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Horizontal subscribed channel filter strip
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    Button {
                                        selectedChannelId = nil
                                        loadCached()
                                    } label: {
                                        Text("Todos")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(selectedChannelId == nil ? .black : .white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedChannelId == nil ? Color.white : Color(white: 0.16), in: Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(appState.subscriptions, id: \.channelId) { sub in
                                        let active = selectedChannelId == sub.channelId
                                        Button {
                                            selectedChannelId = active ? nil : sub.channelId
                                            loadCached()
                                        } label: {
                                            HStack(spacing: 6) {
                                                AsyncImage(url: URL(string: sub.avatar ?? "")) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    Circle().fill(Color(white: 0.25))
                                                }
                                                .frame(width: 22, height: 22)
                                                .clipShape(Circle())

                                                Text(sub.name)
                                                    .font(.caption.weight(active ? .bold : .regular))
                                                    .lineLimit(1)
                                            }
                                            .foregroundStyle(active ? .black : .white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(active ? Color.white : Color(white: 0.16), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            if isRefreshing && videos.isEmpty {
                                ProgressView("Actualizando canales…")
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            } else {
                                LazyVStack(spacing: 20) {
                                    ForEach(videos, id: \.id) { video in
                                        VideoCardView(video: video)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 80)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Suscripciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !appState.subscriptions.isEmpty {
                        Button("Canales (\(appState.subscriptions.count))") {
                            showManageSheet = true
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshFeed() }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(appState.subscriptions.isEmpty || isRefreshing)
                }
            }
            .refreshable {
                await refreshFeed()
            }
            .sheet(isPresented: $showManageSheet) {
                ManageSubscriptionsSheet()
                    .environmentObject(appState)
            }
            .task {
                appState.reloadLocalState()
                loadCached()
                if videos.isEmpty && !appState.subscriptions.isEmpty {
                    await refreshFeed()
                }
            }
        }
    }

    private func loadCached() {
        let filter = selectedChannelId.map { [$0] }
        videos = appState.client.subscriptionsCached(channelFilter: filter)
    }

    private func refreshFeed() async {
        isRefreshing = true
        let filter = selectedChannelId.map { [$0] }
        if let result = try? await appState.refreshSubscriptionsFeed(filter: filter) {
            videos = result.videos
        }
        isRefreshing = false
    }
}

struct ManageSubscriptionsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.subscriptions, id: \.channelId) { sub in
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                            appState.presentedChannelId = sub.channelId
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: sub.avatar ?? "")) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color(white: 0.25))
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())

                                Text(sub.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(role: .destructive) {
                            _ = appState.toggleSubscription(channelId: sub.channelId, name: sub.name, avatar: sub.avatar)
                        } label: {
                            Text("Dejar")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .navigationTitle("Mis canales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}
