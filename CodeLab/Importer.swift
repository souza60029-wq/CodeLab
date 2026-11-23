import Foundation
import Compression

enum Zip {
    /// Extrai um .zip (métodos "armazenado" e "deflate") para a pasta destino.
    /// Se todos os arquivos estiverem dentro de uma única pasta (como nos zips do GitHub), essa pasta é removida do caminho.
    @discardableResult
    static func extract(_ zipURL: URL, to dest: URL) throws -> Int {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let b = data   // sem copiar o arquivo inteiro para um array (economiza RAM)
        func u16(_ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }

        guard b.count >= 22 else { throw GHError(msg: "Arquivo .zip inválido.") }
        var eocd = -1
        var i = b.count - 22
        let lim = max(0, b.count - 22 - 65535)
        while i >= lim {
            if b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 5 && b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw GHError(msg: "Não é um .zip válido.") }
        let count = u16(eocd + 10)
        var off = u32(eocd + 16)
        if count == 0xFFFF || off == 0xFFFFFFFF { throw GHError(msg: "Zip64 (arquivo muito grande) não é suportado.") }

        struct Entry {
            var name: String
            var method: Int
            var csize: Int
            var usize: Int
            var lho: Int
        }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard off + 46 <= b.count, u32(off) == 0x02014b50 else { throw GHError(msg: "Zip corrompido.") }
            let method = u16(off + 10)
            let csize = u32(off + 20)
            let usize = u32(off + 24)
            let nl = u16(off + 28)
            let el = u16(off + 30)
            let cl = u16(off + 32)
            let lho = u32(off + 42)
            guard off + 46 + nl <= b.count else { throw GHError(msg: "Zip corrompido.") }
            let name = String(decoding: b[(off + 46)..<(off + 46 + nl)], as: UTF8.self)
            entries.append(Entry(name: name, method: method, csize: csize, usize: usize, lho: lho))
            off += 46 + nl + el + cl
        }

        // ignora lixo de macOS e a pasta .git
        let valid = entries.filter { e in
            !(e.name.hasPrefix("__MACOSX/") || e.name.hasSuffix(".DS_Store") || e.name.hasPrefix(".git/") || e.name.contains("/.git/"))
        }
        // pasta única na raiz?
        var strip = ""
        let firsts = Set(valid.map { $0.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? "" })
        if firsts.count == 1, let f = firsts.first, !f.isEmpty {
            let allInside = valid.allSatisfy { $0.name.hasPrefix(f + "/") }
            if allInside { strip = f + "/" }
        }

        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var written = 0
        for e in valid {
            var rel = e.name
            if !strip.isEmpty { rel = String(rel.dropFirst(strip.count)) }
            if rel.isEmpty { continue }
            let comps = rel.split(separator: "/").map(String.init)
            if rel.hasPrefix("/") || comps.contains("..") { continue }   // segurança
            let target = dest.appendingPathComponent(rel)
            if e.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            let lo = e.lho
            guard lo + 30 <= b.count, u32(lo) == 0x04034b50 else { throw GHError(msg: "Zip corrompido (\(e.name)).") }
            let nl2 = u16(lo + 26)
            let el2 = u16(lo + 28)
            let start = lo + 30 + nl2 + el2
            guard start + e.csize <= b.count else { throw GHError(msg: "Zip corrompido (\(e.name)).") }
            var out = Data()
            if e.method == 0 {
                out = Data(b[start..<(start + e.csize)])
            } else if e.method == 8 {
                if e.usize > 0 {
                    var dst = [UInt8](repeating: 0, count: e.usize)
                    let src = Array(b[start..<(start + e.csize)])
                    let n = compression_decode_buffer(&dst, e.usize, src, e.csize, nil, COMPRESSION_ZLIB)
                    guard n == e.usize else { throw GHError(msg: "Não consegui descompactar \(e.name).") }
                    out = Data(dst)
                }
            } else {
                throw GHError(msg: "Método de compressão não suportado em \(e.name).")
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: target)
            written += 1
        }
        return written
    }
}

enum Importer {
    static let fm = FileManager.default

    static func detect(_ dir: URL) -> Lang? {
        let names = Store.files(in: dir).map { $0.lowercased() }
        func has(_ suffix: String) -> Bool { names.contains { $0.hasSuffix(suffix) } }
        if has("project.godot") { return .godot }
        if has("androidmanifest.xml") { return .android }
        if has("project.yml") || has("project.pbxproj") || has(".swift") { return .ios }
        if has(".kt") || has(".kts") { return .android }
        if has(".java") { return .java }
        if has(".cpp") || has(".cc") || has(".cxx") || has(".c") || has(".h") || has(".hpp") { return .cpp }
        return nil
    }

    static func copyDir(_ src: URL, _ dst: URL) throws {
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for n in try fm.contentsOfDirectory(atPath: src.path) {
            if n == ".git" || n == ".DS_Store" { continue }
            let s = src.appendingPathComponent(n)
            let d = dst.appendingPathComponent(n)
            var isD: ObjCBool = false
            fm.fileExists(atPath: s.path, isDirectory: &isD)
            if isD.boolValue {
                try copyDir(s, d)
            } else {
                try fm.copyItem(at: s, to: d)
            }
        }
    }

    /// Importa um .zip ou uma pasta escolhida no app Arquivos. Retorna a linguagem e o nome do projeto criado.
    static func importItem(_ url: URL, lang: Lang?) throws -> (Lang, String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let tmp = fm.temporaryDirectory.appendingPathComponent("import-" + UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        var base = Store.cleanName(url.lastPathComponent)
        if isDir.boolValue {
            try copyDir(url, tmp)
        } else if url.pathExtension.lowercased() == "zip" {
            base = Store.cleanName(url.deletingPathExtension().lastPathComponent)
            try Zip.extract(url, to: tmp)
        } else {
            throw GHError(msg: "Escolha um arquivo .zip ou uma pasta.")
        }
        if base.isEmpty { base = "projeto" }

        guard let l = lang ?? detect(tmp) else {
            throw GHError(msg: "Não consegui identificar a linguagem do projeto. Abra a linguagem desejada no menu e importe de lá.")
        }

        let parent = Store.root.appendingPathComponent(l.rawValue)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var name = base
        var n = 2
        while fm.fileExists(atPath: parent.appendingPathComponent(name).path) {
            name = base + "-" + String(n)
            n += 1
        }
        try fm.moveItem(at: tmp, to: parent.appendingPathComponent(name))
        return (l, name)
    }
}
