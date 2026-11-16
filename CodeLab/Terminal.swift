import SwiftUI

struct CmdInfo {
    let cmd: String      // texto mostrado
    let insert: String   // texto colocado no campo
    let desc: String
}

enum Catalog {
    static let git: [CmdInfo] = [
        CmdInfo(cmd: "git init", insert: "git init", desc: "Transforma a pasta atual em repositório git"),
        CmdInfo(cmd: "git clone usuario/repo", insert: "git clone ", desc: "Baixa um repositório do GitHub"),
        CmdInfo(cmd: "git remote add origin usuario/repo", insert: "git remote add origin ", desc: "Liga a pasta a um repositório do GitHub"),
        CmdInfo(cmd: "git remote -v", insert: "git remote -v", desc: "Mostra a qual repositório a pasta está ligada"),
        CmdInfo(cmd: "git status", insert: "git status", desc: "Mostra o que mudou e o que falta fazer"),
        CmdInfo(cmd: "git add .", insert: "git add .", desc: "Prepara todas as mudanças para o commit"),
        CmdInfo(cmd: "git add arquivo", insert: "git add ", desc: "Prepara só um arquivo"),
        CmdInfo(cmd: "git commit -m \"msg\"", insert: "git commit -m \"", desc: "Registra as mudanças preparadas, com uma mensagem"),
        CmdInfo(cmd: "git commit -am \"msg\"", insert: "git commit -am \"", desc: "Prepara os arquivos já rastreados e registra"),
        CmdInfo(cmd: "git push", insert: "git push", desc: "Envia seus commits para o GitHub"),
        CmdInfo(cmd: "git pull", insert: "git pull", desc: "Baixa as novidades do GitHub"),
        CmdInfo(cmd: "git log", insert: "git log", desc: "Mostra o histórico de commits"),
        CmdInfo(cmd: "git diff", insert: "git diff", desc: "Resumo do que mudou"),
        CmdInfo(cmd: "git branch", insert: "git branch", desc: "Mostra a branch atual"),
        CmdInfo(cmd: "git branch -M main", insert: "git branch -M main", desc: "Renomeia a branch atual"),
        CmdInfo(cmd: "git reset", insert: "git reset", desc: "Desfaz o git add (tira do preparado)"),
        CmdInfo(cmd: "git rm arquivo", insert: "git rm ", desc: "Apaga o arquivo e prepara a remoção"),
        CmdInfo(cmd: "git config user.name \"Nome\"", insert: "git config user.name \"", desc: "Aceito, mas o autor é sempre a sua conta do GitHub")
    ]

    static let run: [CmdInfo] = [
        CmdInfo(cmd: "run", insert: "run", desc: "Compila/executa no GitHub e mostra a saída (use depois do git push)")
    ]

    static let files: [CmdInfo] = [
        CmdInfo(cmd: "ls", insert: "ls", desc: "Lista arquivos (ls -a mostra os ocultos)"),
        CmdInfo(cmd: "cd pasta", insert: "cd ", desc: "Entra numa pasta (cd .. volta, cd ~ vai ao início)"),
        CmdInfo(cmd: "pwd", insert: "pwd", desc: "Mostra a pasta atual"),
        CmdInfo(cmd: "tree", insert: "tree", desc: "Mostra as pastas em árvore"),
        CmdInfo(cmd: "cat arquivo", insert: "cat ", desc: "Mostra o conteúdo de um arquivo"),
        CmdInfo(cmd: "head arquivo", insert: "head ", desc: "Primeiras linhas (head -n 5 arquivo)"),
        CmdInfo(cmd: "tail arquivo", insert: "tail ", desc: "Últimas linhas"),
        CmdInfo(cmd: "grep texto arquivo", insert: "grep ", desc: "Procura texto (grep -r texto . procura em tudo)"),
        CmdInfo(cmd: "mkdir pasta", insert: "mkdir ", desc: "Cria uma pasta"),
        CmdInfo(cmd: "touch arquivo", insert: "touch ", desc: "Cria um arquivo vazio"),
        CmdInfo(cmd: "echo \"texto\" > arquivo", insert: "echo \"", desc: "Escreve texto num arquivo (>> acrescenta)"),
        CmdInfo(cmd: "rm arquivo", insert: "rm ", desc: "Apaga (rm -r apaga pasta)"),
        CmdInfo(cmd: "mv origem destino", insert: "mv ", desc: "Move ou renomeia"),
        CmdInfo(cmd: "cp origem destino", insert: "cp ", desc: "Copia (cp -r copia pasta)"),
        CmdInfo(cmd: "wc arquivo", insert: "wc ", desc: "Conta linhas, palavras e bytes"),
        CmdInfo(cmd: "clear", insert: "clear", desc: "Limpa a tela")
    ]

    static let all: [CmdInfo] = git + run + files

