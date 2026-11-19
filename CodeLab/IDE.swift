import SwiftUI

extension FolderItem {
    static func list(_ dir: URL) -> [FolderItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [FolderItem] = []
        for n in names {
            if n == ".codelab" || n == ".git" || n == ".DS_Store" { continue }
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path, isDirectory: &d)
            out.append(FolderItem(name: n, isDir: d.boolValue))
        }
        return out.sorted { x, y in
            if x.isDir != y.isDir { return x.isDir }
            return x.name.lowercased() < y.name.lowercased()
        }
    }
}

struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    let initial: String
    let action: (String) -> Void
}

struct NameSheet: View {
    let p: NamePrompt
    @Environment(\.presentationMode) var pm
    @State private var name = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("nome", text: $name)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .navigationTitle(p.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancelar") { pm.wrappedValue.dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { p.action(n) }
                        pm.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear { name = p.initial }
    }
}

struct TreeRow: Identifiable {
    let url: URL
    let item: FolderItem
    let depth: Int
    var id: String { url.path }
}

/// Navegador de arquivos: modo "ícones" (como o app Arquivos) ou modo "árvore" (como o Android Studio).
/// Segurar em cima de um item abre as opções (abrir, renomear, duplicar, apagar…).
struct FileBrowser: View {
    let root: URL
    let current: URL?
    let onOpen: (URL) -> Void
    let onRemoved: (URL) -> Void
    let onRenamed: (URL, URL) -> Void

    @Environment(\.presentationMode) var pm
    @AppStorage("fileBrowserTree") private var tree = false
    @State private var path: URL
    @State private var expanded: Set<String> = []
    @State private var tick = 0
    @State private var prompt: NamePrompt? = nil
    @State private var toDelete: URL? = nil

    init(root: URL, current: URL?, onOpen: @escaping (URL) -> Void,
         onRemoved: @escaping (URL) -> Void, onRenamed: @escaping (URL, URL) -> Void) {
        self.root = root
        self.current = current
        self.onOpen = onOpen
        self.onRemoved = onRemoved
        self.onRenamed = onRenamed
        _path = State(initialValue: root)
    }

    let fm = FileManager.default

    func items(_ d: URL) -> [FolderItem] {
        _ = tick
        return FolderItem.list(d)
    }

