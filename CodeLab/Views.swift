import SwiftUI
import UniformTypeIdentifiers

struct Card: View {
    let icon: String
    let title: String
    let sub: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 30))
            Text(title).font(.headline)
            Text(sub).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

struct RootView: View {
    @StateObject private var gh = GitHub()
    @StateObject private var store = Store()
    @State private var showGH = false
    @State private var showZip = false
    @State private var showImporter = false
    @State private var importMsg = ""
    @State private var showImportMsg = false

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Lang.allCases) { l in
                        NavigationLink(destination: ProjectsView(lang: l)) {
                            Card(icon: l.icon, title: l.title, sub: l.hint)
                        }
                    }
                    NavigationLink(destination: TerminalView()) {
                        Card(icon: "terminal", title: "Terminal", sub: "git + comandos")
                    }
                }
                .padding()
            }
            .navigationTitle("CodeLab")
            .sheet(isPresented: $showZip) { ZipToGitView().environmentObject(gh) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showZip = true } label: { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(gh.user.map { "@" + $0 } ?? "Entrar no GitHub") { showGH = true }
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert("Abrir projeto", isPresented: $showImportMsg) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMsg)
        }
        .environmentObject(gh)
        .environmentObject(store)
        .sheet(isPresented: $showGH) { GitHubLoginView().environmentObject(gh) }
    }
}

struct GitHubLoginView: View {
    @EnvironmentObject var gh: GitHub
    @Environment(\.presentationMode) var pm
    @State private var token = ""
    @State private var msg = ""
    @State private var busy = false
    @State private var clientId = UserDefaults.standard.string(forKey: "gh_client_id") ?? ""
    @State private var showWeb = false

    var body: some View {
        NavigationView {
            Form {
                if let u = gh.user {
                    Section { Text("Conectado como @\(u)") }
                    Button("Sair") { gh.logout() }
                } else {
                    Section(header: Text("Entrar pelo site do GitHub"),
                            footer: Text("Uma vez só: github.com → Settings → Developer settings → OAuth Apps → New OAuth App (qualquer nome; Homepage e Callback: https://github.com). Marque 'Enable Device Flow', salve e cole aqui o Client ID. Depois é só tocar em Entrar: abre a página do GitHub dentro do app (email, senha e 2 etapas) e você cola o código copiado.")) {
                        TextField("Client ID do OAuth App", text: $clientId)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Button(busy ? "Aguardando autorização…" : "Entrar com GitHub") {
                            Task { @MainActor in
                                busy = true
                                msg = ""
                                defer { busy = false }
                                do { try await gh.loginDevice(clientId: clientId) }
                                catch { msg = error.localizedDescription }
                            }
                        }
                        .disabled(clientId.isEmpty || busy)
                        if let code = gh.userCode {
                            Text(code)
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                            Text("Código copiado. Cole na página do GitHub e autorize.").font(.footnote)
                            Button("Copiar código de novo") { UIPasteboard.general.string = code }
                            if let url = URL(string: gh.verifyURL) { Link("Abrir página do GitHub", destination: url) }
                        }
                    }
                    Section(header: Text("Ou com token de acesso pessoal"),
                            footer: Text("Crie em github.com → Settings → Developer settings → Personal access tokens (classic), marcando 'repo' e 'workflow'.")) {
                        SecureField("ghp_…", text: $token)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Button("Entrar com token") {
                            Task { @MainActor in
                                busy = true
                                msg = ""
                                defer { busy = false }
                                do { try await gh.login(token: token); token = "" }
                                catch { msg = error.localizedDescription }
                            }
                        }
                        .disabled(token.isEmpty || busy)
                    }
                    if !msg.isEmpty { Text(msg).foregroundColor(.red) }
                }
            }
            .navigationTitle("GitHub")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
        }
        .onChange(of: gh.userCode) { code in showWeb = (code != nil) }
        .sheet(isPresented: $showWeb) {
            if let code = gh.userCode, let url = URL(string: gh.verifyURL) {
                GitHubWebSheet(url: url, code: code)
            }
        }
    }
}

struct ProjectsView: View {
    let lang: Lang
    @EnvironmentObject var store: Store
    @State private var newName = ""
    @State private var items: [String] = []
    @State private var showImporter = false
    @State private var importMsg = ""
    @State private var showImportMsg = false
    @State private var kotlin = false
    @State private var minSdk = 24

