import Foundation

// MARK: - Modelos

struct RepoItem: Identifiable {
    let name: String
    let path: String
    let isDir: Bool
    let sha: String
    let size: Int
    var id: String { path }
}

struct RunInfo: Identifiable {
    let id: Int
    let title: String
    let status: String
    let conclusion: String
    let branch: String
    let number: Int
    let created: String
    let url: String
    let event: String
}

struct ArtifactInfo: Identifiable {
    let id: Int
    let name: String
    let size: Int
    let expired: Bool
    let created: String
}

enum Fmt {
    static func ago(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func size(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}

enum RepoLang {
    static func lang(forRepoLanguage l: String?) -> Lang {
        switch (l ?? "").lowercased() {
        case "swift", "objective-c": return .ios
        case "java": return .java
        case "kotlin": return .android
        case "gdscript": return .godot
        default: return .cpp
        }
    }
}

// MARK: - API do repositório (ver, apagar, execuções, artefatos, baixar)

extension GitHub {
    func apiError(_ what: String, _ code: Int, _ data: Data) -> GHError {
        let m = (GitHub.json(data)["message"] as? String) ?? ""
        var extra = ""
        if code == 403 || code == 404 { extra = "\nDica: confira se o token tem as permissões 'repo' e 'workflow'." }
        return GHError(msg: what + " (HTTP " + String(code) + "): " + m + extra)
    }

    func encPath(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
    func encQuery(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }

    // MARK: código

    func listContents(_ slug: String, _ path: String, _ branch: String) async throws -> [RepoItem] {
        let p = path.isEmpty ? "/repos/" + slug + "/contents" : "/repos/" + slug + "/contents/" + encPath(path)
        let (c, d) = try await call("GET", p + "?ref=" + encQuery(branch))
        guard c == 200 else { throw apiError("Não consegui abrir a pasta", c, d) }
        guard let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        var out: [RepoItem] = []
        for x in arr {
            guard let name = x["name"] as? String, let pth = x["path"] as? String else { continue }
            out.append(RepoItem(name: name, path: pth,
                                isDir: (x["type"] as? String) == "dir",
                                sha: (x["sha"] as? String) ?? "",
                                size: (x["size"] as? Int) ?? 0))
        }
        return out.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    func fileText(_ slug: String, _ path: String, _ branch: String) async throws -> String {
        let (c, d) = try await call("GET", "/repos/" + slug + "/contents/" + encPath(path) + "?ref=" + encQuery(branch))
        guard c == 200 else { throw apiError("Não consegui abrir o arquivo", c, d) }
        let j = GitHub.json(d)
        if let sz = j["size"] as? Int, sz > 1_000_000 {
            throw GHError(msg: "Arquivo grande demais para visualizar (" + Fmt.size(sz) + ").")
        }
        guard let b64 = j["content"] as? String,
              let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw GHError(msg: "Este arquivo não tem conteúdo para mostrar.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GHError(msg: "Arquivo binário: não dá para mostrar como texto.")
        }
        return text
    }

    /// Apaga arquivos e/ou pastas do repositório em um único commit.
    func deletePaths(_ slug: String, branch: String, paths: [String], message: String) async throws {
        guard let head = try await headRef(slug, branch) else { throw GHError(msg: "Branch não encontrada.") }
        let (cc, cd) = try await call("GET", "/repos/" + slug + "/git/commits/" + head)
        guard cc == 200, let baseTree = (GitHub.json(cd)["tree"] as? [String: Any])?["sha"] as? String else {
            throw apiError("Erro ao ler o commit", cc, cd)
        }
        let (tc, td) = try await call("GET", "/repos/" + slug + "/git/trees/" + baseTree + "?recursive=1")
        guard tc == 200, let items = GitHub.json(td)["tree"] as? [[String: Any]] else {
            throw apiError("Erro ao ler os arquivos", tc, td)
        }
        var del: [String] = []
        for it in items where (it["type"] as? String) == "blob" {
            guard let p = it["path"] as? String else { continue }
            if paths.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { del.append(p) }
        }
        guard !del.isEmpty else { throw GHError(msg: "Não achei nada para apagar.") }
        var entries: [[String: Any]] = []
        for p in del { entries.append(["path": p, "mode": "100644", "type": "blob", "sha": NSNull()]) }
        let (nc, nd) = try await call("POST", "/repos/" + slug + "/git/trees", body: ["base_tree": baseTree, "tree": entries])
        guard nc == 201, let newTree = GitHub.json(nd)["sha"] as? String else { throw apiError("Falha ao montar a remoção", nc, nd) }
        let (mc, md) = try await call("POST", "/repos/" + slug + "/git/commits", body: ["message": message, "tree": newTree, "parents": [head]])
        guard mc == 201, let sha = GitHub.json(md)["sha"] as? String else { throw apiError("Falha ao criar o commit", mc, md) }
        let (uc, ud) = try await call("PATCH", "/repos/" + slug + "/git/refs/heads/" + branch, body: ["sha": sha])
        guard uc == 200 else { throw apiError("Falha ao atualizar a branch", uc, ud) }
    }

    // MARK: Actions e artefatos

    func listRuns(_ slug: String, branch: String?) async throws -> [RunInfo] {
        var q = "/repos/" + slug + "/actions/runs?per_page=30"
        if let b = branch, !b.isEmpty { q += "&branch=" + encQuery(b) }
        let (c, d) = try await call("GET", q)
        guard c == 200 else { throw apiError("Não consegui ler as execuções", c, d) }
        let arr = (GitHub.json(d)["workflow_runs"] as? [[String: Any]]) ?? []
        return arr.compactMap { (x: [String: Any]) -> RunInfo? in
            guard let id = x["id"] as? Int else { return nil }
            return RunInfo(id: id,
                           title: (x["display_title"] as? String) ?? (x["name"] as? String) ?? "Execução",
                           status: (x["status"] as? String) ?? "",
                           conclusion: (x["conclusion"] as? String) ?? "",
                           branch: (x["head_branch"] as? String) ?? "",
                           number: (x["run_number"] as? Int) ?? 0,
                           created: (x["created_at"] as? String) ?? "",
                           url: (x["html_url"] as? String) ?? "",
                           event: (x["event"] as? String) ?? "")
        }
    }

    func listArtifacts(_ slug: String, runId: Int?) async throws -> [ArtifactInfo] {
        let path = runId == nil
            ? "/repos/" + slug + "/actions/artifacts?per_page=30"
            : "/repos/" + slug + "/actions/runs/" + String(runId ?? 0) + "/artifacts"
        let (c, d) = try await call("GET", path)
        guard c == 200 else { throw apiError("Não consegui ler os artefatos", c, d) }
        let arr = (GitHub.json(d)["artifacts"] as? [[String: Any]]) ?? []
        return arr.compactMap { (x: [String: Any]) -> ArtifactInfo? in
            guard let id = x["id"] as? Int, let name = x["name"] as? String else { return nil }
            return ArtifactInfo(id: id, name: name,
                                size: (x["size_in_bytes"] as? Int) ?? 0,
                                expired: (x["expired"] as? Bool) ?? false,
                                created: (x["created_at"] as? String) ?? "")
        }
    }

    /// Baixa o artefato; devolve o .ipa/.apk se houver, senão o .zip.
    func downloadArtifact(_ slug: String, _ art: ArtifactInfo) async throws -> URL {
        let fm = FileManager.default
        let dl = Store.root.deletingLastPathComponent().appendingPathComponent("Downloads")
        try? fm.createDirectory(at: dl, withIntermediateDirectories: true)
        let data = try await authedFetch("/repos/" + slug + "/actions/artifacts/" + String(art.id) + "/zip")
        let prefix = slug.replacingOccurrences(of: "/", with: "-") + "-" + String(art.id)
        let zip = dl.appendingPathComponent(prefix + "-" + art.name + ".zip")
        try data.write(to: zip)
        let tmp = fm.temporaryDirectory.appendingPathComponent("art-" + UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        if (try? Zip.extract(zip, to: tmp)) != nil {
            for rel in Store.files(in: tmp) where rel.hasSuffix(".ipa") || rel.hasSuffix(".apk") {
                let out = dl.appendingPathComponent(prefix + "-" + (rel as NSString).lastPathComponent)
                try? fm.removeItem(at: out)
                if (try? fm.copyItem(at: tmp.appendingPathComponent(rel), to: out)) != nil { return out }
            }
        }
        return zip
    }

    func deleteArtifact(_ slug: String, _ id: Int) async throws {
        let (c, d) = try await call("DELETE", "/repos/" + slug + "/actions/artifacts/" + String(id))
        guard c == 204 else { throw apiError("Não consegui excluir o artefato", c, d) }
    }

    func rerun(_ slug: String, _ runId: Int) async throws {
        let (c, d) = try await call("POST", "/repos/" + slug + "/actions/runs/" + String(runId) + "/rerun")
        guard c == 201 else { throw apiError("Não consegui executar de novo", c, d) }
    }

    func deleteRun(_ slug: String, _ runId: Int) async throws {
        let (c, d) = try await call("DELETE", "/repos/" + slug + "/actions/runs/" + String(runId))
        guard c == 204 else { throw apiError("Não consegui excluir a execução", c, d) }
    }

    // MARK: baixar o projeto para o aparelho (rápido: um .zip só)

    func downloadRepo(slug: String, branch: String, lang: Lang, name: String, say: (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        let dir = Store.root.appendingPathComponent(lang.rawValue).appendingPathComponent(name)
        if fm.fileExists(atPath: dir.path) {
            throw GHError(msg: "Já existe um projeto chamado \"" + name + "\" em " + lang.title + ".")
        }
        say("Baixando " + slug + " (" + branch + ")…")
        let data = try await authedFetch("/repos/" + slug + "/zipball/" + encPath(branch))
        let tmp = fm.temporaryDirectory.appendingPathComponent("dl-" + UUID().uuidString + ".zip")
        try data.write(to: tmp)
        defer { try? fm.removeItem(at: tmp) }
        say("Descompactando…")
        do {
            _ = try Zip.extract(tmp, to: dir)
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        say("Ligando o projeto ao GitHub…")
        if let h = try? await headRef(slug, branch), let tree = try? await fetchTree(slug, h) {
            var s = GitState()
            s.remote = slug
            s.branch = branch
            s.base = tree
            s.baseCommit = h
            Repo.save(s, dir)
        }
        say("✓ Projeto baixado.")
        return dir
    }
}