    static let quick: [CmdInfo] = [
        CmdInfo(cmd: "git status", insert: "git status", desc: ""),
        CmdInfo(cmd: "git add .", insert: "git add .", desc: ""),
        CmdInfo(cmd: "git commit -m \"msg\"", insert: "git commit -m \"", desc: ""),
        CmdInfo(cmd: "git push", insert: "git push", desc: ""),
        CmdInfo(cmd: "git pull", insert: "git pull", desc: ""),
        CmdInfo(cmd: "run", insert: "run", desc: ""),
        CmdInfo(cmd: "ls", insert: "ls", desc: "")
    ]

    static let localNames = ["help", "pwd", "ls", "cd", "cat", "head", "tail", "grep", "tree", "mkdir", "touch",
                             "rm", "mv", "cp", "echo", "wc", "clear", "date", "whoami", "history", "git", "run"]
    static let gitSubs = ["init", "clone", "remote", "status", "add", "commit", "push", "pull", "log", "diff",
                          "branch", "reset", "rm", "config", "help"]
    static let unsupportedGit = ["checkout", "switch", "restore", "merge", "rebase", "stash", "fetch", "tag", "show", "cherry-pick"]
}

struct Hint {
    let text: String
    let fix: String?
}

@MainActor
final class TerminalModel: ObservableObject {
    @Published var out = "CodeLab terminal. Digite help ou toque no ? para ver os comandos.\n"
    @Published var prompt = "~ $"
    @Published var busy = false
    @Published var next: CmdInfo? = nil

    var cwd = Store.root
    var gh: GitHub?
    var started = false
    var history: [String] = []
    private let fm = FileManager.default

    func say(_ s: String) {
        out += s + "\n"
        if out.count > 30000 { out = String(out.suffix(20000)) }
    }

    // MARK: utilidades de texto

    static func tokens(_ s: String) -> [String] {
        var res: [String] = []
        var cur = ""
        var q: Character? = nil
        var has = false
        for ch in s {
            if let qq = q {
                if ch == qq { q = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                q = ch
                has = true
            } else if ch == " " || ch == "\t" {
                if !cur.isEmpty || has {
                    res.append(cur)
                    cur = ""
                    has = false
                }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty || has { res.append(cur) }
        return res
    }

    static func splitAnd(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var q: Character? = nil
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let qq = q {
                if c == qq { q = nil }
                cur.append(c)
            } else if c == "\"" || c == "'" {
                q = c
                cur.append(c)
            } else if c == "&" && i + 1 < chars.count && chars[i + 1] == "&" {
                parts.append(cur)
                cur = ""
                i += 1
            } else {
                cur.append(c)
            }
            i += 1
        }
        parts.append(cur)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func lev(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [Int](repeating: 0, count: y.count + 1)
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[y.count]
    }

    static func closest(_ w: String, _ list: [String]) -> String? {
        var best: String? = nil
        var bd = 99
        for c in list {
            let d = lev(w.lowercased(), c)
            if d <= 2 && d < w.count && d < bd {
                best = c
                bd = d
            }
        }
        return best
    }

    func hasFlag(_ flags: [String], _ c: Character) -> Bool {
        flags.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains(c) }
    }

    func resolve(_ p: String) -> URL? {
        let base = Store.root
        var u: URL
        if p == "~" {
            u = base
        } else if p.hasPrefix("~/") {
            u = base.appendingPathComponent(String(p.dropFirst(2)))
        } else if p.hasPrefix("/") {
            u = base.appendingPathComponent(String(p.dropFirst()))
        } else {
            u = cwd.appendingPathComponent(p)
        }
        u = u.standardizedFileURL
        let root = base.standardizedFileURL.path
        if u.path == root || u.path.hasPrefix(root + "/") { return u }
        return nil
    }

    // MARK: estado, dicas e sugestões

    func refresh() {
        let rel = Repo.relPath(cwd, Store.root)
        var p = rel.isEmpty ? "~" : "~/" + rel
        if let root = Repo.root(from: cwd) { p += " (" + Repo.load(root).branch + ")" }
        prompt = p + " $"
        next = computeNext()
    }

    func computeNext() -> CmdInfo? {
        if cwd.standardizedFileURL.path == Store.root.standardizedFileURL.path {
            return CmdInfo(cmd: "ls", insert: "ls", desc: "Veja seus projetos e entre em um com cd pasta")
        }
        guard let root = Repo.root(from: cwd) else {
            return CmdInfo(cmd: "git init", insert: "git init", desc: "Esta pasta ainda não é um repositório")
        }
        let s = Repo.load(root)
        if s.remote.isEmpty {
            return CmdInfo(cmd: "git remote add origin usuario/repo", insert: "git remote add origin ", desc: "Ligue a pasta a um repositório do GitHub")
        }
        let st = Repo.status(root, s)
        if !st.toCommit.isEmpty {
            return CmdInfo(cmd: "git commit -m \"msg\"", insert: "git commit -m \"", desc: "Há mudanças preparadas: registre com uma mensagem")
        }
        if !st.notStaged.isEmpty || !st.untracked.isEmpty {
            return CmdInfo(cmd: "git add .", insert: "git add .", desc: "Há arquivos mudados: prepare para o commit")
        }
        if !s.commits.isEmpty {
            return CmdInfo(cmd: "git push", insert: "git push", desc: "Há commits que ainda não foram para o GitHub")
        }
        return CmdInfo(cmd: "run", insert: "run", desc: "Tudo enviado. Compile/execute no GitHub")
    }

    func suggestions(for input: String) -> [CmdInfo] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            var list: [CmdInfo] = []
            if let n = next { list.append(n) }
            for c in Catalog.quick where c.cmd != next?.cmd { list.append(c) }
            return list
        }
        let found = Catalog.all.filter { $0.cmd.lowercased().hasPrefix(q) || $0.insert.lowercased().hasPrefix(q) }
        return Array(found.prefix(8))
    }