    static let sdks: [(Int, String)] = [(21, "5.0"), (23, "6.0"), (24, "7.0"), (26, "8.0"), (28, "9"),
                                        (29, "10"), (30, "11"), (31, "12"), (33, "13"), (34, "14")]

    var body: some View {
        List {
            Section(header: Text("Novo projeto")) {
                if lang == .android {
                    Picker("Linguagem", selection: $kotlin) {
                        Text("Java").tag(false)
                        Text("Kotlin").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Compatível a partir do", selection: $minSdk) {
                        ForEach(ProjectsView.sdks, id: \.0) { sdk in
                            Text("Android " + sdk.1 + " (API " + String(sdk.0) + ")").tag(sdk.0)
                        }
                    }
                }
                HStack {
                    TextField("nome (sem espaços)", text: $newName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Criar") {
                        let n = Store.cleanName(newName)
                        if !n.isEmpty { store.create(lang, n, kotlin: kotlin, minSdk: minSdk); newName = ""; items = store.projects(lang) }
                    }
                }
                Button("Abrir projeto existente (.zip ou pasta)") { showImporter = true }
            }
            Section(header: Text("Projetos"), footer: Text("Dica: você também pode copiar pastas direto no app Arquivos → No meu iPhone → CodeLab → Projects → \(lang.rawValue).")) {
                ForEach(items, id: \.self) { n in
                    NavigationLink(n, destination: IDEView(lang: lang, name: n))
                }
                .onDelete { idx in
                    for i in idx { store.delete(lang, items[i]) }
                    items = store.projects(lang)
                }
            }
        }
        .navigationTitle(lang.title)
        .onAppear { items = store.projects(lang) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip, .folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first {
                    do {
                        let (_, n) = try Importer.importItem(u, lang: lang)
                        importMsg = "Projeto \"\(n)\" importado."
                        items = store.projects(lang)
                    } catch {
                        importMsg = error.localizedDescription
                    }
                    showImportMsg = true
                }
            case .failure(let e):
                importMsg = e.localizedDescription
                showImportMsg = true
            }
        }
        .alert("Abrir projeto", isPresented: $showImportMsg) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMsg)
        }
    }
}

struct ProjectView: View {
    let lang: Lang
    let name: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var gh: GitHub
    @State private var refresh = UUID()
    @State private var repo = ""
    @State private var busy = false
    @State private var showLog = false

    var dir: URL { store.dir(lang, name) }
    var repoKey: String { "repo-\(lang.rawValue)-\(name)" }

    func perform(_ job: @escaping @MainActor () async throws -> Void) {
        UserDefaults.standard.set(repo, forKey: repoKey)
        Task {
            busy = true
            showLog = true
            gh.log = ""
            defer { busy = false }
            do { try await job() }
            catch { gh.add("ERRO: " + error.localizedDescription) }
        }
    }

    func runLocal() {
        let exts = lang == .java ? ["java"] : ["c", "cpp", "cc", "cxx"]
        var src = ""
        for f in Store.files(in: dir) where exts.contains((f as NSString).pathExtension.lowercased()) {
            src += ((try? String(contentsOf: dir.appendingPathComponent(f))) ?? "") + "\n"
        }
        gh.log = Interp(java: lang == .java).run(src)
        showLog = true
    }

