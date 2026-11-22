import Foundation
import UIKit

struct GHRepo: Identifiable {
    let id: Int
    let name: String
    let isPrivate: Bool
    let language: String?
    let url: String
    var fullName: String = ""
    var defaultBranch: String = "main"
}

struct GHError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct RunResult {
    var conclusion: String
    var url: String
    var output: String
    var saved: [String]
}

@MainActor
final class GitHub: ObservableObject {
    @Published var user: String? = UserDefaults.standard.string(forKey: "gh_user")
    @Published var log: String = ""
    @Published var userCode: String? = nil
    @Published var avatarURL: String? = UserDefaults.standard.string(forKey: "gh_avatar")
    @Published var displayName: String? = UserDefaults.standard.string(forKey: "gh_name")
    @Published var bio: String? = UserDefaults.standard.string(forKey: "gh_bio")
    @Published var publicRepos: Int = UserDefaults.standard.integer(forKey: "gh_repos")
    @Published var followers: Int = UserDefaults.standard.integer(forKey: "gh_followers")
    @Published var following: Int = UserDefaults.standard.integer(forKey: "gh_following")
    @Published var repos: [GHRepo] = []
    @Published var lastBuilt: URL? = nil
    @Published var allRepos: [GHRepo] = []
    @Published var verifyURL: String = ""

    func add(_ s: String) {
        log += (log.isEmpty ? "" : "\n") + s
    }

    // MARK: básico

