import SwiftUI
import UIKit

// MARK: - Preferências

@MainActor
enum Haptics {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static func tap() {
        light.impactOccurred()
        light.prepare()
    }
}

enum Prefs {
    static var tabBlur: Bool { UserDefaults.standard.object(forKey: "tabBlur") as? Bool ?? true }
    static var glassPill: Bool { UserDefaults.standard.object(forKey: "glassPill") as? Bool ?? true }
    static var elastic: Bool { UserDefaults.standard.object(forKey: "elastic") as? Bool ?? true }
    static var fluid: Bool { UserDefaults.standard.object(forKey: "fluidAnimations") as? Bool ?? true }
    static var terminalTips: Bool { UserDefaults.standard.object(forKey: "terminalTips") as? Bool ?? false }
    static var autoPairs: Bool { UserDefaults.standard.object(forKey: "autoPairs") as? Bool ?? true }
    static var autoIndent: Bool { UserDefaults.standard.object(forKey: "autoIndent") as? Bool ?? true }
    static var tabWidth: Int {
        let v = UserDefaults.standard.integer(forKey: "tabWidth")
        return v == 0 ? 4 : v
    }
    static var editorFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "editorFontSize")
        return v < 8 ? 15 : CGFloat(v)
    }
}

struct RecentItem: Identifiable {
    let lang: Lang
    let name: String
    var id: String { lang.rawValue + "|" + name }
}

enum Recents {
    static func list() -> [String] { UserDefaults.standard.stringArray(forKey: "recents") ?? [] }
    static func add(_ l: Lang, _ n: String) {
        var a = list()
        let k = l.rawValue + "|" + n
        a.removeAll { $0 == k }
        a.insert(k, at: 0)
        UserDefaults.standard.set(Array(a.prefix(6)), forKey: "recents")
    }
}

// MARK: - Estado global do app

final class AppState: ObservableObject {
    enum Tab: Int, CaseIterable { case home, build, terminal, profile }

    @Published var tab: Tab = .home
    @Published var coding = false
    @Published var keyboard = false
    @Published var blurPhase: CGFloat = 0
    @Published var visited: Set<Tab> = [.home]

    var dockMini: Bool { coding && tab == .home }
    var dockVisible: Bool { !keyboard && !(dockMini && UserDefaults.standard.bool(forKey: "hideDockCoding")) }
    var dockHeight: CGFloat { dockVisible ? (dockMini ? 24 : 52) : 0 }

    /// Troca de aba. Com animações fluidas, usa mola e um borrão de movimento que cresce no meio da transição.
    func select(_ t: Tab) {
        guard t != tab else { return }
        visited.insert(t)
        if Prefs.fluid {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                tab = t
                blurPhase = blurPhase < 0.5 ? 1 : 0
            }
        } else {
            tab = t
        }
    }
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keyboard = true
        })
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keyboard = false
        })
        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            URLCache.shared.removeAllCachedResponses()
        })
    }
}

// MARK: - Efeitos

/// Borrão de movimento: o raio cresce no meio da transição e volta a zero no fim.
struct MotionBlur: ViewModifier, Animatable {
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func body(content: Content) -> some View {
        content.blur(radius: abs(sin(phase * .pi)) * 7)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && Prefs.fluid ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Prefs.fluid ? .spring(response: 0.25, dampingFraction: 0.6) : nil, value: configuration.isPressed)
    }
}

/// Deixa espaço para a barra inferior: o conteúdo sobe em vez de ficar escondido.
struct DockInset: ViewModifier {
    @EnvironmentObject var app: AppState
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: app.dockHeight)
        }
    }
}

extension View {
    func dockInset() -> some View { modifier(DockInset()) }
}

// MARK: - Raiz do app

struct RootView: View {
    @StateObject private var gh = GitHub()
    @StateObject private var store = Store()
    @StateObject private var app = AppState()

