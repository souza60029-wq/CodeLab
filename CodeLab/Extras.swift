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
    let onOpen: (URL) -> Void
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
                        onOpen(dir.appendingPathComponent(h.file))
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
