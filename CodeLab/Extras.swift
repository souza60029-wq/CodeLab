import SwiftUI
import UIKit

// MARK: - Compartilhar (abrir no TrollStore, Arquivos, AirDrop…)

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Exportar projeto em .zip

enum ZipWriter {
    static let table: [UInt32] = (0..<256).map { (i: Int) -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func put<T: FixedWidthInteger>(_ data: inout Data, _ v: T) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    /// Cria um .zip (sem compressão) com todos os arquivos da pasta, dentro de uma pasta `prefix`.
    static func create(dir: URL, to dest: URL, prefix: String) throws {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0
        for rel in Store.files(in: dir) {
            let data = try Data(contentsOf: dir.appendingPathComponent(rel))
            let name = Data((prefix + "/" + rel).utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            let size = UInt32(data.count)

            put(&out, UInt32(0x04034b50))
            put(&out, UInt16(20))
            put(&out, UInt16(0x0800))
            put(&out, UInt16(0))
            put(&out, UInt16(0))
            put(&out, UInt16(0x21))
            put(&out, crc)
            put(&out, size)
            put(&out, size)
            put(&out, UInt16(name.count))
            put(&out, UInt16(0))
            out.append(name)
            out.append(data)

            put(&central, UInt32(0x02014b50))
            put(&central, UInt16(20))
            put(&central, UInt16(20))
            put(&central, UInt16(0x0800))
            put(&central, UInt16(0))
            put(&central, UInt16(0))
            put(&central, UInt16(0x21))
            put(&central, crc)
            put(&central, size)
            put(&central, size)
            put(&central, UInt16(name.count))
            put(&central, UInt16(0))
            put(&central, UInt16(0))
            put(&central, UInt16(0))
            put(&central, UInt16(0))
            put(&central, UInt32(0))
            put(&central, offset)
            central.append(name)
            count += 1
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        put(&out, UInt32(0x06054b50))
        put(&out, UInt16(0))
        put(&out, UInt16(0))
        put(&out, count)
        put(&out, count)
        put(&out, UInt32(central.count))
        put(&out, cdOffset)
        put(&out, UInt16(0))
        try out.write(to: dest)
    }
}

// MARK: - Buscar no projeto

struct SearchHit: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let text: String
}

struct ProjectSearchView: View {
    let dir: URL
    let onOpen: (URL, Int) -> Void
    @Environment(\.presentationMode) var pm
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searched = false

    func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { hits = []; searched = false; return }
        var out: [SearchHit] = []
        for rel in Store.files(in: dir) {
            if rel.hasPrefix(".git/") || rel.hasPrefix(".codelab/") { continue }
            guard let text = try? String(contentsOf: dir.appendingPathComponent(rel)) else { continue }
            var n = 0
            for line in text.components(separatedBy: "\n") {
                n += 1
                if line.range(of: q, options: .caseInsensitive) != nil {
                    out.append(SearchHit(file: rel, line: n, text: line.trimmingCharacters(in: .whitespaces)))
                    if out.count >= 300 { break }
                }
            }
            if out.count >= 300 { break }
        }
        hits = out
        searched = true
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Buscar em todos os arquivos", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { run() }
                }
                if searched && hits.isEmpty {
                    Text("Nenhum resultado.").foregroundColor(.secondary)
                }
                ForEach(hits) { h in
                    Button {
                        onOpen(dir.appendingPathComponent(h.file), h.line)
                        pm.wrappedValue.dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.file + ":" + String(h.line))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(h.text)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
        }
    }
}

// MARK: - Verificar projeto (local, antes de gastar build no GitHub)

struct CheckItem: Identifiable {
    let id = UUID()
    let level: Int   // 0 ok, 1 aviso, 2 erro
    let text: String
    var line: String { (level == 0 ? "✓ " : (level == 1 ? "⚠️ " : "✗ ")) + text }
}