    func layer<V: View>(_ t: AppState.Tab, @ViewBuilder _ content: () -> V) -> some View {
        let sel = app.tab == t
        let dir: CGFloat = t.rawValue < app.tab.rawValue ? -1 : 1
        let fluid = Prefs.fluid
        return content()
            .opacity(sel ? 1 : 0)
            .offset(x: fluid && !sel ? dir * 28 : 0)
            .scaleEffect(fluid && !sel ? 0.98 : 1)
            .allowsHitTesting(sel)
            .accessibilityHidden(!sel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                layer(.home) { HomeView() }
                layer(.build) {
                    if app.visited.contains(.build) { NavigationView { BuildView() }.navigationViewStyle(.stack) }
                }
                layer(.terminal) {
                    if app.visited.contains(.terminal) { NavigationView { TerminalView() }.navigationViewStyle(.stack) }
                }
                layer(.profile) {
                    if app.visited.contains(.profile) { NavigationView { ProfileView() }.navigationViewStyle(.stack) }
                }
            }
            .modifier(MotionBlur(phase: Prefs.tabBlur ? app.blurPhase : 0))

            if app.dockVisible {
                DockView(mini: app.dockMini)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Prefs.fluid ? .spring(response: 0.38, dampingFraction: 0.82) : .easeInOut(duration: 0.2), value: app.dockVisible)
        .animation(Prefs.fluid ? .spring(response: 0.38, dampingFraction: 0.82) : .easeInOut(duration: 0.2), value: app.dockMini)
        .environmentObject(gh)
        .environmentObject(store)
        .environmentObject(app)
    }
}

// MARK: - Dock

/// Gota de vidro: azul translúcida, com brilho e borda em relevo. O que passa por baixo desfoca só nas bordas;
/// no centro dá para ver o ícone nitidamente.
struct GlassPill: View {
    let width: CGFloat
    let height: CGFloat
    let glass: Bool
    let stretch: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if glass {
                Capsule()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.07)],
                                         startPoint: .top, endPoint: .bottom))
                // borda de vidro: aqui o que passa por baixo fica desfocado
                Capsule()
                    .strokeBorder(.ultraThinMaterial, lineWidth: 9)
                // reflexo no topo
                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: height * 0.4)
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                // relevo
                Capsule()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.accentColor.opacity(0.35), Color.white.opacity(0.2)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1.2)
            } else {
                Capsule().fill(Color.accentColor.opacity(0.14))
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(x: 1, y: 1 - min(0.12, stretch / 180))
    }
}

struct DockView: View {
    let mini: Bool
    @EnvironmentObject var app: AppState
    @EnvironmentObject var gh: GitHub
    @AppStorage("blurEnabled") private var blur = true
    @State private var pillL: CGFloat = 0
    @State private var pillR: CGFloat = 0
    @State private var lastIndex = 0

    struct Entry {
        let tab: AppState.Tab
        let title: String
        let icon: String
        let iconSelected: String
    }

    let entries: [Entry] = [
        Entry(tab: .home, title: "Projetos", icon: "chevron.left.forwardslash.chevron.right", iconSelected: "chevron.left.forwardslash.chevron.right"),
        Entry(tab: .build, title: "Build", icon: "hammer", iconSelected: "hammer.fill"),
        Entry(tab: .terminal, title: "Terminal", icon: "terminal", iconSelected: "terminal.fill"),
        Entry(tab: .profile, title: "Perfil", icon: "person.crop.circle", iconSelected: "person.crop.circle.fill")
    ]

    let inset: CGFloat = 8

    /// Seleciona assim que o dedo encosta (sem esperar soltar).
    func select(_ t: AppState.Tab) {
        if app.tab != t { Haptics.tap() }
        app.select(t)
    }

