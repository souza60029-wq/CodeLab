import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Histórico

struct BuildRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let repo: String
    let ok: Bool
    let artifact: String?
    let runURL: String?
}

enum BuildHistory {
    static let key = "buildHistory"
    static func list() -> [BuildRecord] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let a = try? JSONDecoder().decode([BuildRecord].self, from: d) else { return [] }
        return a
    }
    static func add(_ r: BuildRecord) {
        var a = list()
        a.insert(r, at: 0)
        a = Array(a.prefix(10))
        if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
    static var downloads: URL {
        Store.root.deletingLastPathComponent().appendingPathComponent("Downloads")
    }
}

// MARK: - Fluxo: .zip → commit → build → resultado

@MainActor
final class BuildFlow: ObservableObject {
    enum State { case pending, active, done, failed }

    struct Step: Identifiable {
        let id: Int
        let title: String
        var state: State = .pending
        var detail: String = ""
    }

    @Published var steps: [Step] = []
    @Published var running = false
    @Published var started: Date? = nil
    @Published var finished = false
    @Published var success = false
    @Published var message = ""
    @Published var output = ""
    @Published var runURL: String? = nil
    @Published var artifact: URL? = nil

    func setup(build: Bool) {
        var list = [Step(id: 0, title: "Abrir o .zip"), Step(id: 1, title: "Enviar ao GitHub (1 commit)")]
        if build {
            list.append(Step(id: 2, title: "Iniciar o build"))
            list.append(Step(id: 3, title: "Compilar na nuvem"))
            list.append(Step(id: 4, title: "Baixar o resultado"))
        }
        steps = list
    }

    func mark(_ i: Int, _ st: State, _ detail: String? = nil) {
        guard let k = steps.firstIndex(where: { $0.id == i }) else { return }
        steps[k].state = st
        if let d = detail { steps[k].detail = d }
    }

    func activate(_ i: Int, _ detail: String = "") {
        for k in steps.indices where steps[k].id < i && steps[k].state != .done { steps[k].state = .done }
        mark(i, .active, detail)
    }

    func status(_ s: String) -> String {
        switch s {
        case "queued": return "Na fila do GitHub"
        case "in_progress": return "Compilando…"
        case "completed": return "Finalizando…"
        default: return s
        }
    }

    /// Traduz as mensagens do GitHub.swift em etapas.
    func hear(_ m: String) {
        if m.hasPrefix("Abrindo") {
            activate(0, "Lendo o arquivo…")
        } else if m.contains("arquivo(s) no .zip") {
            mark(0, .done, m)
            activate(1, "Preparando os arquivos…")
        } else if m.hasPrefix("Repositório") {
            mark(1, .active, m)
        } else if m.hasPrefix("Preparando") || m.hasPrefix("Montando") {
            mark(1, .active, m)
        } else if m.hasPrefix("✓ 1 commit") {
            mark(1, .done, m)
        } else if m.hasPrefix("Aguardando o GitHub") {
            activate(2, m)
        } else if m.hasPrefix("Workflow iniciado") {
            mark(2, .done, "Workflow disparado")
            activate(3, "Na fila do GitHub")
        } else if m.hasPrefix("Status:") {
            let st = m.replacingOccurrences(of: "Status: ", with: "")
            mark(3, .active, status(st))
        } else if m.hasPrefix("Baixando") {
            mark(3, .done, "Build concluído")
            activate(4, m)
        }
    }

    func finish(ok: Bool, _ msg: String, repo: String) {
        running = false
        finished = true
        success = ok
        message = msg
        UIApplication.shared.isIdleTimerDisabled = false
        UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
        BuildHistory.add(BuildRecord(date: Date(), repo: repo, ok: ok, artifact: artifact?.lastPathComponent, runURL: runURL))
    }

    func run(gh: GitHub, zip: URL, repo: String, branch: String, message msg: String, replaceAll: Bool, build: Bool) async {
        finished = false
        success = false
        message = ""
        output = ""
        runURL = nil
        artifact = nil
        setup(build: build)
        running = true
        started = Date()
        UIApplication.shared.isIdleTimerDisabled = true
        activate(0, "Abrindo…")
        do {
            let r = try await gh.zipToGit(zip: zip, repo: repo, branch: branch, message: msg,
                                          replaceAll: replaceAll, say: { self.hear($0) })
            mark(1, .done, "Commit enviado para " + r.slug + " (" + r.branch + ")")
            if !build {
                finish(ok: true, "Enviado para " + r.slug + " em um único commit.", repo: r.slug)
                return
            }
            activate(2, "Disparando o workflow…")
            let res = try await gh.runWorkflow(slug: r.slug, branch: r.branch, say: { self.hear($0) })
            runURL = res.url
            output = res.output
            if res.conclusion == "success" {
                for k in steps.indices { steps[k].state = .done }
                mark(3, .done, "Build concluído")
                mark(4, .done, res.saved.isEmpty ? "Este build não gerou arquivos" : res.saved.joined(separator: "\n"))
                artifact = gh.lastBuilt
                finish(ok: true, artifact == nil ? "Build concluído." : "Pronto! O arquivo já está no aparelho.", repo: r.slug)
            } else {
                mark(3, .failed, "Resultado: " + res.conclusion)
                finish(ok: false, "O build não passou. Veja a saída abaixo.", repo: r.slug)
            }
        } catch {
            if let k = steps.firstIndex(where: { $0.state == .active }) {
                steps[k].state = .failed
                steps[k].detail = error.localizedDescription
            }
            finish(ok: false, error.localizedDescription, repo: repo)
        }
    }
}