    private func makeRequest(_ method: String, _ path: String, body: [String: Any]?) throws -> URLRequest {
        guard let t = UserDefaults.standard.string(forKey: "gh_token") else {
            throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).")
        }
        guard let url = URL(string: "https://api.github.com" + path) else { throw GHError(msg: "URL inválida") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (Int, Data) {
        let req = try makeRequest(method, path, body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// GET que segue o redirecionamento sem mandar o token para o outro servidor (logs e artifacts)
    func authedFetch(_ path: String) async throws -> Data {
        let req = try makeRequest("GET", path, body: nil)
        let (data, resp) = try await URLSession.shared.data(for: req, delegate: NoRedirect())
        if let http = resp as? HTTPURLResponse {
            if (300...399).contains(http.statusCode),
               let loc = http.value(forHTTPHeaderField: "Location"),
               let u = URL(string: loc) {
                let (d2, _) = try await URLSession.shared.data(from: u)
                return d2
            }
            if http.statusCode != 200 { throw GHError(msg: "HTTP \(http.statusCode)") }
        }
        return data
    }

    static func json(_ d: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    private func fail(_ what: String, _ code: Int, _ data: Data) -> GHError {
        let m = (GitHub.json(data)["message"] as? String) ?? ""
        var extra = ""
        if m.lowercased().contains("workflow") {
            extra = "\nDica: o token precisa das permissões 'repo' e 'workflow'."
        } else if code == 401 {
            extra = "\nDica: token inválido ou expirado. Entre no GitHub de novo."
        } else if code == 403 || code == 404 {
            extra = "\nDica: confira se o token tem as permissões 'repo' e 'workflow'."
        }
        return GHError(msg: "\(what) (HTTP \(code)): \(m)\(extra)")
    }

    func login(token: String) async throws {
        UserDefaults.standard.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gh_token")
        let (code, data) = try await call("GET", "/user")
        guard code == 200, let name = GitHub.json(data)["login"] as? String else {
            UserDefaults.standard.removeObject(forKey: "gh_token")
            throw GHError(msg: "Token inválido (HTTP \(code)).")
        }
        UserDefaults.standard.set(name, forKey: "gh_user")
        user = name
        Task { await refreshProfile() }
    }


    /// Todos os repositórios da conta (até 300), do mais recente para o mais antigo.
    func loadAllRepos() async {
        guard user != nil else { return }
        var acc: [GHRepo] = []
        for page in 1...3 {
            guard let r = try? await call("GET", "/user/repos?per_page=100&sort=updated&page=" + String(page) + "&affiliation=owner,collaborator,organization_member"),
                  r.0 == 200,
                  let arr = (try? JSONSerialization.jsonObject(with: r.1)) as? [[String: Any]] else { break }
            for x in arr {
                guard let id = x["id"] as? Int, let name = x["name"] as? String else { continue }
                acc.append(GHRepo(id: id, name: name,
                                  isPrivate: (x["private"] as? Bool) ?? false,
                                  language: x["language"] as? String,
                                  url: (x["html_url"] as? String) ?? "",
                                  fullName: (x["full_name"] as? String) ?? name,
                                  defaultBranch: (x["default_branch"] as? String) ?? "main"))
            }
            if arr.count < 100 { break }
        }
        if !acc.isEmpty { allRepos = acc }
    }

    /// Branches de um repositório ("dono/nome"). Vazio se o repositório não existir.
    func branches(of slug: String) async -> [String] {
        guard !slug.isEmpty,
              let r = try? await call("GET", "/repos/" + slug + "/branches?per_page=100"),
              r.0 == 200,
              let arr = (try? JSONSerialization.jsonObject(with: r.1)) as? [[String: Any]] else { return [] }
        return arr.compactMap { (x: [String: Any]) -> String? in x["name"] as? String }
    }

    /// Foto, nome e números da conta + repositórios mais recentes.
    func refreshProfile() async {
        guard user != nil else { return }
        let ud = UserDefaults.standard
        if let r = try? await call("GET", "/user"), r.0 == 200 {
            let j = GitHub.json(r.1)
            avatarURL = j["avatar_url"] as? String
            displayName = j["name"] as? String
            bio = j["bio"] as? String
            publicRepos = (j["public_repos"] as? Int) ?? 0
            followers = (j["followers"] as? Int) ?? 0
            following = (j["following"] as? Int) ?? 0
            ud.set(avatarURL, forKey: "gh_avatar")
            ud.set(displayName, forKey: "gh_name")
            ud.set(bio, forKey: "gh_bio")
            ud.set(publicRepos, forKey: "gh_repos")
            ud.set(followers, forKey: "gh_followers")
            ud.set(following, forKey: "gh_following")
        }
        if let r = try? await call("GET", "/user/repos?sort=updated&per_page=8&affiliation=owner,collaborator"), r.0 == 200,
           let arr = (try? JSONSerialization.jsonObject(with: r.1)) as? [[String: Any]] {
            repos = arr.compactMap { (x: [String: Any]) -> GHRepo? in
                guard let id = x["id"] as? Int, let name = x["name"] as? String else { return nil }
                return GHRepo(id: id, name: name,
                              isPrivate: (x["private"] as? Bool) ?? false,
                              language: x["language"] as? String,
                              url: (x["html_url"] as? String) ?? "")
            }
        }
    }


    /// Login pelo site do GitHub (Device Flow): mostra um código, você autoriza no github.com e o app recebe o token.
    func loginDevice(clientId: String) async throws {
        let cid = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw GHError(msg: "Informe o Client ID do seu OAuth App.") }
        UserDefaults.standard.set(cid, forKey: "gh_client_id")

        func post(_ url: String, _ body: [String: Any]) async throws -> [String: Any] {
            guard let u = URL(string: url) else { throw GHError(msg: "URL inválida") }
            var req = URLRequest(url: u)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (d, _) = try await URLSession.shared.data(for: req)
            return GitHub.json(d)
        }

        let r = try await post("https://github.com/login/device/code", ["client_id": cid, "scope": "repo workflow"])
        guard let device = r["device_code"] as? String, let code = r["user_code"] as? String else {
            let m = (r["error_description"] as? String) ?? (r["error"] as? String) ?? "resposta inválida"
            throw GHError(msg: "O GitHub recusou: " + m + ". Confira o Client ID e se 'Enable Device Flow' está marcado no OAuth App.")
        }
        let uri = (r["verification_uri"] as? String) ?? "https://github.com/login/device"
        var interval = (r["interval"] as? Int) ?? 5
        let expires = (r["expires_in"] as? Int) ?? 900
        userCode = code
        verifyURL = uri
        UIPasteboard.general.string = code
        defer { userCode = nil }

        var waited = 0
        while waited < expires {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            waited += interval
            let t = try await post("https://github.com/login/oauth/access_token",
                                   ["client_id": cid, "device_code": device,
                                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            if let tok = t["access_token"] as? String {
                try await login(token: tok)
                return
            }
            let err = (t["error"] as? String) ?? ""
            switch err {
            case "authorization_pending": break
            case "slow_down": interval += 5
            case "expired_token": throw GHError(msg: "O código expirou. Tente de novo.")
            case "access_denied": throw GHError(msg: "Acesso negado no GitHub.")
            default: throw GHError(msg: "Erro: " + ((t["error_description"] as? String) ?? "desconhecido"))
            }
        }
        throw GHError(msg: "Tempo esgotado esperando a autorização.")
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "gh_token")
        UserDefaults.standard.removeObject(forKey: "gh_user")
        for k in ["gh_avatar", "gh_name", "gh_bio", "gh_repos", "gh_followers", "gh_following"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
        user = nil
        avatarURL = nil
        displayName = nil
        bio = nil
        publicRepos = 0
        followers = 0
        following = 0
        repos = []
    }

    // MARK: leitura do repositório

    func headRef(_ slug: String, _ branch: String) async throws -> String? {
        let (c, d) = try await call("GET", "/repos/\(slug)/git/ref/heads/\(branch)")
        if c == 200 { return (GitHub.json(d)["object"] as? [String: Any])?["sha"] as? String }
        if c == 404 || c == 409 { return nil }
        throw fail("Erro ao ler a branch", c, d)
    }

    func headRefRetry(_ slug: String, _ branch: String, tries: Int) async throws -> String? {
        for i in 0..<tries {
            if let h = try await headRef(slug, branch) { return h }
            if i < tries - 1 { try await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        return nil
    }

    func fetchTree(_ slug: String, _ commitSha: String) async throws -> [String: String] {
        let (c, d) = try await call("GET", "/repos/\(slug)/git/commits/\(commitSha)")
        guard c == 200, let tsha = (GitHub.json(d)["tree"] as? [String: Any])?["sha"] as? String else {
            throw fail("Erro ao ler o commit", c, d)
        }
        let (c2, d2) = try await call("GET", "/repos/\(slug)/git/trees/\(tsha)?recursive=1")
        guard c2 == 200, let items = GitHub.json(d2)["tree"] as? [[String: Any]] else {
            throw fail("Erro ao ler os arquivos", c2, d2)
        }
        var m: [String: String] = [:]
        for it in items {
            if (it["type"] as? String) == "blob", let p = it["path"] as? String, let s = it["sha"] as? String {
                m[p] = s
            }
        }
        return m
    }

    // MARK: git push

    func push(root: URL, say: (String) -> Void) async throws {
        guard let me = user else { throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).") }
        var s = Repo.load(root)
        guard !s.remote.isEmpty else {
            throw GHError(msg: "Nenhum remoto configurado.\nUse: git remote add origin usuario/repositorio")
        }
        guard !s.commits.isEmpty else {
            throw GHError(msg: "Nada para enviar: nenhum commit pendente.\nUse: git add .   e depois   git commit -m \"mensagem\"")
        }
        let slug = s.remote
        var created = false
        var defaultBranch = "main"
        let (rc, rd) = try await call("GET", "/repos/\(slug)")
        if rc == 200 {
            defaultBranch = (GitHub.json(rd)["default_branch"] as? String) ?? "main"
        } else if rc == 404 {
            let prefix = me.lowercased() + "/"
            guard slug.lowercased().hasPrefix(prefix) else {
                throw GHError(msg: "O repositório \(slug) não existe (ou você não tem acesso).")
            }
            let name = String(slug.dropFirst(prefix.count))
            let (c2, d2) = try await call("POST", "/user/repos", body: ["name": name, "private": true, "auto_init": true])
            guard c2 == 201 else { throw fail("Não consegui criar o repositório", c2, d2) }
            defaultBranch = (GitHub.json(d2)["default_branch"] as? String) ?? "main"
            created = true
            say("Repositório \(slug) criado (privado).")
        } else {
            throw fail("Erro ao acessar \(slug)", rc, rd)
        }

        var remoteHead: String
        if let h = try await headRefRetry(slug, s.branch, tries: created ? 6 : 1) {
            remoteHead = h
        } else {
            guard let dh = try await headRefRetry(slug, defaultBranch, tries: created ? 6 : 1) else {
                throw GHError(msg: "O repositório está vazio. Crie-o com um README no GitHub (ou apague-o e deixe o CodeLab criar).")
            }
            if s.branch != defaultBranch {
                let (c3, d3) = try await call("POST", "/repos/\(slug)/git/refs", body: ["ref": "refs/heads/\(s.branch)", "sha": dh])
                guard c3 == 201 else { throw fail("Não consegui criar a branch \(s.branch)", c3, d3) }
                say("Branch \(s.branch) criada no GitHub.")
            }
            remoteHead = dh
        }

        if !s.baseCommit.isEmpty && s.baseCommit != remoteHead {
            throw GHError(msg: "Push rejeitado: o GitHub tem commits que você ainda não baixou.\nRode: git pull   e depois   git push")
        }

        var n = 0
        while let c = s.commits.first {
            n += 1
            say("Enviando \(c.id): \(c.message)")
            let (cc, cd) = try await call("GET", "/repos/\(slug)/git/commits/\(remoteHead)")
            guard cc == 200, let baseTree = (GitHub.json(cd)["tree"] as? [String: Any])?["sha"] as? String else {
                throw fail("Erro ao ler o commit remoto", cc, cd)
            }
            var entries: [[String: Any]] = []
            for (p, sha) in c.files.sorted(by: { $0.key < $1.key }) {
                if sha.isEmpty {
                    entries.append(["path": p, "mode": "100644", "type": "blob", "sha": NSNull()])
                } else {
                    let data = try Data(contentsOf: root.appendingPathComponent(".codelab/objects/" + sha))
                    let (bc, bd) = try await call("POST", "/repos/\(slug)/git/blobs", body: ["content": data.base64EncodedString(), "encoding": "base64"])
                    guard bc == 201, let bsha = GitHub.json(bd)["sha"] as? String else {
                        throw fail("Falha ao enviar \(p)", bc, bd)
                    }
                    entries.append(["path": p, "mode": "100644", "type": "blob", "sha": bsha])
                }
            }
            let (tc, td) = try await call("POST", "/repos/\(slug)/git/trees", body: ["base_tree": baseTree, "tree": entries])
            guard tc == 201, let newTree = GitHub.json(td)["sha"] as? String else {
                throw fail("Falha ao montar os arquivos", tc, td)
            }
            let (mc, md) = try await call("POST", "/repos/\(slug)/git/commits", body: ["message": c.message, "tree": newTree, "parents": [remoteHead]])
            guard mc == 201, let newSha = GitHub.json(md)["sha"] as? String else {
                throw fail("Falha ao criar o commit", mc, md)
            }
            let (uc, ud) = try await call("PATCH", "/repos/\(slug)/git/refs/heads/\(s.branch)", body: ["sha": newSha])
            guard uc == 200 else { throw fail("Falha ao atualizar a branch", uc, ud) }
            for (p, sha) in c.files {
                if sha.isEmpty { s.base.removeValue(forKey: p) } else { s.base[p] = sha }
            }
            s.baseCommit = newSha
            remoteHead = newSha
            s.commits.removeFirst()
            Repo.save(s, root)
        }
        say("✓ \(n) commit(s) enviado(s) para \(slug) (\(s.branch)).")
    }

    // MARK: git pull / clone / log

    func pull(root: URL, say: (String) -> Void) async throws {
        guard user != nil else { throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).") }
        var s = Repo.load(root)
        guard !s.remote.isEmpty else {
            throw GHError(msg: "Nenhum remoto configurado.\nUse: git remote add origin usuario/repositorio")
        }
        guard let headSha = try await headRef(s.remote, s.branch) else {
            throw GHError(msg: "A branch \(s.branch) ainda não existe no GitHub. Faça git push primeiro.")
        }
        if headSha == s.baseCommit {
            say("Já está atualizado.")
            return
        }
        let remote = try await fetchTree(s.remote, headSha)
        let work = Repo.workingTree(root)
        var changed = 0
        var kept: [String] = []
        for (p, sha) in remote.sorted(by: { $0.key < $1.key }) {
            if s.base[p] == sha || work[p] == sha { continue }
            if let w = work[p], w != s.base[p] {
                kept.append(p)
                continue
            }
            let (c, d) = try await call("GET", "/repos/\(s.remote)/git/blobs/\(sha)")
            guard c == 200, let b64 = GitHub.json(d)["content"] as? String,
                  let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
                throw fail("Falha ao baixar \(p)", c, d)
            }
            let dest = root.appendingPathComponent(p)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            changed += 1
            say("  baixado \(p)")
        }
        for (p, bsha) in s.base where remote[p] == nil {
            if let w = work[p] {
                if w == bsha {
                    try? FileManager.default.removeItem(at: root.appendingPathComponent(p))
                    changed += 1
                    say("  removido \(p)")
                } else {
                    kept.append(p)
                }
            }
        }
        s.base = remote
        s.baseCommit = headSha
        Repo.save(s, root)
        say("Atualizado: \(changed) arquivo(s).")
        if !kept.isEmpty {
            say("Mantive a SUA versão de: " + kept.joined(separator: ", "))
            say("(ao dar git push, a sua versão substitui a do GitHub)")
        }
    }

    func clone(_ slug: String, into dir: URL, say: (String) -> Void) async throws {
        guard user != nil else { throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).") }
        let (c, d) = try await call("GET", "/repos/\(slug)")
        guard c == 200 else { throw fail("Não achei o repositório \(slug)", c, d) }
        let br = (GitHub.json(d)["default_branch"] as? String) ?? "main"
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var s = GitState()
        s.remote = slug
        s.branch = br
        Repo.save(s, dir)
        say("Clonando \(slug)…")
        try await pull(root: dir, say: say)
    }

    func remoteLog(root: URL, count: Int) async throws -> [String] {
        let s = Repo.load(root)
        guard !s.remote.isEmpty else { return [] }
        let (c, d) = try await call("GET", "/repos/\(s.remote)/commits?sha=\(s.branch)&per_page=\(count)")
        guard c == 200, let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.map { (it: [String: Any]) -> String in
            let sha = String(((it["sha"] as? String) ?? "").prefix(7))
            let cm = it["commit"] as? [String: Any]
            let msg = ((cm?["message"] as? String) ?? "").components(separatedBy: "\n").first ?? ""
            let au = cm?["author"] as? [String: Any]
            let who = (au?["name"] as? String) ?? "?"
            let date = String(((au?["date"] as? String) ?? "").prefix(10))
            return "\(sha) \(msg)  — \(who), \(date)"
        }
    }

    // MARK: ZIP → GitHub em um único commit (como o ZipToGit)

    func zipToGit(zip: URL, repo: String, branch: String, message: String, replaceAll: Bool, say: (String) -> Void) async throws -> (slug: String, branch: String) {
        guard let me = user else { throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).") }
        guard let slug = Repo.normalize(repo, user: me) else {
            throw GHError(msg: "Nome de repositório inválido. Use usuario/repositorio ou só o nome.")
        }

        // 1) abrir o .zip
        let fm = FileManager.default
        let scoped = zip.startAccessingSecurityScopedResource()
        defer { if scoped { zip.stopAccessingSecurityScopedResource() } }
        let tmp = fm.temporaryDirectory.appendingPathComponent("zip2git-" + UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        say("Abrindo o .zip…")
        _ = try Zip.extract(zip, to: tmp)
        let files = Store.files(in: tmp)
        guard !files.isEmpty else { throw GHError(msg: "O .zip está vazio.") }
        say("\(files.count) arquivo(s) no .zip.")

        // 2) repositório (cria se não existir)
        var defaultBranch = "main"
        var created = false
        let (rc, rd) = try await call("GET", "/repos/\(slug)")
        if rc == 200 {
            defaultBranch = (GitHub.json(rd)["default_branch"] as? String) ?? "main"
        } else if rc == 404 {
            let prefix = me.lowercased() + "/"
            guard slug.lowercased().hasPrefix(prefix) else {
                throw GHError(msg: "O repositório \(slug) não existe (ou você não tem acesso).")
            }
            let name = String(slug.dropFirst(prefix.count))
            let (c2, d2) = try await call("POST", "/user/repos", body: ["name": name, "private": true, "auto_init": true])
            guard c2 == 201 else { throw fail("Não consegui criar o repositório", c2, d2) }
            defaultBranch = (GitHub.json(d2)["default_branch"] as? String) ?? "main"
            created = true
            say("Repositório \(slug) criado (privado).")
        } else {
            throw fail("Erro ao acessar \(slug)", rc, rd)
        }
        let wanted = branch.trimmingCharacters(in: .whitespaces)
        let target = wanted.isEmpty ? defaultBranch : wanted

        // 3) commit pai
        var parent = try await headRefRetry(slug, target, tries: created ? 6 : 1)
        let branchExists = parent != nil
        if parent == nil { parent = try await headRefRetry(slug, defaultBranch, tries: created ? 6 : 1) }
        guard let parentSha = parent else {
            throw GHError(msg: "O repositório está vazio. Crie-o com um README no GitHub (ou apague-o e deixe o CodeLab criar).")
        }
        var lastTree: String? = nil
        if !replaceAll && !created {
            let (cc, cd) = try await call("GET", "/repos/\(slug)/git/commits/\(parentSha)")
            guard cc == 200, let bt = (GitHub.json(cd)["tree"] as? [String: Any])?["sha"] as? String else {
                throw fail("Erro ao ler o commit atual", cc, cd)
            }
            lastTree = bt
        }

        // 4) arquivos: texto vai direto na árvore, binário vira blob
        var entries: [[String: Any]] = []
        var sizes: [Int] = []
        for (i, rel) in files.enumerated() {
            let data = try Data(contentsOf: tmp.appendingPathComponent(rel))
            if data.count > 95_000_000 { throw GHError(msg: rel + " passa de 95 MB (o limite do GitHub é 100 MB).") }
            if !data.isEmpty, !data.contains(0), let text = String(data: data, encoding: .utf8) {
                entries.append(["path": rel, "mode": "100644", "type": "blob", "content": text])
                sizes.append(data.count)
            } else {
                let (bc, bd) = try await call("POST", "/repos/\(slug)/git/blobs", body: ["content": data.base64EncodedString(), "encoding": "base64"])
                guard bc == 201, let bsha = GitHub.json(bd)["sha"] as? String else { throw fail("Falha ao enviar " + rel, bc, bd) }
                entries.append(["path": rel, "mode": "100644", "type": "blob", "sha": bsha])
                sizes.append(300)
            }
            if i % 25 == 0 { say("Preparando \(i + 1)/\(files.count)…") }
        }

        // 5) árvore (em partes, mas continua sendo um commit só)
        var i = 0
        while i < entries.count {
            var j = i
            var total = 0
            while j < entries.count && (j - i) < 200 && total < 4_000_000 {
                total += sizes[j]
                j += 1
            }
            var body: [String: Any] = ["tree": Array(entries[i..<j])]
            if let b = lastTree { body["base_tree"] = b }
            let (tc, td) = try await call("POST", "/repos/\(slug)/git/trees", body: body)
            guard tc == 201, let t = GitHub.json(td)["sha"] as? String else { throw fail("Falha ao montar os arquivos", tc, td) }
            lastTree = t
            i = j
            say("Montando… \(j)/\(entries.count)")
        }
        guard let finalTree = lastTree else { throw GHError(msg: "Nada para enviar.") }

        // 6) o commit
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = trimmed.isEmpty ? "Importado do .zip pelo CodeLab" : trimmed
        let parents: [String] = created ? [] : [parentSha]
        let (mc, md) = try await call("POST", "/repos/\(slug)/git/commits", body: ["message": msg, "tree": finalTree, "parents": parents])
        guard mc == 201, let newSha = GitHub.json(md)["sha"] as? String else { throw fail("Falha ao criar o commit", mc, md) }

        if branchExists {
            let (uc, ud) = try await call("PATCH", "/repos/\(slug)/git/refs/heads/\(target)", body: ["sha": newSha, "force": created])
            guard uc == 200 else { throw fail("Falha ao atualizar a branch", uc, ud) }
        } else {
            let (c3, d3) = try await call("POST", "/repos/\(slug)/git/refs", body: ["ref": "refs/heads/" + target, "sha": newSha])
            guard c3 == 201 else { throw fail("Falha ao criar a branch " + target, c3, d3) }
        }
        say("✓ 1 commit com \(files.count) arquivo(s) enviado para \(slug) (\(target)).")
        return (slug: slug, branch: target)
    }

    // MARK: atalho usado pelos botões do app

    func syncAndPush(dir: URL, repo: String, say: (String) -> Void) async throws -> String {
        guard let me = user else { throw GHError(msg: "Entre no GitHub primeiro (botão no topo do menu).") }
        guard let slug = Repo.normalize(repo, user: me) else {
            throw GHError(msg: "Nome de repositório inválido. Use usuario/repositorio ou só o nome.")
        }
        Repo.initRepo(dir)
        var s = Repo.load(dir)
        s.remote = slug
        let n = Repo.stage(dir, &s, prefix: "", includeNew: true)
        if n > 0 {
            let c = try Repo.commit(dir, &s, message: "CodeLab: atualização")
            say("Commit \(c.id): \(n) arquivo(s)")
        } else {
            Repo.save(s, dir)
        }
        if s.commits.isEmpty {
            say("Nada novo para enviar (o GitHub já está igual).")
            return slug
        }
        try await push(root: dir, say: say)
        return slug
    }

    // MARK: executar o workflow

    func runWorkflow(slug: String, branch: String, say: (String) -> Void) async throws -> RunResult {
        let listPath = "/repos/\(slug)/actions/workflows/build.yml/runs?event=workflow_dispatch&per_page=1"

        func latest() async throws -> [String: Any]? {
            let (c, d) = try await call("GET", listPath)
            if c == 404 { return nil }
            guard c == 200 else { throw fail("Erro ao consultar execuções", c, d) }
            return (GitHub.json(d)["workflow_runs"] as? [[String: Any]])?.first
        }

        lastBuilt = nil
        let prev = try await latest()
        let prevId = prev?["id"] as? Int

        var started = false
        for i in 0..<8 {
            let (dc, dd) = try await call("POST", "/repos/\(slug)/actions/workflows/build.yml/dispatches", body: ["ref": branch])
            if dc == 204 { started = true; break }
            let m = (GitHub.json(dd)["message"] as? String) ?? ""
            if dc == 422 && m.contains("workflow_dispatch") {
                throw GHError(msg: "O build.yml não tem 'on: workflow_dispatch'. Confira .github/workflows/build.yml.")
            }
            if dc == 404 && i < 7 {
                if i == 0 { say("Aguardando o GitHub reconhecer o workflow…") }
                try await Task.sleep(nanoseconds: 4_000_000_000)
                continue
            }
            throw fail("Não consegui iniciar o workflow (o projeto foi enviado com git push?)", dc, dd)
        }
        guard started else { throw GHError(msg: "Não consegui iniciar o workflow.") }

        say("Workflow iniciado. Aguardando o resultado…")
        var run: [String: Any]? = nil
        var lastStatus = ""
        for _ in 0..<90 {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            if let r = try await latest(), (r["id"] as? Int) != prevId {
                run = r
                let st = (r["status"] as? String) ?? "?"
                if st != lastStatus {
                    lastStatus = st
                    say("Status: \(st)")
                }
                if st == "completed" { break }
            }
        }
        guard let r = run, let runId = r["id"] as? Int else {
            throw GHError(msg: "Tempo esgotado esperando o workflow. Veja a aba Actions no GitHub.")
        }
        let concl = (r["conclusion"] as? String) ?? (r["status"] as? String) ?? "?"
        let url = (r["html_url"] as? String) ?? ""

        var output = ""
        let (_, jd) = try await call("GET", "/repos/\(slug)/actions/runs/\(runId)/jobs")
        if let job = (GitHub.json(jd)["jobs"] as? [[String: Any]])?.first, let jid = job["id"] as? Int {
            if let data = try? await authedFetch("/repos/\(slug)/actions/jobs/\(jid)/logs"),
               let text = String(data: data, encoding: .utf8) {
                output = GitHub.extractOutput(text)
            }
        }

        var saved: [String] = []
        if concl == "success" {
            let (ac, ad) = try await call("GET", "/repos/\(slug)/actions/runs/\(runId)/artifacts")
            if ac == 200, let arts = GitHub.json(ad)["artifacts"] as? [[String: Any]], !arts.isEmpty {
                let dl = Store.root.deletingLastPathComponent().appendingPathComponent("Downloads")
                try? FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
                for a in arts {
                    guard let aid = a["id"] as? Int, let nm = a["name"] as? String else { continue }
                    say("Baixando \(nm)…")
                    if let zip = try? await authedFetch("/repos/\(slug)/actions/artifacts/\(aid)/zip") {
                        let fname = slug.replacingOccurrences(of: "/", with: "-") + "-" + nm + "-" + String(runId) + ".zip"
                        let dest = dl.appendingPathComponent(fname)
                        if (try? zip.write(to: dest)) != nil {
                            saved.append(fname)
                            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("art-" + UUID().uuidString)
                            if (try? Zip.extract(dest, to: tmp)) != nil {
                                for rel in Store.files(in: tmp) where rel.hasSuffix(".ipa") || rel.hasSuffix(".apk") {
                                    let base = slug.replacingOccurrences(of: "/", with: "-") + "-" + String(runId) + "-" + (rel as NSString).lastPathComponent
                                    let out = dl.appendingPathComponent(base)
                                    try? FileManager.default.removeItem(at: out)
                                    if (try? FileManager.default.copyItem(at: tmp.appendingPathComponent(rel), to: out)) != nil {
                                        saved.append(base)
                                        lastBuilt = out
                                    }
                                }
                            }
                            try? FileManager.default.removeItem(at: tmp)
                        }
                    }
                }
            }
        }
        return RunResult(conclusion: concl, url: url, output: output, saved: saved)
    }

    static func describe(_ r: RunResult) -> String {
        var t = (r.conclusion == "success" ? "✅ Sucesso" : "❌ Resultado: " + r.conclusion) + "\n"
        if !r.output.isEmpty { t += "\n" + r.output + "\n" }
        if !r.saved.isEmpty {
            t += "\nArquivos salvos em Arquivos > CodeLab > Downloads:\n" + r.saved.map { "  " + $0 }.joined(separator: "\n") + "\n"
        }
        if !r.url.isEmpty { t += "\n" + r.url }
        return t
    }

    static func extractOutput(_ all: String) -> String {
        var lines: [String] = []
        for raw in all.components(separatedBy: "\n") {
            var l = raw
            if l.hasPrefix("\u{FEFF}") { l.removeFirst() }
            if let r = l.range(of: #"^\d{4}-\d{2}-\d{2}T[0-9:.]+Z "#, options: .regularExpression) {
                l.removeSubrange(r)
            }
            l = l.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            lines.append(l)
        }
        var start = -1
        for (i, l) in lines.enumerated() {
            if l.hasPrefix("##[group]Run ") && !l.contains("Run actions/") && !l.contains("Run gradle/") {
                start = i
            }
        }
        if start < 0 { return lines.suffix(60).joined(separator: "\n") }
        var out: [String] = []
        var inScript = true
        var i = start
        while i < lines.count {
            let l = lines[i]
            if l.hasPrefix("Post job cleanup") || l.hasPrefix("##[group]Post") { break }
            if inScript {
                if l.hasPrefix("##[endgroup]") { inScript = false }
            } else if l.hasPrefix("##[error]") {
                out.append("ERRO: " + String(l.dropFirst(9)))
            } else if !l.hasPrefix("##[") {
                out.append(l)
            }
            i += 1
        }
        while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
        if out.isEmpty { return "(sem saída)" }
        return out.suffix(120).joined(separator: "\n")
    }
}
