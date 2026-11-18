import SwiftUI
import UniformTypeIdentifiers

/// Importa um .zip e envia para o GitHub em um único commit.
struct ZipToGitView: View {
    @EnvironmentObject var gh: GitHub
    @Environment(\.presentationMode) var pm
    @State private var zipURL: URL? = nil
    @State private var showPicker = false
    @State private var repo = UserDefaults.standard.string(forKey: "zip2git_repo") ?? ""
    @State private var branch = ""
    @State private var message = ""
    @State private var replaceAll = false
    @State private var busy = false
    @State private var log = ""
    @State private var resultSlug: String? = nil

    var canSend: Bool { zipURL != nil && !repo.trimmingCharacters(in: .whitespaces).isEmpty && !busy && gh.user != nil }

    func send() {
        guard let z = zipURL else { return }
        Task { @MainActor in
            busy = true
            log = ""
            resultSlug = nil
            defer { busy = false }
            do {
                let slug = try await gh.zipToGit(zip: z, repo: repo, branch: branch, message: message,
                                                 replaceAll: replaceAll, say: { log += $0 + "\n" })
                UserDefaults.standard.set(repo, forKey: "zip2git_repo")
                resultSlug = slug
            } catch {
                log += "✗ " + error.localizedDescription + "\n"
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                if gh.user == nil {
                    Section { Text("Entre no GitHub primeiro (botão no topo do menu).").foregroundColor(.red) }
                }
                Section(header: Text("Arquivo")) {
                    Button(zipURL?.lastPathComponent ?? "Escolher .zip…") { showPicker = true }
                }
                Section(header: Text("Destino"),
                        footer: Text("Se o repositório não existir, o CodeLab cria (privado) e o histórico fica com esse único commit. Branch vazia = a padrão do repositório.")) {
                    TextField("usuario/repositorio ou só o nome", text: $repo)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("branch (opcional)", text: $branch)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("mensagem do commit (opcional)", text: $message)
                    Toggle("Apagar do repositório o que não está no .zip", isOn: $replaceAll)
                }
                Section {
                    Button(busy ? "Enviando…" : "Enviar em um único commit") { send() }
                        .disabled(!canSend)
                }
                if !log.isEmpty {
                    Section(header: Text("Progresso")) {
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        if let s = resultSlug, let u = URL(string: "https://github.com/" + s) {
                            Link("Abrir no GitHub", destination: u)
                        }
                    }
                }
            }
            .navigationTitle(".zip → GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let u = urls.first { zipURL = u }
            }
        }
        .navigationViewStyle(.stack)
    }
}