// MARK: - Aba Build

struct BuildView: View {
    @EnvironmentObject var gh: GitHub
    @EnvironmentObject var app: AppState
    @StateObject private var flow = BuildFlow()
    @State private var zipURL: URL? = nil
    @State private var showPicker = false
    @State private var repoFull = UserDefaults.standard.string(forKey: "zip2git_repo") ?? ""
    @State private var branch = "main"
    @State private var branches: [String] = ["main"]
    @State private var showRepos = false
    @State private var message = ""
    @State private var build = true
    @State private var replaceAll = false
    @State private var share: ShareItem? = nil
    @State private var history: [BuildRecord] = BuildHistory.list()

    var canStart: Bool {
        zipURL != nil && !repoFull.isEmpty && !flow.running && gh.user != nil
    }

    func start() {
        guard let z = zipURL else { return }
        UserDefaults.standard.set(repoFull, forKey: "zip2git_repo")
        Task { @MainActor in
            await flow.run(gh: gh, zip: z, repo: repoFull, branch: branch, message: message, replaceAll: replaceAll, build: build)
            history = BuildHistory.list()
        }
    }

    func sanitize(_ n: String) -> String {
        let mapped = n.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") ? String($0) : "-" }.joined()
        return mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }

    func loadBranches() async {
        guard !repoFull.isEmpty else { branches = ["main"]; return }
        var b = await gh.branches(of: repoFull)
        b.removeAll { $0 == "main" }
        b.insert("main", at: 0)
        branches = b
        if !b.contains(branch) { branch = "main" }
    }

