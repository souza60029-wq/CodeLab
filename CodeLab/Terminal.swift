import SwiftUI

final class TerminalModel: ObservableObject {
    @Published var out = "CodeLab terminal (local). Digite help.\n"
    var cwd = Store.root
    let fm = FileManager.default

    var prompt: String {
        let rel = String(cwd.path.dropFirst(Store.root.path.count))
        return "~" + rel + " $"
    }

    func resolve(_ p: String) -> URL? {
        let u = (p.hasPrefix("/") ? Store.root.appendingPathComponent(p) : cwd.appendingPathComponent(p)).standardizedFileURL
        return u.path.hasPrefix(Store.root.standardizedFileURL.path) ? u : nil
    }

    func run(_ line: String) {
        out += "\(prompt) \(line)\n"
        let parts = line.split(separator: " ").map(String.init)
        guard let cmd = parts.first else { return }
        let args = Array(parts.dropFirst())
        switch cmd {
        case "help":
            out += "help pwd ls cd cat mkdir touch rm mv cp echo wc clear\n"
        case "pwd":
            out += prompt.dropLast(2) + "\n"
        case "clear":
            out = ""
        case "ls":
            let u = args.first.flatMap(resolve) ?? cwd
            let items = ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []).sorted()
            out += items.joined(separator: "  ") + "\n"
        case "cd":
            if let a = args.first, let u = resolve(a), fm.fileExists(atPath: u.path) { cwd = u }
            else if args.isEmpty { cwd = Store.root }
            else { out += "cd: diretório não encontrado\n" }
        case "cat":
            for a in args {
                if let u = resolve(a), let s = try? String(contentsOf: u) { out += s + (s.hasSuffix("\n") ? "" : "\n") }
                else { out += "cat: \(a): não encontrado\n" }
            }
        case "mkdir":
            for a in args { if let u = resolve(a) { try? fm.createDirectory(at: u, withIntermediateDirectories: true) } }
        case "touch":
            for a in args { if let u = resolve(a), !fm.fileExists(atPath: u.path) { try? "".write(to: u, atomically: true, encoding: .utf8) } }
        case "rm":
            for a in args where !a.hasPrefix("-") { if let u = resolve(a) { try? fm.removeItem(at: u) } }
        case "mv", "cp":
            if args.count >= 2, let a = resolve(args[0]), let b = resolve(args[1]) {
                do { if cmd == "mv" { try fm.moveItem(at: a, to: b) } else { try fm.copyItem(at: a, to: b) } }
                catch { out += "\(cmd): \(error.localizedDescription)\n" }
            } else { out += "uso: \(cmd) origem destino\n" }
        case "echo":
            out += args.joined(separator: " ") + "\n"
        case "wc":
            for a in args {
                if let u = resolve(a), let s = try? String(contentsOf: u) {
                    out += "\(s.components(separatedBy: "\n").count - 1) linhas  \(s.count) caracteres  \(a)\n"
                }
            }
        default:
            out += "\(cmd): comando não encontrado (o iOS não deixa rodar programas externos)\n"
        }
    }
}

struct TerminalView: View {
    @StateObject private var m = TerminalModel()
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(m.out)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            Divider()
            HStack {
                Text(m.prompt).font(.system(.footnote, design: .monospaced))
                TextField("comando", text: $input, onCommit: {
                    m.run(input); input = ""
                })
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(.footnote, design: .monospaced))
            }
            .padding(8)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
