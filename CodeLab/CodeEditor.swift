import SwiftUI
import UIKit

/// Editor de código com cores, barra de símbolos acima do teclado e auto-indentação.
struct JumpRequest: Equatable {
    let id = UUID()
    let line: Int
}

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let ext: String
    var onCursor: ((Int, Int) -> Void)? = nil
    var jump: JumpRequest? = nil
    var onJumped: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: Prefs.editorFontSize, weight: .regular)
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        context.coordinator.textView = tv
        tv.inputAccessoryView = context.coordinator.makeBar()
        tv.text = text
        context.coordinator.highlight(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            tv.text = text
            context.coordinator.highlight(tv)
        }
        if let j = jump, j.id != context.coordinator.lastJump {
            context.coordinator.lastJump = j.id
            context.coordinator.goTo(j.line)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var textView: UITextView?

        var lastJump: UUID? = nil

        init(_ p: CodeEditor) { parent = p }

        static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]

        var unit: String { parent.ext == "gd" ? "\t" : String(repeating: " ", count: Prefs.tabWidth) }

        // MARK: delegate

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            highlight(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard let cb = parent.onCursor else { return }
            let ns = tv.text as NSString
            let loc = min(tv.selectedRange.location, ns.length)
            let before = ns.substring(to: loc).components(separatedBy: "\n")
            let line = before.count
            let col = (before.last ?? "").count + 1
            DispatchQueue.main.async { cb(line, col) }
        }

        /// Troca um trecho de forma que o desfazer (undo) continue funcionando.
        func replace(_ tv: UITextView, _ r: NSRange, with s: String, select: NSRange? = nil) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: r.location),
                  let end = tv.position(from: start, offset: r.length),
                  let tr = tv.textRange(from: start, to: end) else { return }
            tv.replace(tr, withText: s)
            if let sel = select { tv.selectedRange = sel }
            textViewDidChange(tv)
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            let ns = tv.text as NSString
            let len = ns.length
            func ch(_ i: Int) -> String? { (i >= 0 && i < len) ? ns.substring(with: NSRange(location: i, length: 1)) : nil }

            // apagar um par vazio: ( | ) → remove os dois
            if t.isEmpty && range.length == 1 && Prefs.autoPairs {
                if let a = ch(range.location), let b = ch(range.location + 1), Coordinator.pairs[a] == b {
                    replace(tv, NSRange(location: range.location, length: 2), with: "", select: NSRange(location: range.location, length: 0))
                    return false
                }
            }

            // Enter: mantém a indentação, aumenta depois de { e abre o bloco entre { }
            if t == "\n" && Prefs.autoIndent {
                let lr = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let beforeLen = range.location - lr.location
                let before = beforeLen > 0 ? ns.substring(with: NSRange(location: lr.location, length: beforeLen)) : ""
                var indent = ""
                for c in before {
                    if c == " " || c == "\t" { indent.append(c) } else { break }
                }
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                let colonBlock = parent.ext == "gd" && trimmed.hasSuffix(":")
                let extra = (trimmed.hasSuffix("{") || colonBlock) ? unit : ""
                if trimmed.hasSuffix("{"), ch(range.location + range.length) == "}" {
                    let mid = "\n" + indent + unit
                    tv.insertText(mid + "\n" + indent)
                    tv.selectedRange = NSRange(location: range.location + (mid as NSString).length, length: 0)
                    return false
                }
                if !indent.isEmpty || !extra.isEmpty {
                    tv.insertText("\n" + indent + extra)
                    return false
                }
            }

            guard t.count == 1 else { return true }
            let next = ch(range.location + range.length)
            let prev = ch(range.location - 1)

            // digitar um fechamento que já existe logo à frente → só pula
            if Prefs.autoPairs, range.length == 0, [")", "]", "}", "\"", "'"].contains(t), next == t {
                tv.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }

            // } sozinho numa linha em branco → recua um nível
            if t == "}" && Prefs.autoIndent && range.length == 0 {
                let lr = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let beforeLen = range.location - lr.location
                if beforeLen > 0 {
                    let before = ns.substring(with: NSRange(location: lr.location, length: beforeLen))
                    if before.trimmingCharacters(in: .whitespaces).isEmpty {
                        let remove = min(unit.count, beforeLen)
                        replace(tv, NSRange(location: range.location - remove, length: remove), with: "}",
                                select: NSRange(location: range.location - remove + 1, length: 0))
                        return false
                    }
                }
            }

            // fechar automaticamente ( [ { " '
            if Prefs.autoPairs, let close = Coordinator.pairs[t] {
                if range.length > 0 {
                    tv.insertText(t + ns.substring(with: range) + close)
                    return false
                }
                let isQuote = (t == "\"" || t == "'")
                var nextOK = (next == nil)
                if let n = next { nextOK = [" ", "\n", "\t", ")", "]", "}", ",", ";"].contains(n) }
                let prevWord = prev.map { $0.rangeOfCharacter(from: .alphanumerics) != nil } ?? false
                if nextOK && !(isQuote && prevWord) {
                    tv.insertText(t + close)
                    tv.selectedRange = NSRange(location: range.location + 1, length: 0)
                    return false
                }
            }
            return true
        }

        // MARK: ações do teclado

        func insertSymbol(_ s: String) {
            guard let tv = textView else { return }
            tv.insertText(s)
        }

        func moveCursor(_ d: Int) {
            guard let tv = textView else { return }
            let len = (tv.text as NSString).length
            let loc = max(0, min(len, tv.selectedRange.location + d))
            tv.selectedRange = NSRange(location: loc, length: 0)
        }

        func goTo(_ line: Int) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            var loc = 0
            var n = 1
            while n < line && loc < ns.length {
                loc = ns.lineRange(for: NSRange(location: loc, length: 0)).upperBound
                n += 1
            }
            let lr = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
            var l = lr.length
            if l > 0 && ns.substring(with: NSRange(location: lr.upperBound - 1, length: 1)) == "\n" { l -= 1 }
            let target = NSRange(location: lr.location, length: l)
            DispatchQueue.main.async { [weak self] in
                tv.selectedRange = target
                tv.scrollRangeToVisible(target)
                self?.parent.onJumped?()
            }
        }

        var commentPrefix: String? {
            switch parent.ext {
            case "gd", "yml", "yaml", "sh", "py", "properties", "cfg", "godot": return "# "
            case "xml", "html", "md", "txt", "json", "": return nil
            default: return "// "
            }
        }

        /// Linhas que a seleção toca (sem a quebra de linha do final).
        func selectedBlock(_ tv: UITextView) -> (range: NSRange, lines: [String], hadNewline: Bool) {
            let ns = tv.text as NSString
            let lr = ns.lineRange(for: tv.selectedRange)
            var block = ns.substring(with: lr)
            let had = block.hasSuffix("\n")
            if had { block.removeLast() }
            return (lr, block.components(separatedBy: "\n"), had)
        }

        func applyBlock(_ tv: UITextView, _ lr: NSRange, _ lines: [String], _ had: Bool) {
            let new = lines.joined(separator: "\n") + (had ? "\n" : "")
            let selLen = (new as NSString).length - (had ? 1 : 0)
            replace(tv, lr, with: new, select: NSRange(location: lr.location, length: max(0, selLen)))
        }

        func toggleComment() {
            guard let tv = textView, let prefix = commentPrefix else { return }
            let (lr, lines0, had) = selectedBlock(tv)
            var lines = lines0
            let bare = prefix.trimmingCharacters(in: .whitespaces)
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(bare) }
            if allCommented {
                lines = lines.map { (l: String) -> String in
                    var out = l
                    guard l.trimmingCharacters(in: .whitespaces).hasPrefix(bare), let r = out.range(of: bare) else { return l }
                    let off = out.distance(from: out.startIndex, to: r.lowerBound)
                    out.removeSubrange(r)
                    let idx = out.index(out.startIndex, offsetBy: off)
                    if idx < out.endIndex && out[idx] == " " { out.remove(at: idx) }
                    return out
                }
            } else {
                let minIndent = nonEmpty.map { (l: String) -> Int in l.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
                lines = lines.map { (l: String) -> String in
                    if l.trimmingCharacters(in: .whitespaces).isEmpty { return l }
                    var o = l
                    o.insert(contentsOf: prefix, at: o.index(o.startIndex, offsetBy: min(minIndent, o.count)))
                    return o
                }
            }
            applyBlock(tv, lr, lines, had)
        }

        func indent(out: Bool) {
            guard let tv = textView else { return }
            if !out && tv.selectedRange.length == 0 { tv.insertText(unit); return }
            let (lr, lines0, had) = selectedBlock(tv)
            let u = unit
            let lines = lines0.map { (l: String) -> String in
                if out {
                    if l.hasPrefix("\t") { return String(l.dropFirst()) }
                    var n = 0
                    for c in l { if c == " " && n < u.count { n += 1 } else { break } }
                    return String(l.dropFirst(n))
                }
                return l.trimmingCharacters(in: .whitespaces).isEmpty ? l : u + l
            }
            applyBlock(tv, lr, lines, had)
        }

        func duplicateLine() {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let lr = ns.lineRange(for: tv.selectedRange)
            var blk = ns.substring(with: lr)
            if !blk.hasSuffix("\n") { blk = "\n" + blk }
            let at = NSRange(location: lr.upperBound, length: 0)
            let blkLen = (blk as NSString).length
            replace(tv, at, with: blk, select: NSRange(location: lr.upperBound + (blk.hasPrefix("\n") ? 1 : 0), length: max(0, blkLen - 1)))
        }

        func deleteLine() {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let lr = ns.lineRange(for: tv.selectedRange)
            replace(tv, lr, with: "", select: NSRange(location: min(lr.location, ns.length - lr.length), length: 0))
        }

        func moveLine(up: Bool) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let lr = ns.lineRange(for: tv.selectedRange)
            if up {
                if lr.location == 0 { return }
                let prev = ns.lineRange(for: NSRange(location: lr.location - 1, length: 0))
                var blk = ns.substring(with: lr)
                var prv = ns.substring(with: prev)
                if !blk.hasSuffix("\n") {
                    blk += "\n"
                    if prv.hasSuffix("\n") { prv.removeLast() }
                }
                let whole = NSRange(location: prev.location, length: prev.length + lr.length)
                let selLen = (blk as NSString).length - 1
                replace(tv, whole, with: blk + prv, select: NSRange(location: prev.location, length: max(0, selLen)))
            } else {
                if lr.upperBound >= ns.length { return }
                let next = ns.lineRange(for: NSRange(location: lr.upperBound, length: 0))
                var blk = ns.substring(with: lr)
                var nxt = ns.substring(with: next)
                if !nxt.hasSuffix("\n") {
                    nxt += "\n"
                    if blk.hasSuffix("\n") { blk.removeLast() }
                }
                let whole = NSRange(location: lr.location, length: lr.length + next.length)
                let selLen = (blk as NSString).length - (blk.hasSuffix("\n") ? 1 : 0)
                replace(tv, whole, with: nxt + blk, select: NSRange(location: lr.location + (nxt as NSString).length, length: max(0, selLen)))
            }
        }

        // MARK: barra acima do teclado

        func makeBar() -> UIView {
            let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            scroll.autoresizingMask = .flexibleWidth
            scroll.backgroundColor = UIColor.secondarySystemBackground
            scroll.showsHorizontalScrollIndicator = false

            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 6
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 6),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -6),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
            ])

            func add(_ symbol: String?, _ title: String, _ action: @escaping () -> Void) {
                stack.addArrangedSubview(makeButton(symbol: symbol, title: title, action))
            }
            add("keyboard.chevron.compact.down", "⌄") { [weak self] in self?.textView?.resignFirstResponder() }
            add("arrow.uturn.backward", "↶") { [weak self] in self?.textView?.undoManager?.undo() }
            add("arrow.uturn.forward", "↷") { [weak self] in self?.textView?.undoManager?.redo() }
            add("arrow.left", "←") { [weak self] in self?.moveCursor(-1) }
            add("arrow.right", "→") { [weak self] in self?.moveCursor(1) }
            add("arrow.right.to.line", "Tab") { [weak self] in self?.indent(out: false) }
            add("arrow.left.to.line", "⇤") { [weak self] in self?.indent(out: true) }
            if let p = commentPrefix {
                add(nil, p.trimmingCharacters(in: .whitespaces)) { [weak self] in self?.toggleComment() }
            }
            add("plus.square.on.square", "⧉") { [weak self] in self?.duplicateLine() }
            add("trash", "⌫") { [weak self] in self?.deleteLine() }
            add("arrow.up.square", "⇡") { [weak self] in self?.moveLine(up: true) }
            add("arrow.down.square", "⇣") { [weak self] in self?.moveLine(up: false) }

            let symbols = ["{", "}", "(", ")", "[", "]", ";", ":", "\"", "'", "<", ">", "=", "+", "-", "*", "/", "\\", "#", "&", "|", "!", "_", ".", ",", "$", "%", "?"]
            for sym in symbols {
                add(nil, sym) { [weak self] in self?.insertSymbol(sym) }
            }
            return scroll
        }

        func makeButton(symbol: String?, title: String, _ action: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system)
            if let s = symbol, let img = UIImage(systemName: s) {
                b.setImage(img, for: .normal)
            } else {
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .medium)
            }
            b.backgroundColor = UIColor.systemBackground
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return b
        }

        // MARK: cores

        static let keywords: [String: [String]] = [
            "gd": ["func", "var", "const", "extends", "class_name", "if", "elif", "else", "for", "while", "match", "return",
                   "pass", "break", "continue", "signal", "static", "enum", "true", "false", "null", "and", "or", "not",
                   "in", "is", "as", "self", "await", "preload", "export", "onready"],
            "java": ["public", "private", "protected", "class", "interface", "static", "final", "void", "int", "long", "double",
                     "float", "boolean", "char", "String", "new", "return", "if", "else", "for", "while", "do", "switch", "case",
                     "break", "continue", "try", "catch", "finally", "throw", "throws", "import", "package", "extends",
                     "implements", "this", "super", "null", "true", "false", "abstract", "enum", "var"],
            "kt": ["fun", "val", "var", "class", "object", "interface", "if", "else", "for", "while", "when", "return", "import",
                   "package", "null", "true", "false", "is", "in", "as", "override", "open", "data", "sealed", "companion",
                   "private", "public", "protected", "internal", "try", "catch", "finally", "throw", "this", "super", "lateinit", "by"],
            "swift": ["func", "var", "let", "class", "struct", "enum", "protocol", "extension", "if", "else", "guard", "switch",
                      "case", "default", "for", "while", "repeat", "return", "import", "init", "self", "nil", "true", "false",
                      "try", "catch", "throw", "throws", "async", "await", "private", "public", "static", "some", "in", "as", "is"],
            "cpp": ["int", "long", "short", "double", "float", "char", "bool", "void", "auto", "const", "static", "class",
                    "struct", "enum", "namespace", "using", "template", "typename", "public", "private", "protected", "virtual",
                    "override", "new", "delete", "return", "if", "else", "for", "while", "do", "switch", "case", "break",
                    "continue", "try", "catch", "throw", "true", "false", "nullptr", "include", "define", "std", "this", "unsigned"]
        ]

        func group(_ ext: String) -> String {
            switch ext {
            case "c", "cpp", "cc", "cxx", "h", "hpp": return "cpp"
            case "kt", "kts": return "kt"
            default: return ext
            }
        }

        func rules() -> [(String, UIColor)] {
            let g = group(parent.ext)
            var r: [(String, UIColor)] = []
            if let kw = Coordinator.keywords[g] {
                r.append(("\\b(" + kw.joined(separator: "|") + ")\\b", UIColor.systemPink))
            }
            r.append((#"\b[0-9]+(\.[0-9]+)?\b"#, UIColor.systemOrange))
            r.append((#""(\\.|[^"\\\n])*""#, UIColor.systemRed))
            r.append((#"'(\\.|[^'\\\n])*'"#, UIColor.systemRed))
            if g == "gd" || parent.ext == "yml" || parent.ext == "yaml" || parent.ext == "sh" {
                r.append((#"#[^\n]*"#, UIColor.systemGreen))
            } else if ["cpp", "java", "kt", "swift", "gradle", "js"].contains(g) || parent.ext == "gradle" {
                r.append((#"//[^\n]*"#, UIColor.systemGreen))
                r.append((#"/\*[\s\S]*?\*/"#, UIColor.systemGreen))
            }
            return r
        }

        func highlight(_ tv: UITextView) {
            if tv.markedTextRange != nil { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            let font = UIFont.monospacedSystemFont(ofSize: Prefs.editorFontSize, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: UIColor.label], range: full)
            if storage.length < 60000 {
                for (pattern, color) in rules() {
                    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
                    re.enumerateMatches(in: storage.string, options: [], range: full) { m, _, _ in
                        if let r = m?.range { storage.addAttribute(.foregroundColor, value: color, range: r) }
                    }
                }
            }
            storage.endEditing()
            tv.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
        }
    }
}