    @ViewBuilder func icon(_ s: BuildFlow.State) -> some View {
        switch s {
        case .pending: Image(systemName: "circle").foregroundColor(.secondary)
        case .active: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    func stepRow(_ st: BuildFlow.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(st.state).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(st.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(st.state == .pending ? .secondary : .primary)
                if !st.detail.isEmpty {
                    Text(st.detail).font(.caption).foregroundColor(.secondary).lineLimit(4)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func mmss(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        List {
            if gh.user == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Entre no GitHub para compilar.").font(.subheadline.weight(.semibold))
                        Text("O build roda no GitHub Actions, na sua conta.").font(.footnote).foregroundColor(.secondary)
                        Button("Ir para o Perfil") { app.select(.profile) }
                    }
                }
            }

            Section(header: Text("Origem")) {
                Button { showPicker = true } label: {
                    Label(zipURL?.lastPathComponent ?? "Escolher .zip…", systemImage: "doc.zipper")
                }
            }

            Section(header: Text("Destino"),
                    footer: Text("A conta é a que você já conectou. Se o repositório não existir, o CodeLab cria (privado) com esse único commit.")) {
                Button { showRepos = true } label: {
                    HStack {
                        Text("Repositório").foregroundColor(.primary)
                        Spacer()
                        Text(repoFull.isEmpty ? "Escolher…" : repoFull)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("Branch")
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
                            HStack(spacing: 4) {
                                Text(branch)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                            .foregroundColor(.accentColor)
                        }
                    } else {
                        Text(branch).foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Opções"),
                    footer: Text("Compilar roda o .github/workflows/build.yml do projeto (com on: workflow_dispatch) e traz o APK ou IPA de volta para o aparelho.")) {
                Toggle("Compilar e baixar o resultado", isOn: $build)
                DisclosureGroup("Avançado") {
                    TextField("mensagem do commit", text: $message)
                    Toggle("Apagar o que não está no .zip", isOn: $replaceAll)
                }
            }

            Section {
                Button(flow.running ? "Em andamento…" : (build ? "Enviar e compilar" : "Enviar")) { start() }
                    .disabled(!canStart)
            }

            if !flow.steps.isEmpty {
                Section(header: Text("Etapas")) {
                    ForEach(flow.steps) { st in stepRow(st) }
                    if flow.running, let t = flow.started {
                        TimelineView(.periodic(from: t, by: 1)) { ctx in
                            Text("Tempo: " + mmss(ctx.date.timeIntervalSince(t)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if flow.finished {
                Section(header: Text("Resultado")) {
                    Text(flow.message)
                        .font(.subheadline)
                        .foregroundColor(flow.success ? .green : .red)
                    if let a = flow.artifact {
                        Button { share = ShareItem(url: a) } label: {
                            Label("Instalar / compartilhar " + a.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                    }
                    if let u = flow.runURL, let url = URL(string: u) {
                        Link(destination: url) { Label("Abrir execução no GitHub", systemImage: "safari") }
                    }
                    if !flow.output.isEmpty {
                        DisclosureGroup("Saída do build") {
                            Text(flow.output)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !history.isEmpty {
                Section(header: Text("Histórico")) {
                    ForEach(history) { r in
                        HStack(spacing: 10) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(r.ok ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.repo).font(.subheadline)
                                Text(date(r.date) + (r.artifact.map { " · " + $0 } ?? ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let name = r.artifact {
                                let f = BuildHistory.downloads.appendingPathComponent(name)
                                if FileManager.default.fileExists(atPath: f.path) {
                                    Button { share = ShareItem(url: f) } label: { Image(systemName: "square.and.arrow.up") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    Button("Limpar histórico", role: .destructive) {
                        BuildHistory.clear()
                        history = []
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .dockInset()
        .navigationTitle("Build")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            ZipPicker { url in
                zipURL = url
                if repoFull.isEmpty, let u = gh.user {
                    repoFull = u + "/" + sanitize(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        .sheet(isPresented: $showRepos) {
            RepoPickerView(current: repoFull) { picked in repoFull = picked }.environmentObject(gh)
        }
        .onChange(of: repoFull) { v in
            UserDefaults.standard.set(v, forKey: "zip2git_repo")
            Task { await loadBranches() }
        }
        .onAppear {
            if !repoFull.isEmpty && !repoFull.contains("/"), let u = gh.user { repoFull = u + "/" + repoFull }
            Task { await loadBranches() }
        }
        .sheet(item: $share) { item in ShareSheet(items: [item.url]) }
    }
}

// MARK: - Seletor de .zip

/// Seletor de arquivos nativo (UIDocumentPicker). Copia o .zip para dentro do app ao escolher.
struct ZipPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [UTType.zip, UTType(filenameExtension: "zip")].compactMap { $0 }
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}

// MARK: - Favoritos

enum Favorites {
    static let key = "favRepos"
    static func list() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func toggle(_ slug: String) {
        var a = list()
        if let i = a.firstIndex(of: slug) { a.remove(at: i) } else { a.append(slug) }
        UserDefaults.standard.set(a, forKey: key)
    }
}

// MARK: - Escolher repositório

struct RepoPickerView: View {
    @EnvironmentObject var gh: GitHub
    @Environment(\.presentationMode) var pm
    let current: String
    let onPick: (String) -> Void
    @State private var query = ""
    @State private var favs: [String] = Favorites.list()
    @State private var loading = false

    var filtered: [GHRepo] {
        let q = query.lowercased()
        return gh.allRepos.filter { q.isEmpty || $0.fullName.lowercased().contains(q) }
    }
    var favRepos: [GHRepo] { filtered.filter { favs.contains($0.fullName) } }
    var others: [GHRepo] { filtered.filter { !favs.contains($0.fullName) } }

    var newName: String {
        let n = query.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n.contains("/") { return "" }
        return String(n.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") ? $0 : "-" })
    }

    func pick(_ slug: String) {
        onPick(slug)
        pm.wrappedValue.dismiss()
    }

    func row(_ r: GHRepo) -> some View {
        let fav = favs.contains(r.fullName)
        return Button { pick(r.fullName) } label: {
            HStack(spacing: 8) {
                if fav {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                        .frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).foregroundColor(.primary)
                    if let l = r.language {
                        Text(l).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if r.isPrivate { Image(systemName: "lock").font(.caption).foregroundColor(.secondary) }
                if r.fullName == current { Image(systemName: "checkmark").foregroundColor(.accentColor) }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Favorites.toggle(r.fullName)
                favs = Favorites.list()
            } label: {
                Label(fav ? "Desfavoritar" : "Favoritar", systemImage: fav ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                Favorites.toggle(r.fullName)
                favs = Favorites.list()
            } label: {
                Label(fav ? "Desfavoritar" : "Favoritar", systemImage: fav ? "star.slash" : "star")
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                if !newName.isEmpty, let u = gh.user,
                   !gh.allRepos.contains(where: { $0.fullName.lowercased() == (u + "/" + newName).lowercased() }) {
                    Section {
                        Button { pick(u + "/" + newName) } label: {
                            Label("Criar novo: " + u + "/" + newName, systemImage: "plus.circle")
                        }
                    }
                }
                if !favRepos.isEmpty {
                    Section(header: Text("Favoritos")) {
                        ForEach(favRepos) { r in row(r) }
                    }
                }
                Section(header: Text("Repositórios"),
                        footer: Text("Deslize um repositório para a direita (ou segure) para favoritar.")) {
                    if loading && gh.allRepos.isEmpty {
                        HStack { ProgressView(); Text("Carregando…").foregroundColor(.secondary) }
                    }
                    ForEach(others) { r in row(r) }
                }
            }
            .searchable(text: $query, prompt: "Buscar ou criar")
            .navigationTitle("Repositório")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
            .task {
                loading = true
                await gh.loadAllRepos()
                loading = false
            }
        }
    }
}