enum ProjectCheck {
    static func run(_ lang: Lang, _ dir: URL) -> [CheckItem] {
        var r: [CheckItem] = []
        let fm = FileManager.default
        func has(_ p: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(p).path) }
        func read(_ p: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(p)) }
        func ok(_ t: String) { r.append(CheckItem(level: 0, text: t)) }
        func warn(_ t: String) { r.append(CheckItem(level: 1, text: t)) }
        func bad(_ t: String) { r.append(CheckItem(level: 2, text: t)) }

        let all = Store.files(in: dir)
        let hasWorkflow = (read(".github/workflows/build.yml") ?? "").contains("workflow_dispatch")

        switch lang {
        case .android:
            for f in ["settings.gradle", "build.gradle", "app/build.gradle", "app/src/main/AndroidManifest.xml"] {
                if has(f) { ok(f + " encontrado") } else if has(f + ".kts") { ok(f + ".kts encontrado") } else { bad(f + " não existe") }
            }
            if let m = read("app/src/main/AndroidManifest.xml"), let d = m.data(using: .utf8) {
                let p = XMLParser(data: d)
                if p.parse() { ok("AndroidManifest.xml é um XML válido") }
                else { bad("AndroidManifest.xml com erro: " + (p.parserError?.localizedDescription ?? "XML inválido")) }
            }
            if let g = read("settings.gradle"), !g.contains(":app") { bad("settings.gradle não inclui o módulo ':app'") }
            if let g = read("app/build.gradle"), !g.contains("namespace") { warn("app/build.gradle sem 'namespace'") }
            if !all.contains(where: { $0.hasSuffix("MainActivity.java") || $0.hasSuffix("MainActivity.kt") }) { warn("nenhuma MainActivity encontrada") }
        case .ios:
            if has("project.yml") { ok("project.yml encontrado") } else { bad("project.yml não existe (o build usa XcodeGen)") }
            let swift = all.filter { $0.hasSuffix(".swift") }
            if swift.isEmpty { bad("nenhum arquivo .swift") }
            else if !swift.contains(where: { (read($0) ?? "").contains("@main") }) { warn("nenhum arquivo tem @main") }
            else { ok("ponto de entrada @main encontrado") }
        case .godot:
            if let g = read("project.godot") {
                ok("project.godot encontrado")
                if !g.contains("config_version") { warn("project.godot sem config_version") }
            } else { bad("project.godot não existe") }
            if !all.contains(where: { $0.hasSuffix(".gd") }) { warn("nenhum script .gd") }
        case .cpp:
            let src = all.filter { ["c", "cpp", "cc", "cxx"].contains(($0 as NSString).pathExtension.lowercased()) }
            if src.isEmpty { bad("nenhum arquivo .c/.cpp") }
            else if !src.contains(where: { (read($0) ?? "").contains("main") }) { warn("não achei a função main") }
            else { ok("função main encontrada") }
        case .java:
            let src = all.filter { $0.hasSuffix(".java") }
            if src.isEmpty { bad("nenhum arquivo .java") }
            else if !src.contains(where: { (read($0) ?? "").contains("static void main") }) { warn("não achei public static void main") }
            else { ok("método main encontrado") }
        }

        if lang == .android || lang == .ios || lang == .godot {
            if hasWorkflow { ok("workflow de build encontrado (workflow_dispatch)") }
            else { warn(".github/workflows/build.yml ausente ou sem 'workflow_dispatch'") }
        }

        let exts: Set<String> = ["java", "kt", "swift", "gd", "c", "cpp", "cc", "h", "hpp"]
        var problems = 0
        var files = 0
        for f in all where exts.contains((f as NSString).pathExtension.lowercased()) {
            guard let text = read(f) else { continue }
            files += 1
            for i in Linter.check(text, ext: (f as NSString).pathExtension.lowercased()).prefix(3) {
                problems += 1
                if problems <= 8 { warn(f + ":" + String(i.line) + " " + i.msg) }
            }
        }
        if files > 0 && problems == 0 { ok(String(files) + " arquivo(s) de código sem problemas óbvios") }
        if problems > 8 { warn("… e mais " + String(problems - 8) + " aviso(s)") }
        return r
    }

    static func report(_ lang: Lang, _ dir: URL) -> String {
        let items = run(lang, dir)
        let bad = items.filter { $0.level == 2 }.count
        let warn = items.filter { $0.level == 1 }.count
        var s = items.map { $0.line }.joined(separator: "\n")
        s += "\n\n" + (bad > 0 ? "✗ " + String(bad) + " erro(s) — corrija antes de enviar para o GitHub."
                              : (warn > 0 ? "⚠️ " + String(warn) + " aviso(s), mas nada impede o envio."
                                          : "✓ Tudo certo para enviar."))
        return s
    }
}
