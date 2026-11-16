import Foundation
import CryptoKit

struct LocalCommit: Codable {
    var id: String
    var message: String
    var files: [String: String]   // caminho -> sha do arquivo ("" = removido)
    var date: Date
}

struct GitState: Codable {
    var remote: String = ""
    var branch: String = "main"
    var base: [String: String] = [:]
    var baseCommit: String = ""
    var staged: [String] = []
    var commits: [LocalCommit] = []
}

struct GitStatus {
    var toCommit: [String: String] = [:]
    var notStaged: [String: String] = [:]
    var untracked: [String] = []
    var isClean: Bool { toCommit.isEmpty && notStaged.isEmpty && untracked.isEmpty }
}

enum Repo {
    static func stateURL(_ root: URL) -> URL {
        root.appendingPathComponent(".codelab/git.json")
    }

    static func isRepo(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: stateURL(root).path)
    }

    static func root(from dir: URL) -> URL? {
        var u = dir.standardizedFileURL
        let top = Store.root.standardizedFileURL.path
        while u.path == top || u.path.hasPrefix(top + "/") {
            if isRepo(u) { return u }
            if u.path == top { break }
            u = u.deletingLastPathComponent()
        }
        return nil
    }

    static func load(_ root: URL) -> GitState {
        guard let d = try? Data(contentsOf: stateURL(root)),
              let s = try? JSONDecoder().decode(GitState.self, from: d) else { return GitState() }
        return s
    }

    static func save(_ s: GitState, _ root: URL) {
        try? FileManager.default.createDirectory(at: root.appendingPathComponent(".codelab/objects"), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) {
            try? d.write(to: stateURL(root), options: .atomic)
        }
    }

    static func initRepo(_ root: URL) {
        if !isRepo(root) { save(GitState(), root) }
    }

    static func relPath(_ u: URL, _ root: URL) -> String {
        let a = u.standardizedFileURL.path
        let b = root.standardizedFileURL.path
        if a == b { return "" }
        if a.hasPrefix(b + "/") { return String(a.dropFirst(b.count + 1)) }
        return a
    }

    static func normalize(_ input: String, user: String?) -> String? {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "github.com/"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return nil }
        if s.contains("/") {
            return s.split(separator: "/").count == 2 ? s : nil
        }
        if let u = user { return u + "/" + s }
        return nil
    }

    // MARK: hashes

    static func blobSHA(_ data: Data) -> String {
        var h = Insecure.SHA1()
        h.update(data: Data("blob \(data.count)\0".utf8))
        h.update(data: data)
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func workingTree(_ root: URL) -> [String: String] {
        var m: [String: String] = [:]
        for p in Store.files(in: root) {
            if let d = try? Data(contentsOf: root.appendingPathComponent(p)) {
                m[p] = blobSHA(d)
            }
        }
        return m
    }

    /// Estado do último commit local (base do GitHub + commits pendentes)
    static func head(_ s: GitState) -> [String: String] {
        var t = s.base
        for c in s.commits {
            for (p, sha) in c.files {
                if sha.isEmpty { t.removeValue(forKey: p) } else { t[p] = sha }
            }
        }
        return t
    }

    static func changes(_ root: URL, _ s: GitState) -> [String: String] {
        let work = workingTree(root)
        let hd = head(s)
        var ch: [String: String] = [:]
        for (p, sha) in work {
            if let h = hd[p] {
                if h != sha { ch[p] = "modificado" }
            } else {
                ch[p] = "novo arquivo"
            }
        }
        for p in hd.keys where work[p] == nil {
            ch[p] = "removido"
        }
        return ch
    }

    static func status(_ root: URL, _ s: GitState) -> GitStatus {
        let ch = changes(root, s)
        var st = GitStatus()
        for (p, kind) in ch {
            if s.staged.contains(p) {
                st.toCommit[p] = kind
            } else if kind == "novo arquivo" {
                st.untracked.append(p)
            } else {
                st.notStaged[p] = kind
            }
        }
        st.untracked.sort()
        return st
    }

    /// git add. Retorna quantos arquivos mudados foram preparados.
    @discardableResult
    static func stage(_ root: URL, _ s: inout GitState, prefix: String, includeNew: Bool) -> Int {
        let ch = changes(root, s)
        var n = 0
        for (p, kind) in ch {
            if !prefix.isEmpty && !(p == prefix || p.hasPrefix(prefix + "/")) { continue }
            if kind == "novo arquivo" && !includeNew { continue }
            if !s.staged.contains(p) { s.staged.append(p) }
            n += 1
        }
        save(s, root)
        return n
    }

    @discardableResult
    static func commit(_ root: URL, _ s: inout GitState, message: String) throws -> LocalCommit {
        let work = workingTree(root)
        let hd = head(s)
        var files: [String: String] = [:]
        for p in s.staged {
            if let sha = work[p] {
                if hd[p] != sha { files[p] = sha }
            } else if hd[p] != nil {
                files[p] = ""
            }
        }
        guard !files.isEmpty else { throw GHError(msg: "Nada preparado para commitar.") }
        let objs = root.appendingPathComponent(".codelab/objects")
        try FileManager.default.createDirectory(at: objs, withIntermediateDirectories: true)
        for (p, sha) in files where !sha.isEmpty {
            let dest = objs.appendingPathComponent(sha)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: root.appendingPathComponent(p), to: dest)
            }
        }
        let now = Date()
        let seed = message + String(now.timeIntervalSince1970)
        let id = String(blobSHA(Data(seed.utf8)).prefix(7))
        let c = LocalCommit(id: id, message: message, files: files, date: now)
        s.commits.append(c)
        s.staged = []
        save(s, root)
        return c
    }
}