    func hint(for input: String) -> Hint? {
        let s = input.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        let t = TerminalModel.tokens(input)
        guard let first = t.first else { return nil }
        let endsSpace = input.hasSuffix(" ")

        if t.count == 1 && !endsSpace {
            if Catalog.localNames.contains(where: { $0.hasPrefix(first) }) { return nil }
            if let c = TerminalModel.closest(first, Catalog.localNames) {
                return Hint(text: "Você quis dizer \"\(c)\"?", fix: c)
            }
            return nil
        }
        if first != "git" {
            if !Catalog.localNames.contains(first), let c = TerminalModel.closest(first, Catalog.localNames) {
                let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let rest = parts.count > 1 ? " " + String(parts[1]) : ""
                return Hint(text: "Você quis dizer \"\(c)\"?", fix: c + rest)
            }
            return nil
        }
        if t.count == 1 { return nil }

        let sub = t[1]
        let parts = s.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        let rest = parts.count > 2 ? " " + String(parts[2]) : ""
        let known = Catalog.gitSubs + Catalog.unsupportedGit

        if t.count == 2 && !endsSpace {
            if known.contains(where: { $0.hasPrefix(sub) }) { return nil }
            if let c = TerminalModel.closest(sub, known) {
                return Hint(text: "Você quis dizer \"git \(c)\"?", fix: "git " + c + rest)
            }
            return Hint(text: "\"\(sub)\" não é um comando do git. Toque no ? para ver a lista.", fix: nil)
        }
        if !known.contains(sub) {
            if let c = TerminalModel.closest(sub, known) {
                return Hint(text: "Você quis dizer \"git \(c)\"?", fix: "git " + c + rest)
            }
            return Hint(text: "\"\(sub)\" não é um comando do git.", fix: nil)
        }
        if sub == "commit" {
            let hasM = t.contains { $0 == "-m" || $0 == "-am" || $0 == "-ma" || $0.hasPrefix("--message") }
            if !hasM { return Hint(text: "Falta a mensagem: git commit -m \"o que você fez\"", fix: nil) }
        }
        if sub == "add" && t.count == 2 {
            return Hint(text: "Diga o que preparar: git add .  (tudo)  ou  git add arquivo", fix: "git add .")
        }
        if sub == "remote" && t.count >= 2 && !t.contains("-v") && t.count < 4 && t.contains("add") {
            return Hint(text: "Formato: git remote add origin usuario/repositorio", fix: nil)
        }
        if sub == "clone" && t.count == 2 {
            return Hint(text: "Formato: git clone usuario/repositorio", fix: nil)
        }
        if Catalog.unsupportedGit.contains(sub) {
            return Hint(text: "git \(sub) ainda não é suportado no CodeLab.", fix: nil)
        }
        return nil
    }

    // MARK: execução

    func submit(_ line: String) {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.isEmpty { return }
        if busy {
            say("(aguarde o comando anterior terminar)")
            return
        }
        history.append(l)
        out += prompt + " " + l + "\n"
        busy = true
        Task {
            for part in TerminalModel.splitAnd(l) {
                let ok = await execute(TerminalModel.tokens(part))
                if !ok { break }
            }
            busy = false
            refresh()
        }
    }

    func execute(_ t: [String]) async -> Bool {
        guard let cmd = t.first else { return true }
        let args = Array(t.dropFirst())
        if cmd == "git" { return await git(args) }
        if cmd == "run" { return await runRemote() }
        if cmd == "help" { help(); return true }
        if cmd == "clear" { out = ""; return true }
        if let ok = local(cmd, args) { return ok }
        unknown(cmd)
        return false
    }

    func unknown(_ cmd: String) {
        let noDevice = ["sudo", "apt", "apt-get", "brew", "pip", "pip3", "npm", "yum"]
        let build = ["gcc", "g++", "clang", "make", "cmake", "javac", "java", "kotlinc", "kotlin", "python",
                     "python3", "node", "godot", "gradle", "swift", "swiftc", "xcodebuild"]
        if noDevice.contains(cmd) {
            say("\(cmd): não existe no iPhone (o iOS não tem instalador de pacotes). Os compiladores já ficam no GitHub: veja o comando run.")
        } else if build.contains(cmd) {
            say("\(cmd): compilar e executar acontece no GitHub, não aqui.")
            say("Fluxo: git add .  →  git commit -m \"msg\"  →  git push  →  run")
        } else if let c = TerminalModel.closest(cmd, Catalog.localNames) {
            say("\(cmd): comando não encontrado. Você quis dizer \"\(c)\"?")
        } else {
            say("\(cmd): comando não encontrado. Digite help.")
        }
    }

