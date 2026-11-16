import Foundation

struct GHError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

@MainActor
final class GitHub: ObservableObject {
    @Published var user: String? = UserDefaults.standard.string(forKey: "gh_user")
    @Published var log: String = ""

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (Int, Data) {
        guard let t = UserDefaults.standard.string(forKey: "gh_token") else { throw GHError(msg: "Entre no GitHub primeiro.") }
        guard let url = URL(string: "https://api.github.com" + path) else { throw GHError(msg: "URL inválida") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private func json(_ d: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    func login(token: String) async throws {
        UserDefaults.standard.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gh_token")
        let (code, data) = try await call("GET", "/user")
        guard code == 200, let name = json(data)["login"] as? String else {
            UserDefaults.standard.removeObject(forKey: "gh_token")
            throw GHError(msg: "Token inválido (HTTP \(code)).")
        }
        UserDefaults.standard.set(name, forKey: "gh_user")
        user = name
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "gh_token")
        UserDefaults.standard.removeObject(forKey: "gh_user")
        user = nil
    }

    private func ensureRepo(_ repo: String) async throws -> String {
        guard let u = user else { throw GHError(msg: "Entre no GitHub primeiro.") }
        let (code, data) = try await call("GET", "/repos/\(u)/\(repo)")
        if code == 200 { return (json(data)["default_branch"] as? String) ?? "main" }
        if code == 404 {
            let (c2, d2) = try await call("POST", "/user/repos", body: ["name": repo, "private": true, "auto_init": true])
            guard c2 == 201 else { throw GHError(msg: "Não consegui criar o repositório (HTTP \(c2)).") }
            return (json(d2)["default_branch"] as? String) ?? "main"
        }
        throw GHError(msg: "Erro ao acessar o repositório (HTTP \(code)).")
    }

    func push(dir: URL, repo: String) async throws -> String {
        guard let u = user else { throw GHError(msg: "Entre no GitHub primeiro.") }
        let branch = try await ensureRepo(repo)
        let files = Store.files(in: dir)
        var n = 0
        for rel in files {
            log = "Enviando \(rel) (\(n + 1)/\(files.count))…"
            let data = try Data(contentsOf: dir.appendingPathComponent(rel))
            let enc = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel
            let path = "/repos/\(u)/\(repo)/contents/\(enc)"
            var body: [String: Any] = ["message": "CodeLab: \(rel)", "content": data.base64EncodedString(), "branch": branch]
            let (c, d) = try await call("GET", path + "?ref=\(branch)")
            if c == 200, let sha = json(d)["sha"] as? String { body["sha"] = sha }
            let (pc, _) = try await call("PUT", path, body: body)
            guard pc == 200 || pc == 201 else { throw GHError(msg: "Falha ao enviar \(rel) (HTTP \(pc)).") }
            n += 1
        }
        log = "Enviados \(n) arquivos para \(u)/\(repo)."
        return branch
    }

    private func latestRun(_ repo: String) async throws -> [String: Any]? {
        guard let u = user else { return nil }
        let (_, d) = try await call("GET", "/repos/\(u)/\(repo)/actions/runs?per_page=1")
        return (json(d)["workflow_runs"] as? [[String: Any]])?.first
    }

    func runAndWait(dir: URL, repo: String) async throws {
        guard let u = user else { throw GHError(msg: "Entre no GitHub primeiro.") }
        let branch = try await push(dir: dir, repo: repo)
        let prevId = (try await latestRun(repo))?["id"] as? Int
        let (dc, _) = try await call("POST", "/repos/\(u)/\(repo)/actions/workflows/build.yml/dispatches", body: ["ref": branch])
        guard dc == 204 else { throw GHError(msg: "Não consegui iniciar o workflow (HTTP \(dc)). Confira se o token tem permissão 'workflow'.") }
        log += "\nWorkflow iniciado. Aguardando…"
        var run: [String: Any]? = nil
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            if let r = try await latestRun(repo), (r["id"] as? Int) != prevId {
                run = r
                if (r["status"] as? String) == "completed" { break }
                log = "Status: \(r["status"] as? String ?? "?")…"
            }
        }
        guard let r = run, let runId = r["id"] as? Int else { throw GHError(msg: "Tempo esgotado esperando o workflow.") }
        let concl = r["conclusion"] as? String ?? "?"
        let url = r["html_url"] as? String ?? ""
        let (_, jd) = try await call("GET", "/repos/\(u)/\(repo)/actions/runs/\(runId)/jobs")
        var text = ""
        if let job = (json(jd)["jobs"] as? [[String: Any]])?.first, let jid = job["id"] as? Int {
            let (_, ld) = try await call("GET", "/repos/\(u)/\(repo)/actions/jobs/\(jid)/logs")
            let all = String(data: ld, encoding: .utf8) ?? ""
            text = all.components(separatedBy: "\n").suffix(80).joined(separator: "\n")
        }
        log = "Resultado: \(concl)\n\(url)\n\n\(text)"
    }
}
