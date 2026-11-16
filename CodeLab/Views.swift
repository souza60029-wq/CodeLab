import SwiftUI

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
                        Card(icon: "terminal", title: "Terminal", sub: "Comandos locais")
                    }
                }
                .padding()
            }
            .navigationTitle("CodeLab")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(gh.user.map { "@" + $0 } ?? "Entrar no GitHub") { showGH = true }
                }
            }
        }
        .navigationViewStyle(.stack)
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

    func clean(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    }

    var body: some View {
        List {
            Section(header: Text("Novo projeto")) {
                HStack {
                    TextField("nome (sem espaços)", text: $newName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Criar") {
                        let n = clean(newName)
                        if !n.isEmpty { store.create(lang, n); newName = ""; items = store.projects(lang) }
                    }
                }
            }
            Section(header: Text("Projetos")) {
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

    var body: some View {
        List {
            Section(header: Text("Arquivos")) {
                ForEach(files, id: \.self) { f in
                    NavigationLink(f, destination: EditorView(url: dir.appendingPathComponent(f)))
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
            Section(header: Text("GitHub"), footer: Text("Executar envia o projeto, roda o workflow no GitHub e mostra o resultado. Para Android/iOS, o APK/IPA fica em Artifacts na página da execução.")) {
                TextField("repositório", text: $repo)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Enviar pro GitHub") {
                    UserDefaults.standard.set(repo, forKey: repoKey)
                    Task {
                        busy = true; showLog = true
                        defer { busy = false }
                        do { _ = try await gh.push(dir: dir, repo: repo) }
                        catch { gh.log = error.localizedDescription }
                    }
                }
                .disabled(repo.isEmpty || busy)
                Button(lang == .android ? "Montar APK" : lang == .ios ? "Montar IPA" : "Executar / compilar") {
                    UserDefaults.standard.set(repo, forKey: repoKey)
                    Task {
                        busy = true; showLog = true
                        defer { busy = false }
                        do { try await gh.runAndWait(dir: dir, repo: repo) }
                        catch { gh.log = error.localizedDescription }
                    }
                }
                .disabled(repo.isEmpty || busy)
            }
        }
        .navigationTitle(name)
        .onAppear {
            files = Store.files(in: dir)
            repo = UserDefaults.standard.string(forKey: repoKey) ?? name
        }
        .sheet(isPresented: $showLog) {
            NavigationView {
                ScrollView {
                    Text(gh.log)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
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
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 4)
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