    func help() {
        say("""
        GITHUB (o terminal fala direto com o GitHub, sem precisar de git instalado)
          git init                      cria repositório na pasta atual
          git clone usuario/repo        baixa um repositório
          git remote add origin repo    liga a pasta a um repositório
          git status                    o que mudou
          git add . | arquivo           prepara mudanças
          git commit -m "mensagem"      registra
          git push | git pull           envia / baixa
          git log | git diff | git branch | git reset | git rm
          run                           compila/executa no GitHub e mostra a saída

        ARQUIVOS
          ls [-a]  cd  pwd  tree  cat  head  tail  grep  wc
          mkdir  touch  rm [-r]  mv  cp [-r]  echo "texto" > arquivo
          clear  date  whoami  history

        Dica: use && para encadear:  git add . && git commit -m "ok" && git push
        Toque no ? para ver a lista completa e as dicas aparecem sozinhas enquanto você digita.
        """)
    }

    func gitHelp() {
        for c in Catalog.git { say("  " + c.cmd + "\n      " + c.desc) }
    }

    // MARK: comandos locais

    func local(_ cmd: String, _ args: [String]) -> Bool? {
        let flags = args.filter { $0.hasPrefix("-") && $0.count > 1 }
        let paths = args.filter { !($0.hasPrefix("-") && $0.count > 1) }
        switch cmd {
        case "pwd":
            let rel = Repo.relPath(cwd, Store.root)
            say(rel.isEmpty ? "~" : "~/" + rel)
            return true

        case "ls":
            let showAll = hasFlag(flags, "a")
            let u: URL = paths.first.flatMap { resolve($0) } ?? cwd
            guard let names = try? fm.contentsOfDirectory(atPath: u.path) else {
                say("ls: caminho não encontrado")
                return false
            }
            var items: [String] = []
            for n in names.sorted() {
                if !showAll && n.hasPrefix(".") { continue }
                var d: ObjCBool = false
                fm.fileExists(atPath: u.appendingPathComponent(n).path, isDirectory: &d)
                items.append(d.boolValue ? n + "/" : n)
            }
            say(items.isEmpty ? "(vazio)" : items.joined(separator: "  "))
            return true

        case "cd":
            if paths.isEmpty {
                cwd = Store.root
                return true
            }
            guard let u = resolve(paths[0]) else {
                say("cd: fora da pasta de projetos")
                return false
            }
            var d: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &d), d.boolValue {
                cwd = u
                return true
            }
            say("cd: \(paths[0]): pasta não encontrada")
            return false

        case "cat":
            if paths.isEmpty {
                say("uso: cat arquivo")
                return false
            }
            for p in paths {
                guard let u = resolve(p), let s = try? String(contentsOf: u) else {
                    say("cat: \(p): não encontrado")
                    return false
                }
                say(s.hasSuffix("\n") ? String(s.dropLast()) : s)
            }
            return true

        case "head", "tail":
            var n = 10
            var list: [String] = []
            var i = 0
            while i < args.count {
                let a = args[i]
                if a == "-n", i + 1 < args.count {
                    n = Int(args[i + 1]) ?? 10
                    i += 2
                    continue
                }
                if a.hasPrefix("-"), let v = Int(a.dropFirst()) {
                    n = v
                    i += 1
                    continue
                }
                list.append(a)
                i += 1
            }
            if list.isEmpty {
                say("uso: \(cmd) [-n N] arquivo")
                return false
            }
            for f in list {
                guard let u = resolve(f), let s = try? String(contentsOf: u) else {
                    say("\(cmd): \(f): não encontrado")
                    return false
                }
                var ls = s.components(separatedBy: "\n")
                if ls.last == "" { ls.removeLast() }
                let picked = cmd == "head" ? Array(ls.prefix(n)) : Array(ls.suffix(n))
                say(picked.joined(separator: "\n"))
            }
            return true

        case "grep":
            let ic = hasFlag(flags, "i")
            let rec = hasFlag(flags, "r")
            guard !paths.isEmpty else {
                say("uso: grep [-i] [-r] texto arquivo...")
                return false
            }
            let pat = paths[0]
            let given = Array(paths.dropFirst())
            var targets: [URL] = []
            if given.isEmpty && rec { targets = [cwd] } else { targets = given.compactMap { resolve($0) } }
            var found = 0
            for t in targets {
                var d: ObjCBool = false
                guard fm.fileExists(atPath: t.path, isDirectory: &d) else { continue }
                var list: [URL] = [t]
                if d.boolValue {
                    list = rec ? Store.files(in: t).map { t.appendingPathComponent($0) } : []
                }
                for f in list {
                    guard let s = try? String(contentsOf: f) else { continue }
                    for (i, ln) in s.components(separatedBy: "\n").enumerated() {
                        let hit = ic ? ln.lowercased().contains(pat.lowercased()) : ln.contains(pat)
                        if hit {
                            found += 1
                            say("\(Repo.relPath(f, cwd)):\(i + 1): \(ln)")
                        }
                    }
                }
            }
            if found == 0 { say("(nenhuma ocorrência)") }
            return true

        case "tree":
            let u: URL = paths.first.flatMap { resolve($0) } ?? cwd
            say(u.lastPathComponent + "/")
            tree(u, "")
            return true

        case "mkdir":
            if paths.isEmpty {
                say("uso: mkdir pasta")
                return false
            }
            var ok = true
            for p in paths {
                guard let u = resolve(p) else {
                    say("mkdir: caminho fora da pasta de projetos")
                    ok = false
                    continue
                }
                do { try fm.createDirectory(at: u, withIntermediateDirectories: true) }
                catch {
                    say("mkdir: \(error.localizedDescription)")
                    ok = false
                }
            }
            return ok

        case "touch":
            if paths.isEmpty {
                say("uso: touch arquivo")
                return false
            }
            for p in paths {
                guard let u = resolve(p) else {
                    say("touch: caminho fora da pasta de projetos")
                    return false
                }
                try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) }
            }
            return true

        case "rm":
            let rec = hasFlag(flags, "r") || hasFlag(flags, "R")
            if paths.isEmpty {
                say("uso: rm [-r] caminho")
                return false
            }
            var ok = true
            for p in paths {
                guard let u = resolve(p), u.path != Store.root.standardizedFileURL.path else {
                    say("rm: não permitido: \(p)")
                    ok = false
                    continue
                }
                var d: ObjCBool = false
                guard fm.fileExists(atPath: u.path, isDirectory: &d) else {
                    say("rm: \(p): não encontrado")
                    ok = false
                    continue
                }
                if d.boolValue && !rec {
                    say("rm: \(p) é uma pasta (use rm -r)")
                    ok = false
                    continue
                }
                do { try fm.removeItem(at: u) }
                catch {
                    say("rm: \(error.localizedDescription)")
                    ok = false
                }
            }
            if !fm.fileExists(atPath: cwd.path) { cwd = Store.root }
            return ok

        case "mv", "cp":
            guard paths.count == 2, let a = resolve(paths[0]), var b = resolve(paths[1]) else {
                say("uso: \(cmd) origem destino")
                return false
            }
            var dd: ObjCBool = false
            if fm.fileExists(atPath: b.path, isDirectory: &dd), dd.boolValue {
                b = b.appendingPathComponent(a.lastPathComponent)
            }
            var sd: ObjCBool = false
            fm.fileExists(atPath: a.path, isDirectory: &sd)
            if cmd == "cp" && sd.boolValue && !(hasFlag(flags, "r") || hasFlag(flags, "R")) {
                say("cp: \(paths[0]) é uma pasta (use cp -r)")
                return false
            }
            do {
                if cmd == "mv" { try fm.moveItem(at: a, to: b) } else { try fm.copyItem(at: a, to: b) }
            } catch {
                say("\(cmd): \(error.localizedDescription)")
                return false
            }
            return true

        case "echo":
            if let i = args.firstIndex(where: { $0 == ">" || $0 == ">>" }) {
                guard i + 1 < args.count, let u = resolve(args[i + 1]) else {
                    say("uso: echo \"texto\" > arquivo")
                    return false
                }
                let text = args[..<i].joined(separator: " ") + "\n"
                try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                if args[i] == ">>", let old = try? String(contentsOf: u) {
                    try? (old + text).write(to: u, atomically: true, encoding: .utf8)
                } else {
                    try? text.write(to: u, atomically: true, encoding: .utf8)
                }
                return true
            }
            say(args.joined(separator: " "))
            return true

        case "wc":
            if paths.isEmpty {
                say("uso: wc arquivo")
                return false
            }
            for p in paths {
                guard let u = resolve(p), let s = try? String(contentsOf: u) else {
                    say("wc: \(p): não encontrado")
                    return false
                }
                let lines = s.components(separatedBy: "\n").count - (s.hasSuffix("\n") ? 1 : 0)
                let words = s.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
                say("\(lines) linhas  \(words) palavras  \(s.utf8.count) bytes  \(p)")
            }
            return true

        case "date":
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateStyle = .full
            f.timeStyle = .medium
            say(f.string(from: Date()))
            return true

        case "whoami":
            if let u = gh?.user { say("@" + u) } else { say("(não conectado ao GitHub)") }
            return true

        case "history":
            for (i, h) in history.enumerated() { say("\(i + 1)  \(h)") }
            return true

        case "nano", "vim", "vi", "code", "edit":
            say("\(cmd): para editar use o editor do app (abra o projeto e toque no arquivo).")
            say("Pelo terminal você pode escrever com:  echo \"texto\" > arquivo")
            return false

        default:
            return nil
        }
    }

    func tree(_ u: URL, _ prefix: String) {
        let names = ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for (i, n) in names.enumerated() {
            let last = i == names.count - 1
            let child = u.appendingPathComponent(n)
            var d: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &d)
            say(prefix + (last ? "└── " : "├── ") + n + (d.boolValue ? "/" : ""))
            if d.boolValue { tree(child, prefix + (last ? "    " : "│   ")) }
        }
    }

    // MARK: git

    func gitUnknown(_ sub: String) {
        if let c = TerminalModel.closest(sub, Catalog.gitSubs + Catalog.unsupportedGit) {
            say("git: '\(sub)' não é um comando. Você quis dizer 'git \(c)'?")
        } else {
            say("git: '\(sub)' não é um comando. Digite git help.")
        }
    }

    func gitInit() -> Bool {
        if cwd.standardizedFileURL.path == Store.root.standardizedFileURL.path {
            say("Entre numa pasta de projeto primeiro (ex: cd cpp/meuprojeto).")
            return false
        }
        if let r = Repo.root(from: cwd) {
            let rel = Repo.relPath(r, Store.root)
            say("Já existe um repositório em ~/\(rel)")
            return false
        }
        Repo.initRepo(cwd)
        say("Repositório criado nesta pasta.")
        say("Próximo: git remote add origin usuario/repositorio")
        return true
    }

    func gitClone(_ paths: [String]) async -> Bool {
        guard let g = gh, g.user != nil else {
            say("Entre no GitHub primeiro (botão no topo do menu).")
            return false
        }
        guard let first = paths.first else {
            say("uso: git clone usuario/repositorio [pasta]")
            return false
        }
        guard let slug = Repo.normalize(first, user: g.user) else {
            say("Repositório inválido. Use usuario/repositorio.")
            return false
        }
        let name = paths.count > 1 ? paths[1] : String(slug.split(separator: "/").last ?? "repo")
        guard let dir = resolve(name) else {
            say("Pasta fora da área de projetos.")
            return false
        }
        if fm.fileExists(atPath: dir.path) {
            say("fatal: '\(name)' já existe.")
            return false
        }
        do {
            try await g.clone(slug, into: dir, say: { self.say($0) })
            say("Pronto. Entre com: cd \(name)")
            return true
        } catch {
            try? fm.removeItem(at: dir)
            say("erro: " + error.localizedDescription)
            return false
        }
    }

    func git(_ args: [String]) async -> Bool {
        guard let sub = args.first else {
            gitHelp()
            return true
        }
        let rest = Array(args.dropFirst())
        let flags = rest.filter { $0.hasPrefix("-") }
        let paths = rest.filter { !$0.hasPrefix("-") }

        switch sub {
        case "help", "--help", "-h":
            gitHelp()
            return true
        case "init":
            return gitInit()
        case "clone":
            return await gitClone(paths)
        case "config":
            say("ok (o CodeLab usa a sua conta do GitHub como autor dos commits)")
            return true
        default:
            break
        }

        guard let root = Repo.root(from: cwd) else {
            if Catalog.gitSubs.contains(sub) || Catalog.unsupportedGit.contains(sub) {
                say("fatal: esta pasta não é um repositório git.")
                say("Use: git init   (ou git clone usuario/repo)")
            } else {
                gitUnknown(sub)
            }
            return false
        }
        var s = Repo.load(root)

        switch sub {
        case "status":
            say("Na branch \(s.branch)")
            say(s.remote.isEmpty ? "Remoto: (nenhum)  → git remote add origin usuario/repo" : "Remoto: \(s.remote)")
            if !s.commits.isEmpty { say("Você tem \(s.commits.count) commit(s) para enviar (git push).") }
            let st = Repo.status(root, s)
            if st.isClean {
                say(s.commits.isEmpty ? "\nNada para commitar, tudo limpo." : "\nNada novo para commitar.")
                return true
            }
            if !st.toCommit.isEmpty {
                say("\nPreparado para o commit:")
                for (p, k) in st.toCommit.sorted(by: { $0.key < $1.key }) { say("  \(k): \(p)") }
                say("  (use git commit -m \"mensagem\")")
            }
            if !st.notStaged.isEmpty {
                say("\nMudou, mas não está preparado:")
                for (p, k) in st.notStaged.sorted(by: { $0.key < $1.key }) { say("  \(k): \(p)") }
                say("  (use git add . para preparar)")
            }
            if !st.untracked.isEmpty {
                say("\nArquivos novos ainda não rastreados:")
                for p in st.untracked { say("  \(p)") }
                say("  (use git add . para incluir)")
            }
            return true

        case "add":
            let all = flags.contains("--all") || hasFlag(flags, "A")
            if paths.isEmpty && !all {
                say("Diga o que preparar: git add .   ou   git add arquivo")
                return false
            }
            var n = 0
            if all { n = Repo.stage(root, &s, prefix: "", includeNew: true) }
            for p in paths {
                if p == "." {
                    n += Repo.stage(root, &s, prefix: Repo.relPath(cwd, root), includeNew: true)
                    continue
                }
                guard let u = resolve(p) else {
                    say("fatal: caminho fora do projeto: \(p)")
                    return false
                }
                let rel = Repo.relPath(u, root)
                let before = n
                n += Repo.stage(root, &s, prefix: rel, includeNew: true)
                if n == before && !fm.fileExists(atPath: u.path) && Repo.head(s)[rel] == nil {
                    say("fatal: '\(p)' não corresponde a nenhum arquivo")
                    return false
                }
            }
            say(n == 0 ? "Nada mudou para preparar." : "\(n) arquivo(s) preparado(s).")
            return true

        case "commit":
            var stageTracked = false
            var words: [String] = []
            var i = 0
            while i < rest.count {
                let a = rest[i]
                if a == "-m" || a == "-am" || a == "-ma" {
                    if a != "-m" { stageTracked = true }
                    i += 1
                    while i < rest.count && !rest[i].hasPrefix("-") {
                        words.append(rest[i])
                        i += 1
                    }
                    continue
                }
                if a == "-a" || a == "--all" {
                    stageTracked = true
                } else if a.hasPrefix("--message=") {
                    words.append(String(a.dropFirst(10)))
                }
                i += 1
            }
            if words.isEmpty {
                say("Falta a mensagem. Use: git commit -m \"o que você fez\"")
                return false
            }
            let message = words.joined(separator: " ")
            if stageTracked { Repo.stage(root, &s, prefix: "", includeNew: false) }
            do {
                let c = try Repo.commit(root, &s, message: message)
                say("[\(s.branch) \(c.id)] \(message)")
                say(" \(c.files.count) arquivo(s) alterado(s). Para enviar: git push")
                return true
            } catch {
                say("Nada preparado para commitar.")
                let st = Repo.status(root, s)
                if !st.isClean { say("Use: git add .   e depois   git commit -m \"mensagem\"") }
                return false
            }

        case "push":
            guard let g = gh else {
                say("GitHub indisponível.")
                return false
            }
            do {
                try await g.push(root: root, say: { self.say($0) })
                return true
            } catch {
                say("erro: " + error.localizedDescription)
                return false
            }

        case "pull":
            guard let g = gh else {
                say("GitHub indisponível.")
                return false
            }
            do {
                try await g.pull(root: root, say: { self.say($0) })
                return true
            } catch {
                say("erro: " + error.localizedDescription)
                return false
            }

        case "log":
            for c in s.commits.reversed() { say("* \(c.id) \(c.message)   (local, ainda não enviado)") }
            if let g = gh, g.user != nil, !s.remote.isEmpty {
                do {
                    let lines = try await g.remoteLog(root: root, count: 10)
                    for l in lines { say("  " + l) }
                    if lines.isEmpty && s.commits.isEmpty { say("(sem histórico)") }
                } catch {
                    say("log: " + error.localizedDescription)
                }
            } else if s.commits.isEmpty {
                say("Nenhum commit ainda.")
            }
            return true

        case "diff":
            let ch = Repo.changes(root, s)
            if ch.isEmpty {
                say("Sem mudanças.")
            } else {
                for (p, k) in ch.sorted(by: { $0.key < $1.key }) { say("\(k): \(p)") }
                say("(resumo por arquivo; o CodeLab ainda não mostra linha a linha)")
            }
            return true

        case "remote":
            let sub2 = paths.first ?? ""
            if sub2 == "" || sub2 == "show" {
                if s.remote.isEmpty {
                    say("(nenhum remoto)  use: git remote add origin usuario/repo")
                } else if flags.contains("-v") {
                    say("origin\t\(s.remote) (fetch)")
                    say("origin\t\(s.remote) (push)")
                } else {
                    say("origin")
                }
                return true
            }
            if sub2 == "add" || sub2 == "set-url" {
                guard paths.count >= 3 else {
                    say("uso: git remote add origin usuario/repositorio")
                    return false
                }
                guard paths[1] == "origin" else {
                    say("O CodeLab só suporta o remoto chamado origin.")
                    return false
                }
                guard let slug = Repo.normalize(paths[2], user: gh?.user) else {
                    say("Repositório inválido. Use usuario/repositorio (ou só o nome, se for seu).")
                    return false
                }
                if sub2 == "add" && !s.remote.isEmpty {
                    say("erro: o remoto origin já existe (\(s.remote)). Use git remote set-url origin ...")
                    return false
                }
                s.remote = slug
                s.baseCommit = ""
                Repo.save(s, root)
                say("origin → \(slug)")
                return true
            }
            if sub2 == "remove" || sub2 == "rm" {
                s.remote = ""
                Repo.save(s, root)
                say("remoto removido")
                return true
            }
            say("uso: git remote -v | add origin repo | set-url origin repo | remove origin")
            return false

        case "branch":
            if flags.contains("-M") || flags.contains("-m") {
                guard let nm = paths.first else {
                    say("uso: git branch -M nome")
                    return false
                }
                s.branch = nm
                s.baseCommit = ""
                Repo.save(s, root)
                say("branch renomeada para \(nm)")
                return true
            }
            if let nm = paths.first {
                say("O CodeLab usa uma branch por pasta. Para trocar o nome: git branch -M \(nm)")
                return false
            }
            say("* \(s.branch)")
            return true

        case "reset":
            if paths.isEmpty {
                s.staged = []
            } else {
                for p in paths {
                    if let u = resolve(p) {
                        let rel = Repo.relPath(u, root)
                        s.staged.removeAll { $0 == rel || $0.hasPrefix(rel + "/") }
                    }
                }
            }
            Repo.save(s, root)
            say("Preparação desfeita.")
            return true

        case "rm":
            if paths.isEmpty {
                say("uso: git rm arquivo")
                return false
            }
            for p in paths {
                guard let u = resolve(p) else { continue }
                let rel = Repo.relPath(u, root)
                try? fm.removeItem(at: u)
                if !s.staged.contains(rel) { s.staged.append(rel) }
                say("rm '\(rel)'")
            }
            Repo.save(s, root)
            return true

        default:
            if Catalog.unsupportedGit.contains(sub) {
                say("git \(sub) ainda não é suportado no CodeLab.")
            } else {
                gitUnknown(sub)
            }
            return false
        }
    }

    func runRemote() async -> Bool {
        guard let g = gh, g.user != nil else {
            say("Entre no GitHub primeiro (botão no topo do menu).")
            return false
        }
        guard let root = Repo.root(from: cwd) else {
            say("Esta pasta não é um repositório. Use git init.")
            return false
        }
        let s = Repo.load(root)
        if s.remote.isEmpty {
            say("Nenhum remoto. Use: git remote add origin usuario/repositorio")
            return false
        }
        if !s.commits.isEmpty {
            say("Aviso: você tem \(s.commits.count) commit(s) não enviado(s). O GitHub vai rodar a versão antiga (use git push antes).")
        }
        do {
            let r = try await g.runWorkflow(slug: s.remote, branch: s.branch, say: { self.say($0) })
            say(GitHub.describe(r))
            return r.conclusion == "success"
        } catch {
            say("erro: " + error.localizedDescription)
            return false
        }
    }
}