    var body: some View {
        List {
            if lang == .cpp || lang == .java {
                Section(header: Text("Executar"), footer: Text("Roda no próprio aparelho, sem GitHub. Suporta variáveis, if/while/for, funções, printf/cout/System.out. Ainda sem arrays, classes com objetos e entrada de dados.")) {
                    Button("▶︎ Executar (no aparelho)") { runLocal() }
                }
            }
            Section(header: Text("GitHub"), footer: Text("Executar envia o projeto (git add + commit + push), roda o workflow no GitHub e mostra a saída aqui. Para Android/iOS, o APK/IPA é baixado para Arquivos → CodeLab → Downloads.")) {
                TextField("repositório (usuario/nome ou só o nome)", text: $repo)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Enviar pro GitHub (add + commit + push)") {
                    perform {
                        _ = try await gh.syncAndPush(dir: dir, repo: repo, say: { gh.add($0) })
                        refresh = UUID()
                    }
                }
                .disabled(repo.isEmpty || busy)
                Button("Baixar do GitHub (pull)") {
                    perform {
                        Repo.initRepo(dir)
                        var s = Repo.load(dir)
                        if s.remote.isEmpty {
                            guard let slug = Repo.normalize(repo, user: gh.user) else { throw GHError(msg: "Nome de repositório inválido.") }
                            s.remote = slug
                            Repo.save(s, dir)
                        }
                        try await gh.pull(root: dir, say: { gh.add($0) })
                        refresh = UUID()
                    }
                }
                .disabled(repo.isEmpty || busy)
                if lang != .cpp && lang != .java {
                Button(lang == .android ? "Montar APK" : lang == .ios ? "Montar IPA" : "Executar / compilar") {
                    perform {
                        let slug = try await gh.syncAndPush(dir: dir, repo: repo, say: { gh.add($0) })
                        let br = Repo.load(dir).branch
                        let r = try await gh.runWorkflow(slug: slug, branch: br, say: { gh.add($0) })
                        gh.add(GitHub.describe(r))
                    }
                }
                .disabled(repo.isEmpty || busy)
                }
            }
            Section(header: Text("Terminal")) {
                NavigationLink("Abrir terminal nesta pasta", destination: TerminalView(start: dir))
            }
        }
        .navigationTitle("Ferramentas")
        .onAppear {
            let saved = Repo.load(dir).remote
            repo = saved.isEmpty ? (UserDefaults.standard.string(forKey: repoKey) ?? name) : saved
        }
        .sheet(isPresented: $showLog) {
            NavigationView {
                ScrollView {
                    Text(gh.log)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle(busy ? "Trabalhando…" : "Resultado")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { showLog = false } } }
            }
        }
    }
}

struct EditorView: View {
    let url: URL
    @State private var text = ""
    var ext: String { url.pathExtension.lowercased() }
    var issues: [Issue] { Linter.check(text, ext: ext) }

    var body: some View {
        VStack(spacing: 0) {
            CodeEditor(text: $text, ext: ext)
            Divider()
            if issues.isEmpty {
                Text("✓ nenhum problema encontrado").font(.footnote).padding(8)
            } else {
                List(issues) { i in
                    Text("linha \(i.line): \(i.msg)").font(.footnote)
                }
                .frame(height: 130)
            }
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Corrigir") { text = Linter.fix(text, issues, ext: ext) }
                Button("Salvar") { try? text.write(to: url, atomically: true, encoding: .utf8) }
            }
        }
        .onAppear { text = (try? String(contentsOf: url)) ?? "" }
        .onDisappear { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}

struct FolderItem: Identifiable {
    let name: String
    let isDir: Bool
    var id: String { name }
}

/// Lista de pastas e arquivos de uma pasta, no estilo do app Arquivos do iOS.
struct FolderListSection: View {
    let dir: URL
    @State private var items: [FolderItem] = []
    @State private var newName = ""

    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var list: [FolderItem] = []
        for n in names {
            if n == ".codelab" || n == ".git" || n == ".DS_Store" { continue }
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path, isDirectory: &d)
            list.append(FolderItem(name: n, isDir: d.boolValue))
        }
        items = list.sorted { x, y in
            if x.isDir != y.isDir { return x.isDir }
            return x.name.lowercased() < y.name.lowercased()
        }
    }

    func create(folder: Bool) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let u = dir.appendingPathComponent(n)
        if folder {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        } else {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) }
        }
        newName = ""
        reload()
    }

    var body: some View {
        Section(header: Text(dir.lastPathComponent)) {
            ForEach(items) { it in
                if it.isDir {
                    NavigationLink(destination: FolderView(dir: dir.appendingPathComponent(it.name))) {
                        Label(it.name, systemImage: "folder")
                    }
                } else {
                    NavigationLink(destination: EditorView(url: dir.appendingPathComponent(it.name))) {
                        Label(it.name, systemImage: "doc.text")
                    }
                }
            }
            .onDelete { idx in
                for i in idx { try? FileManager.default.removeItem(at: dir.appendingPathComponent(items[i].name)) }
                reload()
            }
            HStack {
                TextField("nome (ex: util.cpp ou src)", text: $newName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Menu("Novo") {
                    Button("Arquivo") { create(folder: false) }
                    Button("Pasta") { create(folder: true) }
                }
            }
        }
        .onAppear { reload() }
    }
}

struct FolderView: View {
    let dir: URL
    var body: some View {
        List { FolderListSection(dir: dir) }
            .navigationTitle(dir.lastPathComponent)
    }
}
