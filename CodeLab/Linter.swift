import Foundation

struct Issue: Identifiable {
    let id = UUID()
    let line: Int
    let msg: String
    var append: String? = nil
}

enum Linter {
    static func check(_ text: String, ext: String) -> [Issue] {
        var out: [Issue] = []
        let hash = (ext == "gd")
        let chars = Array(text)
        var stack: [(Character, Int)] = []
        var line = 1
        var inStr: Character? = nil
        var inBlock = false
        var inLine = false
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let n: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "\n" { line += 1; inLine = false; inStr = nil; i += 1; continue }
            if inLine { i += 1; continue }
            if inBlock {
                if c == "*" && n == "/" { inBlock = false; i += 2 } else { i += 1 }
                continue
            }
            if let q = inStr {
                if c == "\\" { i += 2; continue }
                if c == q { inStr = nil }
                i += 1; continue
            }
            if c == "\"" || c == "'" { inStr = c; i += 1; continue }
            if hash && c == "#" { inLine = true; i += 1; continue }
            if !hash && c == "/" && n == "/" { inLine = true; i += 2; continue }
            if !hash && c == "/" && n == "*" { inBlock = true; i += 2; continue }
            if "([{".contains(c) { stack.append((c, line)) }
            else if let open = pairs[c] {
                if let last = stack.last, last.0 == open { stack.removeLast() }
                else { out.append(Issue(line: line, msg: "'\(c)' sem par")) }
            }
            i += 1
        }
        for s in stack { out.append(Issue(line: s.1, msg: "'\(s.0)' não foi fechado")) }

        let lines = text.components(separatedBy: "\n")
        func code(_ s: String) -> String {
            let sep = hash ? "#" : "//"
            return s.components(separatedBy: sep)[0].trimmingCharacters(in: .whitespaces)
        }
        func nextNonEmpty(_ from: Int) -> String {
            var j = from + 1
            while j < lines.count {
                let t = code(lines[j])
                if !t.isEmpty { return t }
                j += 1
            }
            return ""
        }
        let semi = ["c", "cpp", "h", "hpp", "java"].contains(ext)
        let controls = ["if", "for", "while", "else", "switch", "do", "try", "catch", "class", "struct", "namespace", "enum", "interface", "template", "public", "private", "protected"]
        for (idx, raw) in lines.enumerated() {
            let t = code(raw)
            if t.isEmpty || t.hasPrefix("*") || t.hasPrefix("/*") || t.hasPrefix("#") && !hash || t.hasPrefix("@") { continue }
            if semi {
                guard let last = t.last else { continue }
                if ";{},(:&|+-*/=<>\\".contains(last) { continue }
                let first = t.split(separator: " ").first.map(String.init) ?? ""
                let firstWord = first.components(separatedBy: "(")[0]
                if controls.contains(firstWord) { continue }
                if nextNonEmpty(idx).hasPrefix("{") || nextNonEmpty(idx).hasPrefix(".") { continue }
                out.append(Issue(line: idx + 1, msg: "falta ';' no fim da linha?", append: ";"))
            }
            if hash {
                let starts = ["func ", "if ", "elif ", "else", "for ", "while ", "class ", "match ", "static func "]
                if starts.contains(where: { t.hasPrefix($0) }) && !t.hasSuffix(":") {
                    out.append(Issue(line: idx + 1, msg: "falta ':' no fim da linha", append: ":"))
                }
            }
        }
        return out.sorted { $0.line < $1.line }
    }

    static func fix(_ text: String, _ issues: [Issue], ext: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let sep = ext == "gd" ? "#" : "//"
        for i in issues {
            guard let a = i.append, i.line - 1 < lines.count else { continue }
            let n = i.line - 1
            if let r = lines[n].range(of: sep) {
                var head = String(lines[n][lines[n].startIndex..<r.lowerBound])
                while head.last == " " { head.removeLast() }
                lines[n] = head + a + " " + String(lines[n][r.lowerBound...])
            } else {
                lines[n] += a
            }
        }
        return lines.joined(separator: "\n")
    }
}