    func count(_ d: URL) -> Int {
        ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).count
    }

    var atRoot: Bool { path.standardizedFileURL.path == root.standardizedFileURL.path }

    // MARK: ações

    func ask(newIn d: URL, folder: Bool) {
        prompt = NamePrompt(title: folder ? "Nova pasta" : "Novo arquivo", initial: "") { n in
            let u = d.appendingPathComponent(n)
            if folder {
                try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            } else {
                try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) }
            }
            expanded.insert(d.path)
            tick += 1
        }
    }

    func rename(_ u: URL) {
        prompt = NamePrompt(title: "Renomear", initial: u.lastPathComponent) { n in
            let nu = u.deletingLastPathComponent().appendingPathComponent(n)
            if (try? fm.moveItem(at: u, to: nu)) != nil { onRenamed(u, nu) }
            tick += 1
        }
    }

    func duplicate(_ u: URL) {
        let base = u.deletingPathExtension().lastPathComponent
        let ext = u.pathExtension
        var i = 1
        var nu = u
        repeat {
            let nm = base + "-copia" + (i > 1 ? String(i) : "") + (ext.isEmpty ? "" : "." + ext)
            nu = u.deletingLastPathComponent().appendingPathComponent(nm)
            i += 1
        } while fm.fileExists(atPath: nu.path)
        try? fm.copyItem(at: u, to: nu)
        tick += 1
    }

    func tap(_ it: FolderItem, _ u: URL) {
        if it.isDir {
            if tree {
                if expanded.contains(u.path) { expanded.remove(u.path) } else { expanded.insert(u.path) }
            } else {
                path = u
            }
        } else {
            onOpen(u)
            pm.wrappedValue.dismiss()
        }
    }

    @ViewBuilder func menu(_ it: FolderItem, _ u: URL) -> some View {
        if it.isDir {
            Button { ask(newIn: u, folder: false) } label: { Label("Novo arquivo aqui", systemImage: "doc.badge.plus") }
            Button { ask(newIn: u, folder: true) } label: { Label("Nova pasta aqui", systemImage: "folder.badge.plus") }
        } else {
            Button { onOpen(u); pm.wrappedValue.dismiss() } label: { Label("Abrir", systemImage: "doc.text") }
        }
        Button { rename(u) } label: { Label("Renomear", systemImage: "pencil") }
        Button { duplicate(u) } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { toDelete = u } label: { Label("Apagar", systemImage: "trash") }
    }

    // MARK: modo ícones

    func cell(_ it: FolderItem) -> some View {
        let u = path.appendingPathComponent(it.name)
        return VStack(spacing: 4) {
            if it.isDir {
                Image(systemName: "folder.fill")
                    .font(.system(size: 52))
                    .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.98))
            } else {
                ZStack {
                    Image(systemName: "doc.fill").font(.system(size: 46)).foregroundColor(Color(.systemGray4))
                    Text(u.pathExtension.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .offset(y: 8)
                }
            }
            Text(it.name).font(.footnote).lineLimit(2).multilineTextAlignment(.center)
            if it.isDir {
                Text(String(count(u)) + " itens").font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(current == u ? Color.blue.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { tap(it, u) }
        .contextMenu { menu(it, u) }
    }

    var gridView: some View {
        ScrollView {
            if !atRoot {
                HStack {
                    Button { path = path.deletingLastPathComponent() } label: { Label("Voltar", systemImage: "chevron.left") }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            let list = items(path)
            if list.isEmpty {
                Text("Pasta vazia. Toque em + para criar.").font(.footnote).foregroundColor(.secondary).padding(.top, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 14) {
                ForEach(list) { it in cell(it) }
            }
            .padding()
        }
    }

    // MARK: modo árvore

    func rows(_ d: URL, _ depth: Int) -> [TreeRow] {
        var out: [TreeRow] = []
        for it in items(d) {
            let u = d.appendingPathComponent(it.name)
            out.append(TreeRow(url: u, item: it, depth: depth))
            if it.isDir && expanded.contains(u.path) { out += rows(u, depth + 1) }
        }
        return out
    }

    func treeRow(_ r: TreeRow) -> some View {
        HStack(spacing: 6) {
            if r.item.isDir {
                Image(systemName: expanded.contains(r.url.path) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }
            Image(systemName: r.item.isDir ? "folder.fill" : "doc.text")
                .foregroundColor(r.item.isDir ? Color(red: 0.45, green: 0.65, blue: 0.95) : Color.secondary)
            Text(r.item.name).font(.system(size: 15)).lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(r.depth) * 14)
        .contentShape(Rectangle())
        .onTapGesture { tap(r.item, r.url) }
        .contextMenu { menu(r.item, r.url) }
        .listRowBackground(current == r.url ? Color.blue.opacity(0.15) : Color.clear)
    }

    var treeView: some View {
        List {
            ForEach(rows(root, 0)) { r in treeRow(r) }
        }
        .listStyle(.plain)
    }

    var body: some View {
        NavigationView {
            Group {
                if tree { treeView } else { gridView }
            }
            .navigationTitle(tree || atRoot ? root.lastPathComponent : path.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Fechar") { pm.wrappedValue.dismiss() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { tree.toggle() } label: {
                        Image(systemName: tree ? "square.grid.2x2" : "list.bullet.indent")
                    }
                    Menu {
                        Button("Novo arquivo") { ask(newIn: tree ? root : path, folder: false) }
                        Button("Nova pasta") { ask(newIn: tree ? root : path, folder: true) }
                    } label: { Image(systemName: "plus") }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $prompt) { p in NameSheet(p: p) }
        .confirmationDialog(
            "Apagar este item?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible,
            presenting: toDelete
        ) { u in
            Button("Apagar " + u.lastPathComponent, role: .destructive) {
                try? fm.removeItem(at: u)
                onRemoved(u)
                tick += 1
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

/// Tela principal do projeto: o código ocupa a tela; os arquivos ficam num botão.
struct IDEView: View {
    let lang: Lang
    let name: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    @State private var current: URL? = nil
    @State private var openFiles: [URL] = []
    @State private var text = ""
    @State private var showFiles = false
    @State private var showTools = false
    @State private var showOut = false
    @State private var output = ""
    @State private var showSearch = false
    @State private var shareItem: ShareItem? = nil
    @State private var jump: JumpRequest? = nil
    @State private var line = 1
    @State private var col = 1
    @State private var dirty = false
    @State private var saveTask: Task<Void, Never>? = nil

    var dir: URL { store.dir(lang, name) }
    var ext: String { current?.pathExtension.lowercased() ?? "" }
    var issues: [Issue] { current == nil ? [] : Linter.check(text, ext: ext) }

    func read(_ u: URL) -> String { (try? String(contentsOf: u)) ?? "" }

    func save() {
        if let c = current, FileManager.default.fileExists(atPath: c.path) {
            try? text.write(to: c, atomically: true, encoding: .utf8)
        }
        dirty = false
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { save() }
        }
    }

    func open(_ u: URL, line l: Int? = nil) {
        if current?.path != u.path {
            save()
            current = u
            text = read(u)
            dirty = false
        }
        if !openFiles.contains(where: { $0.path == u.path }) { openFiles.append(u) }
        if let l = l { jump = JumpRequest(line: l) }
    }

    func close(_ u: URL) {
        if current?.path == u.path { save() }
        openFiles.removeAll { $0.path == u.path }
        if current?.path == u.path {
            if let n = openFiles.last { current = n; text = read(n) } else { current = nil; text = "" }
        }
    }

    func defaultFile() -> URL? {
        let all = Store.files(in: dir)
        let prefs = ["main.cpp", "Main.java", "main.gd", "MainActivity.java", "MainActivity.kt", "App.swift"]
        for p in prefs {
            if let f = all.first(where: { ($0 as NSString).lastPathComponent == p }) { return dir.appendingPathComponent(f) }
        }
        if let f = all.first(where: { !$0.hasPrefix(".") }) { return dir.appendingPathComponent(f) }
        return nil
    }

    func exportZip() {
        save()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".zip")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try ZipWriter.create(dir: dir, to: tmp, prefix: name)
            shareItem = ShareItem(url: tmp)
        } catch {
            output = "Erro ao exportar: " + error.localizedDescription
            showOut = true
        }
    }

    func runLocal() {
        save()
        let exts = lang == .java ? ["java"] : ["c", "cpp", "cc", "cxx"]
        var src = ""
        for f in Store.files(in: dir) where exts.contains((f as NSString).pathExtension.lowercased()) {
            src += read(dir.appendingPathComponent(f)) + "\n"
        }
        output = Interp(java: lang == .java).run(src)
        showOut = true
    }

    var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(openFiles, id: \.path) { f in
                    HStack(spacing: 6) {
                        Text(f.lastPathComponent).font(.footnote).lineLimit(1)
                        Button { close(f) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(f.path == current?.path ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .onTapGesture { open(f) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    var statusBar: some View {
        HStack {
            Text("Ln " + String(line) + ", Col " + String(col))
            Spacer()
            Text(dirty ? "Editando…" : "Salvo ✓")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            if openFiles.count > 1 { tabStrip }
            if current != nil {
                CodeEditor(text: $text, ext: ext,
                           onCursor: { l, c in line = l; col = c },
                           jump: jump,
                           onJumped: { jump = nil })
                    .id(current)
                Divider()
                statusBar
                if !issues.isEmpty {
                    List(issues) { i in
                        Button { jump = JumpRequest(line: i.line) } label: {
                            Text("linha \(i.line): \(i.msg)").font(.footnote).foregroundColor(.primary)
                        }
                    }
                    .frame(height: 110)
                }
            } else {
                Spacer()
                Text("Nenhum arquivo aberto").foregroundColor(.secondary)
                Button("Abrir arquivos") { showFiles = true }.padding()
                Spacer()
            }
        }
        .navigationTitle(current?.lastPathComponent ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if lang == .cpp || lang == .java {
                    Button { runLocal() } label: { Image(systemName: "play.fill") }
                }
                Button { save(); showFiles = true } label: { Image(systemName: "folder") }
                Menu {
                    Button("Salvar") { save() }
                    Button("Buscar no projeto") { save(); showSearch = true }
                    Button("Exportar projeto (.zip)") { exportZip() }
                    Button("Corrigir erros") { text = Linter.fix(text, issues, ext: ext) }
                    Button("GitHub e ferramentas") { save(); showTools = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .background(
            NavigationLink(destination: ProjectView(lang: lang, name: name), isActive: $showTools) { EmptyView() }
        )
        .onChange(of: text) { _ in
            if current != nil {
                dirty = true
                scheduleSave()
            }
        }
        .onAppear {
            app.coding = true
            Recents.add(lang, name)
            if current == nil, let f = defaultFile() { open(f) }
        }
        .onDisappear { save(); app.coding = false }
        .sheet(isPresented: $showFiles) {
            FileBrowser(
                root: dir,
                current: current,
                onOpen: { u in open(u) },
                onRemoved: { u in
                    openFiles.removeAll { $0.path == u.path || $0.path.hasPrefix(u.path + "/") }
                    if let c = current, c.path == u.path || c.path.hasPrefix(u.path + "/") {
                        if let n = openFiles.last { current = n; text = read(n) } else { current = nil; text = "" }
                    }
                },
                onRenamed: { old, new in
                    func fix(_ x: URL) -> URL {
                        if x.path == old.path { return new }
                        if x.path.hasPrefix(old.path + "/") {
                            return URL(fileURLWithPath: new.path + String(x.path.dropFirst(old.path.count)))
                        }
                        return x
                    }
                    openFiles = openFiles.map(fix)
                    if let c = current { current = fix(c) }
                }
            )
        }
        .sheet(isPresented: $showSearch) {
            ProjectSearchView(dir: dir) { u, l in open(u, line: l) }
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(isPresented: $showOut) {
            NavigationView {
                ScrollView {
                    Text(output)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("Resultado")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { showOut = false } } }
            }
        }
    }
}
