import SwiftUI
import UIKit

// MARK: - Preferências

enum Prefs {
    static var fluid: Bool { UserDefaults.standard.object(forKey: "fluidAnimations") as? Bool ?? true }
    static var terminalTips: Bool { UserDefaults.standard.object(forKey: "terminalTips") as? Bool ?? true }
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
    enum Tab: Int, CaseIterable { case home, terminal, profile }

    @Published var tab: Tab = .home
    @Published var coding = false
    @Published var keyboard = false
    @Published var blurPhase: CGFloat = 0

    var dockMini: Bool { coding && tab == .home }
    var dockVisible: Bool { !keyboard && !(dockMini && UserDefaults.standard.bool(forKey: "hideDockCoding")) }
    var dockHeight: CGFloat { dockVisible ? (dockMini ? 24 : 52) : 0 }

    /// Troca de aba. Com animações fluidas, usa mola e um borrão de movimento que cresce no meio da transição.
    func select(_ t: Tab) {
        guard t != tab else { return }
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
                layer(.terminal) { NavigationView { TerminalView() }.navigationViewStyle(.stack) }
                layer(.profile) { NavigationView { ProfileView() }.navigationViewStyle(.stack) }
            }
            .modifier(MotionBlur(phase: app.blurPhase))

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

struct DockView: View {
    let mini: Bool
    @EnvironmentObject var app: AppState
    @EnvironmentObject var gh: GitHub
    @AppStorage("blurEnabled") private var blur = true
    @Namespace private var pill

    struct Entry {
        let tab: AppState.Tab
        let title: String
        let icon: String
        let iconSelected: String
    }

    let entries: [Entry] = [
        Entry(tab: .home, title: "Início", icon: "house", iconSelected: "house.fill"),
        Entry(tab: .terminal, title: "Terminal", icon: "terminal", iconSelected: "terminal.fill"),
        Entry(tab: .profile, title: "Perfil", icon: "person.crop.circle", iconSelected: "person.crop.circle.fill")
    ]

    func select(_ t: AppState.Tab) {
        if app.tab != t { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        app.select(t)
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
        .background(
            ZStack {
                if sel && !mini && Prefs.fluid {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .matchedGeometryEffect(id: "pill", in: pill)
                        .scaleEffect(x: 1 + 0.4 * abs(sin(app.blurPhase * .pi)), y: 1)
                }
            }
        )
        .contentShape(Rectangle())
    }

    var bar: some View {
        Group {
            if blur {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Color(.systemBackground)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(entries, id: \.title) { e in
                Button { select(e.tab) } label: { cell(e) }
                    .buttonStyle(PressableStyle())
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
    @State private var showZip = false
    @State private var recents: [RecentItem] = []

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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
            .navigationTitle("CodeLab")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showZip = true } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(isPresented: $showZip) { ZipToGitView().environmentObject(gh) }
            .onAppear { loadRecents() }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Perfil

struct ProfileView: View {
    @EnvironmentObject var gh: GitHub
    @State private var showLogin = false

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

            if gh.user != nil && !gh.repos.isEmpty {
                Section(header: Text("Repositórios recentes")) {
                    ForEach(gh.repos) { r in
                        if let u = URL(string: r.url) {
                            Link(destination: u) {
                                HStack(spacing: 10) {
                                    Image(systemName: r.isPrivate ? "lock" : "book.closed").frame(width: 22).foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).foregroundColor(.primary)
                                        if let lang = r.language { Text(lang).font(.caption).foregroundColor(.secondary) }
                                    }
                                    Spacer()
                                }
                            }
                        }
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
        .task { await gh.refreshProfile() }
        .refreshable { await gh.refreshProfile() }
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
    @AppStorage("terminalTips") private var tips = true

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
                    footer: Text("Transições com mola e efeito de movimento (um borrão que acompanha o deslize) ao trocar de aba, além de resposta ao toque nos botões. Desative em aparelhos mais lentos ou para economizar bateria.")) {
                Toggle("Animações fluidas", isOn: $fluid)
            }
            Section(header: Text("Terminal"),
                    footer: Text("As sugestões de comandos e de arquivos aparecem enquanto você digita. A dica abaixo aparece só com o campo vazio.")) {
                Toggle("Dica do próximo passo", isOn: $tips)
            }
        }
        .dockInset()
        .navigationTitle("Configurações")
        .navigationBarTitleDisplayMode(.inline)
    }
}
