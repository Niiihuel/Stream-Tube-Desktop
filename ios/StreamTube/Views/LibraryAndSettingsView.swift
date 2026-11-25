import SwiftUI
import UniformTypeIdentifiers

struct LibraryAndSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager

    @State private var history: [FfiHistoryEntry] = []
    @State private var showSettings = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                // Recent Watch History Strip
                Section("Historial reciente") {
                    if history.isEmpty {
                        Text("Todavía no viste ningún video.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(history.prefix(15), id: \.video.id) { entry in
                                    Button {
                                        playerManager.play(video: entry.video)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            AsyncImage(url: URL(string: entry.video.compactThumbnail ?? entry.video.thumbnail)) { img in
                                                img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color(white: 0.16))
                                            }
                                            .frame(width: 150, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(alignment: .bottom) {
                                                if entry.durationSecs > 0 {
                                                    GeometryReader { geo in
                                                        Rectangle()
                                                            .fill(Color(hex: 0xFF0033))
                                                            .frame(width: geo.size.width * min(1, max(0, entry.progressSecs / entry.durationSecs)))
                                                    }
                                                    .frame(height: 3)
                                                }
                                            }

                                            Text(entry.video.title)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                                .frame(width: 150, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        NavigationLink("Ver todo el historial (\(history.count))") {
                            FullHistoryView(onChange: reload)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }

                // Local Playlists
                Section {
                    ForEach(appState.localPlaylists, id: \.id) { pl in
                        NavigationLink {
                            LocalPlaylistDetailView(playlist: pl)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: pl.name == "Favorites" ? "heart.fill" : (pl.name == "Watch later" ? "clock.fill" : "music.note.list"))
                                    .foregroundStyle(pl.name == "Favorites" ? Color(hex: 0xFF0033) : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizedPlaylistName(pl.name))
                                        .font(.subheadline.weight(.medium))
                                    Text("\(pl.count) videos")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            if !pl.isProtected {
                                Button(role: .destructive) {
                                    appState.client.deleteLocalPlaylist(playlistId: pl.id)
                                    appState.reloadLocalState()
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Mis listas")
                        Spacer()
                        Button {
                            showNewPlaylistAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .alert("Nueva lista local", isPresented: $showNewPlaylistAlert) {
                TextField("Nombre", text: $newPlaylistName)
                Button("Cancelar", role: .cancel) { newPlaylistName = "" }
                Button("Crear") {
                    let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = appState.client.createLocalPlaylist(name: trimmed)
                        appState.reloadLocalState()
                    }
                    newPlaylistName = ""
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheetView()
                    .environmentObject(appState)
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        appState.reloadLocalState()
        history = appState.client.watchHistory(query: "", limit: 150)
    }

    private func localizedPlaylistName(_ raw: String) -> String {
        switch raw {
        case "Watch later": return "Ver más tarde"
        case "Favorites": return "Favoritos"
        default: return raw
        }
    }
}

struct FullHistoryView: View {
    let onChange: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var entries: [FfiHistoryEntry] = []

    var body: some View {
        List {
            ForEach(entries, id: \.video.id) { entry in
                CompactVideoRow(video: entry.video)
                    .swipeActions {
                        Button(role: .destructive) {
                            appState.client.removeFromHistory(videoId: entry.video.id)
                            load()
                            onChange()
                        } label: {
                            Label("Quitar", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Buscar en el historial")
        .onChange(of: query) { _, _ in load() }
        .navigationTitle("Historial")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !entries.isEmpty {
                    Button("Limpiar", role: .destructive) {
                        appState.client.clearHistory()
                        load()
                        onChange()
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        entries = appState.client.watchHistory(query: query, limit: 400)
    }
}

struct LocalPlaylistDetailView: View {
    let playlist: FfiLocalPlaylist
    @EnvironmentObject private var appState: AppState
    @State private var videos: [FfiVideoItem] = []

    var body: some View {
        List {
            ForEach(videos, id: \.id) { video in
                CompactVideoRow(video: video)
                    .swipeActions {
                        Button(role: .destructive) {
                            appState.client.removeFromLocalPlaylist(playlistId: playlist.id, videoId: video.id)
                            load()
                            appState.reloadLocalState()
                        } label: {
                            Label("Quitar", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name == "Watch later" ? "Ver más tarde" : (playlist.name == "Favorites" ? "Favoritos" : playlist.name))
        .onAppear(perform: load)
    }

    private func load() {
        videos = appState.client.localPlaylistVideos(playlistId: playlist.id)
    }
}

struct SettingsSheetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FfiSettings?
    @State private var showImporter = false
    @State private var deviceCode: FfiDeviceCode?
    @State private var isPollingLogin = false
    @State private var backupFileURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                // Google / YouTube Optional Device Login
                Section("Cuenta de YouTube (Opcional)") {
                    if appState.authStatus.signedIn {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.authStatus.accountName ?? "Cuenta conectada")
                                    .font(.subheadline.weight(.semibold))
                                if let handle = appState.authStatus.accountHandle {
                                    Text(handle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Cerrar sesión", role: .destructive) {
                                appState.client.signOut()
                                appState.reloadLocalState()
                            }
                            .font(.caption.weight(.semibold))
                        }

                        Button("Sincronizar suscripciones de mi cuenta") {
                            Task {
                                let c = appState.client
                                if let added = try? await Task.detached(operation: { try c.syncAccountSubscriptions() }).value {
                                    appState.reloadLocalState()
                                    appState.showToast("Sincronizados \(added) canales nuevos")
                                }
                            }
                        }

                        Button("Sincronizar historial de mi cuenta") {
                            Task {
                                let c = appState.client
                                if let added = try? await Task.detached(operation: { try c.syncAccountHistory() }).value {
                                    appState.showToast("Importados \(added) videos al historial")
                                }
                            }
                        }
                    } else if let dc = deviceCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Copiá este código e ingresalo en google.com/device:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(dc.userCode)
                                    .font(.title3.monospaced().weight(.bold))
                                Spacer()
                                Button("Copiar y abrir") {
                                    UIPasteboard.general.string = dc.userCode
                                    if let url = URL(string: dc.verificationUrl) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            if isPollingLogin {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Esperando confirmación…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Button("Vincular cuenta con código (google.com/device)") {
                            Task { await beginDeviceLogin() }
                        }
                    }
                }

                if let binding = Binding($draft) {
                    Section("Reproducción sin anuncios") {
                        Picker("Calidad predeterminada", selection: binding.defaultQuality) {
                            Text("Auto (Adaptativo)").tag(UInt32(0))
                            Text("2160p (4K)").tag(UInt32(2160))
                            Text("1440p").tag(UInt32(1440))
                            Text("1080p (Full HD)").tag(UInt32(1080))
                            Text("720p").tag(UInt32(720))
                            Text("480p").tag(UInt32(480))
                            Text("360p (Ahorro de datos)").tag(UInt32(360))
                        }
                        Toggle("Reproducción continua (Autoplay)", isOn: binding.autoplayNext)
                        Toggle("Reanudar donde lo dejaste", isOn: binding.resumePlayback)
                        Toggle("Forzar pista de audio original", isOn: binding.originalAudio)
                        Toggle("Recordar velocidad por canal", isOn: binding.rememberSpeedPerChannel)
                    }

                    Section("SponsorBlock (Saltar patrocinios)") {
                        Toggle("Activar SponsorBlock", isOn: binding.sponsorblock)
                        if binding.wrappedValue.sponsorblock {
                            Toggle("Saltar patrocinadores", isOn: binding.sbSkipSponsors)
                            Toggle("Saltar autopromoción", isOn: binding.sbSkipSelfpromo)
                            Toggle("Saltar recordatorios de suscripción", isOn: binding.sbSkipInteraction)
                            Toggle("Saltar intros", isOn: binding.sbSkipIntro)
                            Toggle("Saltar outros / créditos", isOn: binding.sbSkipOutro)
                            Toggle("Saltar avances / recaps", isOn: binding.sbSkipPreview)
                            Toggle("Saltar relleno", isOn: binding.sbSkipFiller)
                            Toggle("Mostrar aviso al saltar", isOn: binding.sbNotify)
                        }
                    }

                    Section("DeArrow & Dislikes") {
                        Toggle("Mostrar contador de Dislikes (RYD)", isOn: binding.ryd)
                        Toggle("Títulos sin clickbait (DeArrow)", isOn: binding.dearrowTitles)
                        Toggle("Miniaturas limpias (DeArrow)", isOn: binding.dearrowThumbnails)
                    }

                    Section("Sin distracciones y Privacidad") {
                        Toggle("Ocultar pestaña Shorts", isOn: binding.hideShorts)
                        Toggle("Ocultar directos en feeds", isOn: binding.hideLive)
                        Toggle("Ocultar ya vistos en el feed", isOn: binding.hideWatchedInFeed)
                        Toggle("Ocultar comentarios", isOn: binding.hideComments)
                        Toggle("Ocultar videos relacionados", isOn: binding.hideRelated)
                        Toggle("Guardar historial local", isOn: binding.historyEnabled)
                        Toggle("Forzar IPv4 (evita bloqueos anti-bot)", isOn: binding.ipv4Only)
                    }
                }

                Section("Importar / Respaldar datos") {
                    Button("Importar archivo (NewPipe, FreeTube, Takeout, OPML)") {
                        showImporter = true
                    }

                    Button("Generar copia de seguridad (.json)") {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("streamtube-backup.json")
                        if (try? appState.client.exportBackupFile(path: tmp.path)) != nil {
                            backupFileURL = tmp
                        }
                    }

                    if let backupFileURL {
                        ShareLink(item: backupFileURL) {
                            Label("Compartir copia de seguridad", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        if let draft {
                            appState.updateSettings(draft)
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .commaSeparatedText, .xml, .data]
            ) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let rep = try? appState.client.importDataFile(path: url.path) {
                        appState.reloadLocalState()
                        appState.showToast("Importados: \(rep.subscriptions) canales, \(rep.playlists) listas")
                    }
                }
            }
            .onAppear {
                if draft == nil {
                    draft = appState.settings
                }
            }
        }
    }

    private func beginDeviceLogin() async {
        let c = appState.client
        guard let dc = try? await Task.detached(operation: { try c.startDeviceLogin() }).value else { return }
        deviceCode = dc
        isPollingLogin = true

        var interval = max(dc.intervalSecs, 5)
        while !Task.isCancelled && isPollingLogin {
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            guard let status = try? await Task.detached(operation: { try c.pollDeviceLogin(dc: dc) }).value else {
                break
            }
            switch status {
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .done:
                isPollingLogin = false
                deviceCode = nil
                appState.reloadLocalState()
                return
            }
        }
        isPollingLogin = false
    }
}
