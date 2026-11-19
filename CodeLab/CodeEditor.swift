import SwiftUI
import UIKit

/// Editor de código com cores, barra de símbolos acima do teclado e auto-indentação.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let ext: String

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
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var textView: UITextView?

        init(_ p: CodeEditor) { parent = p }

        // MARK: delegate

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            highlight(tv)
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            if t == "\n" {
                let ns = tv.text as NSString
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let beforeLen = range.location - lineRange.location
                let before = beforeLen > 0 ? ns.substring(with: NSRange(location: lineRange.location, length: beforeLen)) : ""
                var indent = ""
                for ch in before {
                    if ch == " " || ch == "\t" { indent.append(ch) } else { break }
                }
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                var extra = ""
                let unit = parent.ext == "gd" ? "\t" : "    "
                if trimmed.hasSuffix("{") || (parent.ext == "gd" && trimmed.hasSuffix(":")) { extra = unit }
                if !indent.isEmpty || !extra.isEmpty {
                    tv.insertText("\n" + indent + extra)
                    return false
                }
            }
            return true
        }

        // MARK: barra de símbolos

        func insertSymbol(_ s: String) {
            guard let tv = textView else { return }
            tv.insertText(s)
        }

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

            let hide = makeButton("⌄") { [weak self] in self?.textView?.resignFirstResponder() }
            stack.addArrangedSubview(hide)
            let tabText = parent.ext == "gd" ? "\t" : "    "
            let tab = makeButton("Tab") { [weak self] in self?.insertSymbol(tabText) }
            stack.addArrangedSubview(tab)

            let symbols = ["{", "}", "(", ")", "[", "]", ";", ":", "\"", "'", "<", ">", "=", "+", "-", "*", "/", "\\", "#", "&", "|", "!", "_", ".", ",", "$", "%", "?"]
            for sym in symbols {
                let b = makeButton(sym) { [weak self] in self?.insertSymbol(sym) }
                stack.addArrangedSubview(b)
            }
            return scroll
        }

        func makeButton(_ title: String, _ action: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .medium)
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