// MARK: - Telas

struct TerminalView: View {
    var start: URL? = nil
    @EnvironmentObject var gh: GitHub
    @StateObject private var m = TerminalModel()
    @State private var input = ""
    @State private var showHelp = false
    @State private var histIdx = -1
    @FocusState private var focused: Bool

    init(start: URL? = nil) {
        self.start = start
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(m.out)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: m.out) { _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            Divider()
            hintBar
            suggestionBar
            inputRow
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
            }
        }
        .sheet(isPresented: $showHelp) {
            CheatSheet { text in
                input = text
                focused = true
            }
        }
        .onAppear {
            m.gh = gh
            if !m.started {
                m.started = true
                if let s = start { m.cwd = s }
            }
            m.refresh()
        }
    }

    var hintBar: some View {
        Group {
            if let h = m.hint(for: input) {
                HStack {
                    Text("⚠️ " + h.text).font(.caption).foregroundColor(.orange)
                    Spacer()
                    if let f = h.fix {
                        Button("Corrigir") { input = f }.font(.caption.bold())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            } else if input.isEmpty, let n = m.next {
                HStack {
                    Text("💡 " + n.desc).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
    }

    var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(m.suggestions(for: input), id: \.cmd) { c in
                    Button {
                        input = c.insert
                        focused = true
                    } label: {
                        Text(c.cmd)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
    }

    var inputRow: some View {
        HStack(spacing: 8) {
            Text(m.prompt)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 170, alignment: .leading)
            TextField("comando", text: $input)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }
            if m.busy { ProgressView() }
            Button { recall() } label: { Image(systemName: "arrow.up") }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    func send() {
        let l = input
        input = ""
        histIdx = -1
        m.submit(l)
        focused = true
    }

    func recall() {
        if m.history.isEmpty { return }
        histIdx = histIdx < 0 ? m.history.count - 1 : max(0, histIdx - 1)
        input = m.history[histIdx]
    }
}

struct CheatSheet: View {
    let onPick: (String) -> Void
    @Environment(\.presentationMode) var pm

    func row(_ c: CmdInfo) -> some View {
        Button {
            onPick(c.insert)
            pm.wrappedValue.dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.cmd).font(.system(.subheadline, design: .monospaced)).foregroundColor(.primary)
                Text(c.desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Fluxo básico")) {
                    Text("1. cd pasta-do-projeto\n2. git init\n3. git remote add origin usuario/repo\n4. git add .\n5. git commit -m \"mensagem\"\n6. git push\n7. run  (compila/executa no GitHub)")
                        .font(.system(.footnote, design: .monospaced))
                }
                Section(header: Text("GitHub (git)")) {
                    ForEach(Catalog.git, id: \.cmd) { c in row(c) }
                }
                Section(header: Text("Executar")) {
                    ForEach(Catalog.run, id: \.cmd) { c in row(c) }
                }
                Section(header: Text("Arquivos")) {
                    ForEach(Catalog.files, id: \.cmd) { c in row(c) }
                }
            }
            .navigationTitle("Comandos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { pm.wrappedValue.dismiss() }
                }
            }
        }
    }
}
