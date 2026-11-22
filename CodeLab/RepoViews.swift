import SwiftUI

func langColor(_ l: String?) -> Color {
    switch (l ?? "").lowercased() {
    case "swift": return .orange
    case "java": return Color(red: 0.69, green: 0.45, blue: 0.1)
    case "c++", "c": return .pink
    case "kotlin": return .purple
    case "python": return .blue
    case "gdscript": return .teal
    case "javascript": return .yellow
    case "html": return .red
    default: return .gray
    }
}

// MARK: - Cartão lateral

struct RepoCard: View {
    let repo: GHRepo
    let fav: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(repo.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if fav { Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.yellow) }
            }
            if let d = repo.description, !d.isEmpty {
                Text(d).font(.caption).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let l = repo.language {
                    Circle().fill(langColor(l)).frame(width: 8, height: 8)
                    Text(l).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if repo.stars > 0 {
                    Image(systemName: "star").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(String(repo.stars)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 190, height: 104, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Todos os repositórios

struct RepoListView: View {
    @EnvironmentObject var gh: GitHub
    @State private var query = ""
    @State private var favs = Favorites.list()

    var sorted: [GHRepo] {
        let q = query.lowercased()
        let list = gh.allRepos.filter { q.isEmpty || $0.fullName.lowercased().contains(q) }
        return list.filter { favs.contains($0.fullName) } + list.filter { !favs.contains($0.fullName) }
    }

    var body: some View {
        List {
            ForEach(sorted) { r in
                NavigationLink(destination: RepoDetailView(repo: r)) {
                    HStack(spacing: 8) {
                        if favs.contains(r.fullName) {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(.yellow).frame(width: 14)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                            if let l = r.language { Text(l).font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        if r.isPrivate { Image(systemName: "lock").font(.caption).foregroundColor(.secondary) }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Favorites.toggle(r.fullName)
                        favs = Favorites.list()
                    } label: {
                        Label("Favoritar", systemImage: "star")
                    }
                    .tint(.yellow)
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar repositório")
        .navigationTitle("Repositórios")
        .dockInset()
        .task { await gh.loadAllRepos() }
    }
}

// MARK: - Abrir um repositório (como no GitHub)

struct RepoDetailView: View {
    let repo: GHRepo
    @EnvironmentObject var gh: GitHub
    @State private var branch: String
    @State private var branches: [String] = []
    @State private var showDownload = false

    init(repo: GHRepo) {
        self.repo = repo
        _branch = State(initialValue: repo.defaultBranch)
    }

    func tile(_ icon: String, _ color: Color, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .cornerRadius(7)
            Text(title)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(repo.fullName).font(.footnote).foregroundColor(.secondary)
                    Text(repo.name).font(.title2.weight(.bold))
                    if let d = repo.description, !d.isEmpty { Text(d).font(.subheadline).foregroundColor(.secondary) }
                    HStack(spacing: 12) {
                        if let l = repo.language {
                            HStack(spacing: 4) {
                                Circle().fill(langColor(l)).frame(width: 8, height: 8)
                                Text(l).font(.caption)
                            }
                        }
                        Label(String(repo.stars), systemImage: "star").font(.caption)
                        if repo.isPrivate { Label("Privado", systemImage: "lock").font(.caption) }
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                Button { showDownload = true } label: {
                    Label("Baixar para o aparelho", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                if let u = URL(string: repo.url) {
                    Link(destination: u) { Label("Abrir no GitHub", systemImage: "safari") }
                }
            }

            Section {
                HStack {
                    Image(systemName: "arrow.triangle.branch").foregroundColor(.secondary)
                    Text(branch).font(.system(.body, design: .monospaced))
                    Image(systemName: "checkmark").font(.caption).foregroundColor(.green)
                    Spacer()
                    if branches.count > 1 {
                        Menu {
                            ForEach(branches, id: \.self) { b in
                                Button {
                                    branch = b
                                } label: {
                                    if b == branch { Label(b, systemImage: "checkmark") } else { Text(b) }
                                }
                            }
                        } label: {
                            Text("Trocar branch").font(.subheadline)
                        }
                    }
                }
            }

            Section {
                NavigationLink(destination: RepoCodeView(slug: repo.fullName, branch: branch, path: "")) {
                    tile("chevron.left.forwardslash.chevron.right", Color(.systemGray), "Código")
                }
                NavigationLink(destination: RepoActionsView(slug: repo.fullName, branch: branch)) {
                    tile("play.fill", .orange, "Actions")
                }
                NavigationLink(destination: RepoArtifactsView(slug: repo.fullName)) {
                    tile("shippingbox.fill", .blue, "Artefatos")
                }
            }
        }
        .listStyle(.insetGrouped)
        .dockInset()
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            var b = await gh.branches(of: repo.fullName)
            if b.isEmpty { b = [repo.defaultBranch] }
            branches = b
            if !b.contains(branch) { branch = b[0] }
        }
        .sheet(isPresented: $showDownload) {
            DownloadRepoView(slug: repo.fullName, branch: branch, language: repo.language)
                .environmentObject(gh)
        }
    }
}

// MARK: - Código (pastas e arquivos do repositório)

struct RepoCodeView: View {
    let slug: String
    let branch: String
    let path: String
    @EnvironmentObject var gh: GitHub
    @State private var items: [RepoItem] = []
    @State private var loading = true
    @State private var error = ""
    @State private var toDelete: RepoItem? = nil
    @State private var busy = false

    func load() async {
        loading = true
        error = ""
        do { items = try await gh.listContents(slug, path, branch) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    func remove(_ it: RepoItem) {
        Task { @MainActor in
            busy = true
            defer { busy = false }
            do {
                try await gh.deletePaths(slug, branch: branch, paths: [it.path],
                                         message: "Apagar " + it.path + " (CodeLab)")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await load()
            } catch {
                self.error = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    @ViewBuilder func rowLabel(_ it: RepoItem) -> some View {
        HStack {
            Image(systemName: it.isDir ? "folder.fill" : "doc.text")
                .foregroundColor(it.isDir ? Color(red: 0.45, green: 0.65, blue: 0.95) : .secondary)
                .frame(width: 22)
            Text(it.name)
            Spacer()
            if !it.isDir && it.size > 0 {
                Text(Fmt.size(it.size)).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        List {
            if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
            if loading && items.isEmpty {
                HStack { ProgressView(); Text("Carregando…").foregroundColor(.secondary) }
            }
            ForEach(items) { it in
                Group {
                    if it.isDir {
                        NavigationLink(destination: RepoCodeView(slug: slug, branch: branch, path: it.path)) { rowLabel(it) }
                    } else {
                        NavigationLink(destination: RepoFileView(slug: slug, branch: branch, path: it.path)) { rowLabel(it) }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { toDelete = it } label: { Label("Apagar", systemImage: "trash") }
                }
                .contextMenu {
                    Button(role: .destructive) { toDelete = it } label: { Label("Apagar do repositório", systemImage: "trash") }
                }
            }
        }
        .dockInset()
        .navigationTitle(path.isEmpty ? "Código" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if busy { ProgressView() } else {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "Apagar do repositório?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible,
            presenting: toDelete
        ) { it in
            Button((it.isDir ? "Apagar a pasta " : "Apagar ") + it.name, role: .destructive) { remove(it) }
            Button("Cancelar", role: .cancel) {}
        } message: { it in
            Text("Isso cria um commit na branch " + branch + " removendo " + (it.isDir ? "a pasta e tudo dentro dela." : "o arquivo."))
        }
    }
}

struct RepoFileView: View {
    let slug: String
    let branch: String
    let path: String
    @EnvironmentObject var gh: GitHub
    @Environment(\.presentationMode) var pm
    @State private var text = ""
    @State private var error = ""
    @State private var loading = true
    @State private var confirm = false

    var body: some View {
        Group {
            if loading {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if !error.isEmpty {
                VStack { Spacer(); Text(error).foregroundColor(.secondary).padding(); Spacer() }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
        }
        .dockInset()
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { UIPasteboard.general.string = text } label: { Image(systemName: "doc.on.doc") }
                    .disabled(text.isEmpty)
                Button(role: .destructive) { confirm = true } label: { Image(systemName: "trash") }
            }
        }
        .task {
            do { text = try await gh.fileText(slug, path, branch) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .confirmationDialog("Apagar este arquivo do repositório?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Apagar " + (path as NSString).lastPathComponent, role: .destructive) {
                Task { @MainActor in
                    do {
                        try await gh.deletePaths(slug, branch: branch, paths: [path], message: "Apagar " + path + " (CodeLab)")
                        pm.wrappedValue.dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Actions e artefatos

struct RepoActionsView: View {
    let slug: String
    let branch: String
    @EnvironmentObject var gh: GitHub
    @State private var runs: [RunInfo] = []
    @State private var loading = true
    @State private var error = ""

    func load() async {
        loading = true
        error = ""
        do { runs = try await gh.listRuns(slug, branch: nil) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    @ViewBuilder func statusIcon(_ r: RunInfo) -> some View {
        if r.status != "completed" {
            Image(systemName: "clock.fill").foregroundColor(.orange)
        } else if r.conclusion == "success" {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        } else if r.conclusion == "cancelled" || r.conclusion == "skipped" {
            Image(systemName: "slash.circle").foregroundColor(.secondary)
        } else {
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    var body: some View {
        List {
            if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
            if loading && runs.isEmpty {
                HStack { ProgressView(); Text("Carregando…").foregroundColor(.secondary) }
            }
            if !loading && runs.isEmpty && error.isEmpty {
                Text("Nenhuma execução ainda.").foregroundColor(.secondary)
            }
            ForEach(runs) { r in
                NavigationLink(destination: RunDetailView(slug: slug, run: r)) {
                    HStack(spacing: 10) {
                        statusIcon(r).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline).lineLimit(2)
                            Text("#" + String(r.number) + " · " + r.branch + " · " + Fmt.ago(r.created))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .dockInset()
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
}

struct RunDetailView: View {
    let slug: String
    let run: RunInfo
    @EnvironmentObject var gh: GitHub
    @Environment(\.presentationMode) var pm
    @State private var arts: [ArtifactInfo] = []
    @State private var loading = true
    @State private var msg = ""
    @State private var confirmDelete = false

    func load() async {
        loading = true
        do { arts = try await gh.listArtifacts(slug, runId: run.id) }
        catch { msg = error.localizedDescription }
        loading = false
    }

    var body: some View {
        List {
            Section(header: Text("Execução")) {
                Text(run.title).font(.subheadline)
                HStack { Text("Estado"); Spacer(); Text(run.status == "completed" ? run.conclusion : run.status).foregroundColor(.secondary) }
                HStack { Text("Branch"); Spacer(); Text(run.branch).foregroundColor(.secondary) }
                HStack { Text("Disparo"); Spacer(); Text(run.event).foregroundColor(.secondary) }
                if let u = URL(string: run.url) {
                    Link(destination: u) { Label("Abrir no GitHub", systemImage: "safari") }
                }
            }
            Section(header: Text("Artefatos")) {
                if loading && arts.isEmpty { HStack { ProgressView(); Text("Carregando…").foregroundColor(.secondary) } }
                if !loading && arts.isEmpty { Text("Esta execução não gerou artefatos.").foregroundColor(.secondary) }
                ForEach(arts) { a in
                    ArtifactRow(slug: slug, art: a) { arts.removeAll { $0.id == a.id } }
                }
            }
            Section {
                Button {
                    Task { @MainActor in
                        do { try await gh.rerun(slug, run.id); msg = "Execução reenviada." }
                        catch { msg = error.localizedDescription }
                    }
                } label: { Label("Executar de novo", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Excluir esta execução", systemImage: "trash") }
                if !msg.isEmpty { Text(msg).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .dockInset()
        .navigationTitle("#" + String(run.number))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Excluir esta execução?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                Task { @MainActor in
                    do { try await gh.deleteRun(slug, run.id); pm.wrappedValue.dismiss() }
                    catch { msg = error.localizedDescription }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

struct RepoArtifactsView: View {
    let slug: String
    @EnvironmentObject var gh: GitHub
    @State private var arts: [ArtifactInfo] = []
    @State private var loading = true
    @State private var error = ""

    func load() async {
        loading = true
        error = ""
        do { arts = try await gh.listArtifacts(slug, runId: nil) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    var body: some View {
        List {
            if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
            if loading && arts.isEmpty { HStack { ProgressView(); Text("Carregando…").foregroundColor(.secondary) } }
            if !loading && arts.isEmpty && error.isEmpty {
                Text("Nenhum artefato gerado ainda.").foregroundColor(.secondary)
            }
            ForEach(arts) { a in
                ArtifactRow(slug: slug, art: a) { arts.removeAll { $0.id == a.id } }
            }
        }
        .dockInset()
        .navigationTitle("Artefatos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
}

struct ArtifactRow: View {
    let slug: String
    let art: ArtifactInfo
    let onDeleted: () -> Void
    @EnvironmentObject var gh: GitHub
    @State private var busy = false
    @State private var msg = ""
    @State private var share: ShareItem? = nil
    @State private var confirmDelete = false

    func download() {
        Task { @MainActor in
            busy = true
            msg = ""
            defer { busy = false }
            do {
                let u = try await gh.downloadArtifact(slug, art)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                share = ShareItem(url: u)
            } catch {
                msg = error.localizedDescription
            }
        }
    }

    func remove() {
        Task { @MainActor in
            do {
                try await gh.deleteArtifact(slug, art.id)
                onDeleted()
            } catch {
                msg = error.localizedDescription
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: art.expired ? "archivebox" : "shippingbox.fill")
                .foregroundColor(art.expired ? .secondary : .accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(art.name).font(.subheadline)
                Text(Fmt.size(art.size) + " · " + Fmt.ago(art.created) + (art.expired ? " · expirado" : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !msg.isEmpty { Text(msg).font(.caption).foregroundColor(.red) }
            }
            Spacer()
            if busy {
                ProgressView()
            } else if !art.expired {
                Button { download() } label: { Image(systemName: "arrow.down.circle") }
                    .buttonStyle(.borderless)
            }
        }
        .swipeActions {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Excluir", systemImage: "trash") }
        }
        .confirmationDialog("Excluir este artefato?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) { remove() }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $share) { item in ShareSheet(items: [item.url]) }
    }
}

// MARK: - Baixar o projeto para o aparelho

struct DownloadRepoView: View {
    let slug: String
    let branch: String
    @EnvironmentObject var gh: GitHub
    @EnvironmentObject var app: AppState
    @Environment(\.presentationMode) var pm
    @State private var lang: Lang
    @State private var name: String
    @State private var log = ""
    @State private var busy = false
    @State private var done = false

    init(slug: String, branch: String, language: String?) {
        self.slug = slug
        self.branch = branch
        _lang = State(initialValue: RepoLang.lang(forRepoLanguage: language))
        _name = State(initialValue: String(slug.split(separator: "/").last ?? "projeto"))
    }

    func clean(_ s: String) -> String {
        String(s.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "-" })
    }

    func start() {
        let n = clean(name)
        Task { @MainActor in
            busy = true
            log = ""
            defer { busy = false }
            do {
                _ = try await gh.downloadRepo(slug: slug, branch: branch, lang: lang, name: n, say: { log += $0 + "\n" })
                done = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                log += "✗ " + error.localizedDescription + "\n"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Origem")) {
                    Label(slug + " · " + branch, systemImage: "arrow.down.circle")
                }
                Section(header: Text("Salvar como"),
                        footer: Text("O projeto vai para Projetos e continua ligado ao GitHub: dá para editar, e enviar com git commit e git push.")) {
                    Picker("Tipo", selection: $lang) {
                        ForEach(Lang.allCases) { l in Text(l.title).tag(l) }
                    }
                    TextField("nome da pasta", text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section {
                    Button(busy ? "Baixando…" : "Baixar para o aparelho") { start() }
                        .disabled(busy || done || clean(name).isEmpty)
                }
                if !log.isEmpty {
                    Section { Text(log).font(.system(.footnote, design: .monospaced)) }
                }
                if done {
                    Section {
                        Button("Ver em Projetos") {
                            app.select(.home)
                            pm.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Baixar projeto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
        }
    }
}