    func place(_ idx: Int, width: CGFloat, animated: Bool) {
        let cw = width / CGFloat(entries.count)
        let tl = CGFloat(idx) * cw + inset
        let tr = CGFloat(idx + 1) * cw - inset
        if !animated || !Prefs.fluid {
            pillL = tl
            pillR = tr
            return
        }
        if !Prefs.elastic {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                pillL = tl
                pillR = tr
            }
            return
        }
        let fast = Animation.spring(response: 0.26, dampingFraction: 0.72)
        let slow = Animation.spring(response: 0.52, dampingFraction: 0.8)
        if idx > lastIndex {
            withAnimation(fast) { pillR = tr }
            withAnimation(slow.delay(0.03)) { pillL = tl }
        } else {
            withAnimation(fast) { pillL = tl }
            withAnimation(slow.delay(0.03)) { pillR = tr }
        }
    }

    func glyph(_ e: Entry, _ sel: Bool) -> some View {
        Group {
            if e.tab == .profile, let s = gh.avatarURL, let u = URL(string: s) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .overlay(Circle().stroke(sel ? Color.accentColor : Color.clear, lineWidth: 2))
            } else {
                Image(systemName: sel ? e.iconSelected : e.icon).font(.system(size: 22))
            }
        }
    }

    func cell(_ e: Entry) -> some View {
        let sel = app.tab == e.tab
        return Group {
            if mini {
                Image(systemName: sel ? e.iconSelected : e.icon).font(.system(size: 12, weight: .semibold))
            } else {
                VStack(spacing: 3) {
                    glyph(e, sel)
                    Text(e.title).font(.system(size: 10, weight: .medium))
                }
            }
        }
        .foregroundColor(sel ? .accentColor : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }

    /// Preta (ou branca, no modo claro) e só desfoca quando algo passa por trás.
    var bar: some View {
        ZStack {
            if blur {
                Rectangle().fill(.ultraThinMaterial)
                Color(.systemBackground).opacity(0.62)
            } else {
                Color(.systemBackground)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    var body: some View {
        GeometryReader { g in
            let cw = g.size.width / CGFloat(entries.count)
            let stretch = Prefs.elastic ? max(0, (pillR - pillL) - (cw - 2 * inset)) : 0
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(entries, id: \.title) { e in
                        cell(e)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in select(e.tab) })
                    }
                }
                if !mini {
                    GlassPill(width: max(8, pillR - pillL), height: 42, glass: Prefs.glassPill, stretch: stretch)
                        .offset(x: pillL)
                        .allowsHitTesting(false)
                    // o item atual aparece nítido por cima da gota; os que ela atravessa ficam desfocados nas bordas
                    let ti = app.tab.rawValue
                    let cellL = CGFloat(ti) * cw
                    let overlap = min(1, max(0, (min(pillR, cellL + cw) - max(pillL, cellL)) / max(1, cw - 2 * inset)))
                    cell(entries[ti])
                        .frame(width: cw, height: 52)
                        .offset(x: cellL)
                        .opacity(Double(overlap))
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                lastIndex = app.tab.rawValue
                place(lastIndex, width: g.size.width, animated: false)
            }
            .onChange(of: app.tab) { t in
                place(t.rawValue, width: g.size.width, animated: true)
                lastIndex = t.rawValue
            }
        }
        .frame(height: mini ? 24 : 52)
        .background(bar)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Início

struct HomeView: View {
    @EnvironmentObject var gh: GitHub
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    @State private var recents: [RecentItem] = []
    @State private var showClonePicker = false
    @State private var showDownload = false
    @State private var pendingSlug: String? = nil

    func loadRecents() {
        recents = Recents.list().compactMap { (s: String) -> RecentItem? in
            let p = s.components(separatedBy: "|")
            guard p.count == 2, let l = Lang(rawValue: p[0]) else { return nil }
            guard FileManager.default.fileExists(atPath: store.dir(l, p[1]).path) else { return nil }
            return RecentItem(lang: l, name: p[1])
        }
    }

    func recentRow(_ r: RecentItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.lang.icon).font(.system(size: 20)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.subheadline.weight(.semibold))
                Text(r.lang.title).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    var buildBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enviar .zip e compilar").font(.subheadline.weight(.semibold))
                Text("Acompanhe as etapas e receba o APK ou IPA").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    var downloadBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Baixar do GitHub").font(.subheadline.weight(.semibold))
                Text("Traga um dos seus repositórios para o aparelho").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Button { app.select(.build) } label: { buildBanner }
                            .buttonStyle(PressableStyle())
                        Button {
                            if gh.user == nil { app.select(.profile) } else { showClonePicker = true }
                        } label: { downloadBanner }
                            .buttonStyle(PressableStyle())
                    }
                    if !recents.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recentes").font(.headline)
                            ForEach(recents) { r in
                                NavigationLink(destination: IDEView(lang: r.lang, name: r.name)) { recentRow(r) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Projetos").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(Lang.allCases) { l in
                                NavigationLink(destination: ProjectsView(lang: l)) {
                                    Card(icon: l.icon, title: l.title, sub: l.hint)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding()
            }
            .dockInset()
            .sheet(isPresented: $showClonePicker, onDismiss: { if pendingSlug != nil { showDownload = true } }) {
                RepoPickerView(current: "") { slug in pendingSlug = slug }.environmentObject(gh)
            }
            .sheet(isPresented: $showDownload, onDismiss: { pendingSlug = nil }) {
                if let sl = pendingSlug {
                    let r = gh.allRepos.first(where: { $0.fullName == sl })
                    DownloadRepoView(slug: sl, branch: r?.defaultBranch ?? "main", language: r?.language)
                        .environmentObject(gh)
                        .environmentObject(app)
                }
            }
            .navigationTitle("CodeLab")
            .onAppear { loadRecents() }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Perfil

struct ProfileView: View {
    @EnvironmentObject var gh: GitHub
    @State private var showLogin = false
    @State private var favs = Favorites.list()

    func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(n)).font(.headline)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    var avatar: some View {
        Group {
            if let s = gh.avatarURL, let u = URL(string: s) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.25)
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
    }

    var header: some View {
        VStack(spacing: 8) {
            avatar
            if let login = gh.user {
                Text(gh.displayName ?? login).font(.title2.weight(.bold))
                Text("@" + login).foregroundColor(.secondary)
                if let bio = gh.bio, !bio.isEmpty {
                    Text(bio).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
                }
                HStack {
                    stat(gh.publicRepos, "repositórios")
                    stat(gh.followers, "seguidores")
                    stat(gh.following, "seguindo")
                }
                .padding(.top, 6)
            } else {
                Text("Você não está conectado").font(.headline)
                Text("Entre com o GitHub para enviar projetos, importar .zip e usar o git no terminal.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button { showLogin = true } label: {
                    Text("Entrar com GitHub").font(.subheadline.weight(.semibold)).padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    var body: some View {
        List {
            Section { header }
                .listRowBackground(Color.clear)

            if gh.user != nil {
                let repos = gh.allRepos.isEmpty ? gh.repos : gh.allRepos
                if !repos.isEmpty {
                    Section(header:
                        HStack {
                            Text("Repositórios")
                            Spacer()
                            NavigationLink("Ver todos") { RepoListView() }
                                .font(.footnote)
                        }
                        .textCase(nil)
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(repos.filter { favs.contains($0.fullName) } + repos.filter { !favs.contains($0.fullName) }) { r in
                                    NavigationLink(destination: RepoDetailView(repo: r)) {
                                        RepoCard(repo: r, fav: favs.contains(r.fullName))
                                    }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu {
                                        Button {
                                            Favorites.toggle(r.fullName)
                                            favs = Favorites.list()
                                        } label: {
                                            Label(favs.contains(r.fullName) ? "Desfavoritar" : "Favoritar",
                                                  systemImage: favs.contains(r.fullName) ? "star.slash" : "star")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }

            Section {
                NavigationLink(destination: SettingsView()) {
                    Label("Configurações", systemImage: "gearshape")
                }
                Button {
                    let path = Store.root.deletingLastPathComponent().path
                    if let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                       let u = URL(string: "shareddocuments://" + enc) {
                        UIApplication.shared.open(u, options: [:], completionHandler: nil)
                    }
                } label: {
                    Label("Abrir pasta no app Arquivos", systemImage: "folder")
                }
            }

            if let login = gh.user {
                Section {
                    if let u = URL(string: "https://github.com/" + login) {
                        Link(destination: u) { Label("Abrir perfil no GitHub", systemImage: "safari") }
                    }
                    Button(role: .destructive) { gh.logout() } label: {
                        Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            Section {
                Text("CodeLab 1.0")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .dockInset()
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { GitHubLoginView().environmentObject(gh) }
        .onAppear { favs = Favorites.list() }
        .task {
            await gh.refreshProfile()
            await gh.loadAllRepos()
        }
        .refreshable {
            await gh.refreshProfile()
            await gh.loadAllRepos()
        }
    }
}

// MARK: - Configurações

struct SettingsView: View {
    @AppStorage("blurEnabled") private var blur = true
    @AppStorage("hideDockCoding") private var hideDock = false
    @AppStorage("editorFontSize") private var fontSize = 15.0
    @AppStorage("autoPairs") private var autoPairs = true
    @AppStorage("autoIndent") private var autoIndent = true
    @AppStorage("tabWidth") private var tabWidth = 4
    @AppStorage("fluidAnimations") private var fluid = true
    @AppStorage("tabBlur") private var tabBlur = true
    @AppStorage("glassPill") private var glassPill = true
    @AppStorage("elastic") private var elastic = true
    @AppStorage("terminalTips") private var tips = false

    var body: some View {
        Form {
            Section(header: Text("Aparência"),
                    footer: Text("Aplica um efeito de vidro fosco à barra inferior. Desativado, a barra usa um fundo sólido.")) {
                Toggle("Desfoque da barra inferior", isOn: $blur)
            }
            Section(header: Text("Editor"),
                    footer: Text("Desativado, a barra inferior encolhe para uma faixa fina enquanto você edita código. O tamanho da fonte vale a partir do próximo arquivo aberto.")) {
                Toggle("Ocultar a barra inferior ao programar", isOn: $hideDock)
                Stepper(value: $fontSize, in: 11...24, step: 1) {
                    Text("Tamanho da fonte: " + String(Int(fontSize)))
                }
            }
            Section(header: Text("Ajuda ao digitar"),
                    footer: Text("Fecha ( [ { \" e ' sozinho, mantém a indentação ao dar Enter e recua o } automaticamente.")) {
                Toggle("Fechar parênteses e aspas", isOn: $autoPairs)
                Toggle("Indentação automática", isOn: $autoIndent)
                Picker("Largura do Tab", selection: $tabWidth) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            }
            Section(header: Text("Animações"),
                    footer: Text("Animações fluidas liga as molas e a resposta ao toque. Cada efeito pode ser desligado separadamente: o desfoque da tela ao trocar de aba, o visual de vidro 3D da gota na barra e a elasticidade (a gota esticando enquanto corre). Desligar tudo deixa o app mais leve em aparelhos lentos.")) {
                Toggle("Animações fluidas", isOn: $fluid)
                Toggle("Desfoque ao trocar de aba", isOn: $tabBlur)
                Toggle("Gota de vidro (efeito 3D)", isOn: $glassPill)
                Toggle("Elasticidade da gota", isOn: $elastic)
            }
            Section(header: Text("Terminal"),
                    footer: Text("As sugestões aparecem enquanto você digita: o texto fica sublinhado de amarelo e uma lâmpada surge no canto; toque nele para ver. A dica de próximo passo é uma faixa opcional no topo do terminal.")) {
                Toggle("Dica do próximo passo", isOn: $tips)
            }
        }
        .dockInset()
        .navigationTitle("Configurações")
        .navigationBarTitleDisplayMode(.inline)
    }
}
