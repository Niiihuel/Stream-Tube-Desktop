import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager

    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var results: [FfiFeedItem] = []
    @State private var continuation: String?
    @State private var filter = FfiSearchFilter(
        sort: 0,
        date: 0,
        kind: 0,
        duration: 0,
        hd: false,
        subtitles: false,
        live: false,
        fourK: false
    )
    @State private var isSearching = false
    @State private var showFilterSheet = false
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched || query.isEmpty {
                    List {
                        if !suggestions.isEmpty {
                            Section(query.isEmpty ? "Búsquedas recientes" : "Sugerencias") {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        query = suggestion
                                        Task { await executeSearch() }
                                    } label: {
                                        HStack {
                                            Image(systemName: query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                                                .foregroundStyle(.secondary)
                                            Text(suggestion)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                        }
                                    }
                                    .swipeActions {
                                        if query.isEmpty {
                                            Button(role: .destructive) {
                                                appState.client.removeSearchHistory(query: suggestion)
                                                suggestions.removeAll { $0 == suggestion }
                                            } label: {
                                                Label("Borrar", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else if isSearching && results.isEmpty {
                    ProgressView("Buscando…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                                FeedItemRow(item: item)
                                    .onAppear {
                                        if index >= results.count - 4, let next = continuation, !isSearching {
                                            Task { await loadMore(token: next) }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 80)
                    }
                }
            }
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Videos, canales o pegar enlace de YouTube")
            .onSubmit(of: .search) {
                Task { await executeSearch() }
            }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty {
                    hasSearched = false
                }
                Task {
                    suggestions = await appState.suggestions(for: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                SearchFilterSheet(filter: $filter) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { await executeSearch() }
                    }
                }
            }
            .task {
                suggestions = await appState.suggestions(for: "")
            }
        }
    }

    private func executeSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Direct YouTube URL support
        if trimmed.contains("youtu.be/") || trimmed.contains("youtube.com/") {
            if let target = try? await appState.resolveURL(trimmed) {
                switch target {
                case .video(let videoId):
                    let item = FfiVideoItem(
                        id: videoId, title: "Cargando…", channelName: "", channelId: nil,
                        channelAvatar: nil, thumbnail: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
                        compactThumbnail: nil, durationText: nil, durationSecs: nil, viewsText: nil,
                        publishedText: nil, publishedTs: nil, descriptionSnippet: nil,
                        isLive: false, isShort: false, isUpcoming: false, playlistId: nil, resumeProgress: nil
                    )
                    playerManager.play(video: item)
                    return
                case .channel(let cid):
                    appState.presentedChannelId = cid
                    return
                case .playlist(let pid):
                    appState.presentedPlaylistId = pid
                    return
                }
            }
        }

        hasSearched = true
        isSearching = true
        if let page = try? await appState.search(query: trimmed, filter: filter) {
            results = page.items
            continuation = page.continuation
        }
        isSearching = false
    }

    private func loadMore(token: String) async {
        isSearching = true
        if let page = try? await appState.continueFeed(token: token, source: "search") {
            results.append(contentsOf: page.items)
            continuation = page.continuation
        }
        isSearching = false
    }
}

struct SearchFilterSheet: View {
    @Binding var filter: FfiSearchFilter
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Ordenar por", selection: $filter.sort) {
                    Text("Relevancia").tag(UInt8(0))
                    Text("Calificación").tag(UInt8(1))
                    Text("Fecha de subida").tag(UInt8(2))
                    Text("Visualizaciones").tag(UInt8(3))
                }
                Picker("Tipo", selection: $filter.kind) {
                    Text("Todo").tag(UInt8(0))
                    Text("Videos").tag(UInt8(1))
                    Text("Canales").tag(UInt8(2))
                    Text("Listas").tag(UInt8(3))
                }
                Picker("Fecha", selection: $filter.date) {
                    Text("Cualquier fecha").tag(UInt8(0))
                    Text("Última hora").tag(UInt8(1))
                    Text("Hoy").tag(UInt8(2))
                    Text("Esta semana").tag(UInt8(3))
                    Text("Este mes").tag(UInt8(4))
                    Text("Este año").tag(UInt8(5))
                }
                Picker("Duración", selection: $filter.duration) {
                    Text("Cualquiera").tag(UInt8(0))
                    Text("Corto (< 4 min)").tag(UInt8(1))
                    Text("Medio (4–20 min)").tag(UInt8(3))
                    Text("Largo (> 20 min)").tag(UInt8(2))
                }
                Toggle("En vivo", isOn: $filter.live)
                Toggle("4K", isOn: $filter.fourK)
                Toggle("Subtítulos", isOn: $filter.subtitles)
            }
            .navigationTitle("Filtros de búsqueda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restablecer") {
                        filter = FfiSearchFilter(sort: 0, date: 0, kind: 0, duration: 0, hd: false, subtitles: false, live: false, fourK: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aplicar") {
                        dismiss()
                        onApply()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
