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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(gh.user.map { "@" + $0 } ?? "Entrar no GitHub") { showGH = true }
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip, .folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first {
                    do {
                        let (l, n) = try Importer.importItem(u, lang: nil)
                        importMsg = "Projeto \"\(n)\" importado em \(l.title)."
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

    var body: some View {
        NavigationView {
            Form {
                if let u = gh.user {
                    Section { Text("Conectado como @\(u)") }
                    Button("Sair") { gh.logout() }
                } else {
                    Section(header: Text("Token de acesso pessoal"),
                            footer: Text("Crie em github.com → Settings → Developer settings → Personal access tokens (classic), marcando 'repo' e 'workflow'.")) {
                        SecureField("ghp_…", text: $token)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    Button(busy ? "Entrando…" : "Entrar") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do { try await gh.login(token: token); token = ""; msg = "" }
                            catch { msg = error.localizedDescription }
                        }
                    }
                    .disabled(token.isEmpty || busy)
                    if !msg.isEmpty { Text(msg).foregroundColor(.red) }
                }
            }
            .navigationTitle("GitHub")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
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

    var body: some View {
        List {
            Section(header: Text("Novo projeto")) {
                HStack {
                    TextField("nome (sem espaços)", text: $newName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Criar") {
                        let n = Store.cleanName(newName)
                        if !n.isEmpty { store.create(lang, n); newName = ""; items = store.projects(lang) }
                    }
                }
                Button("Abrir projeto existente (.zip ou pasta)") { showImporter = true }
            }
            Section(header: Text("Projetos"), footer: Text("Dica: você também pode copiar pastas direto no app Arquivos → No meu iPhone → CodeLab → Projects → \(lang.rawValue).")) {
                ForEach(items, id: \.self) { n in
                    NavigationLink(n, destination: ProjectView(lang: lang, name: n))
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
    @State private var files: [String] = []
    @State private var newFile = ""
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

    var body: some View {
        List {
            Section(header: Text("Arquivos")) {
                ForEach(files, id: \.self) { f in
                    NavigationLink(f, destination: EditorView(url: dir.appendingPathComponent(f)))
                }
                .onDelete { idx in
                    for i in idx { try? FileManager.default.removeItem(at: dir.appendingPathComponent(files[i])) }
                    files = Store.files(in: dir)
                }
                HStack {
                    TextField("novo arquivo (ex: util.cpp)", text: $newFile)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Criar") {
                        let n = newFile.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty {
                            let u = dir.appendingPathComponent(n)
                            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                            if !FileManager.default.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) }
                            newFile = ""
                            files = Store.files(in: dir)
                        }
                    }
                }
            }
            Section(header: Text("GitHub"), footer: Text("Executar envia o projeto (git add + commit + push), roda o workflow no GitHub e mostra a saída aqui. Para Android/iOS, o APK/IPA é baixado para Arquivos → CodeLab → Downloads.")) {
                TextField("repositório (usuario/nome ou só o nome)", text: $repo)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Enviar pro GitHub (add + commit + push)") {
                    perform {
                        _ = try await gh.syncAndPush(dir: dir, repo: repo, say: { gh.add($0) })
                        files = Store.files(in: dir)
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
                        files = Store.files(in: dir)
                    }
                }
                .disabled(repo.isEmpty || busy)
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
            Section(header: Text("Terminal")) {
                NavigationLink("Abrir terminal nesta pasta", destination: TerminalView(start: dir))
            }
        }
        .navigationTitle(name)
        .onAppear {
            files = Store.files(in: dir)
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
