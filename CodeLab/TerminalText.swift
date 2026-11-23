import SwiftUI
import UIKit

// MARK: - Sugestões

struct SuggestItem {
    let title: String
    let subtitle: String?
    let result: String?
    let icon: String
}

@MainActor
enum TermSuggest {
    static let extraCmds = ["sed", "awk", "tar", "gzip", "curl", "find", "diff", "du", "stat", "sort", "uniq", "tr"]
    static let pathCmds: Set<String> = ["cd", "ls", "cat", "head", "tail", "grep", "rm", "mv", "cp", "mkdir", "touch",
                                         "wc", "tree", "sed", "awk", "tar", "gzip", "find", "diff", "du", "stat", "sort", "uniq", "git"]

    static func items(for input: String, model m: TerminalModel) -> [SuggestItem] {
        if input.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var out: [SuggestItem] = []
        if let h = m.hint(for: input) {
            if let f = h.fix {
                out.append(SuggestItem(title: f, subtitle: h.text, result: f, icon: "exclamationmark.triangle"))
            } else {
                out.append(SuggestItem(title: h.text, subtitle: nil, result: nil, icon: "exclamationmark.triangle"))
            }
        }
        out += completions(input, m)
        return out
    }

    static func completions(_ s: String, _ m: TerminalModel) -> [SuggestItem] {
        let endsSpace = s.hasSuffix(" ")
        let toks = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let cmd = toks.first else { return [] }
        var out: [SuggestItem] = []

        if toks.count == 1 && !endsSpace {
            let q = cmd.lowercased()
            for c in m.suggestions(for: s) {
                out.append(SuggestItem(title: c.cmd, subtitle: c.desc, result: c.insert, icon: "terminal"))
            }
            for n in Catalog.localNames + extraCmds where n.hasPrefix(q) && n != q {
                if !out.contains(where: { $0.result == n || ($0.result ?? "").hasPrefix(n + " ") }) {
                    out.append(SuggestItem(title: n, subtitle: nil, result: n + " ", icon: "chevron.right"))
                }
            }
            return Array(out.prefix(10))
        }

        if cmd == "git" && ((toks.count == 1 && endsSpace) || (toks.count == 2 && !endsSpace)) {
            let prefix = toks.count == 2 ? toks[1].lowercased() : ""
            for sub in Catalog.gitSubs where sub.hasPrefix(prefix) && sub != prefix {
                out.append(SuggestItem(title: "git " + sub, subtitle: nil, result: "git " + sub + " ", icon: "arrow.triangle.branch"))
            }
            return Array(out.prefix(10))
        }

        guard pathCmds.contains(cmd) else { return [] }
        if cmd == "git" {
            let sub = toks.count > 1 ? toks[1] : ""
            if !["add", "rm", "reset"].contains(sub) { return [] }
        }
        let last = endsSpace ? "" : (toks.last ?? "")
        if last.hasPrefix("-") { return [] }
        var dirPart = ""
        var namePart = last
        if let r = last.range(of: "/", options: .backwards) {
            dirPart = String(last[..<r.upperBound])
            namePart = String(last[r.upperBound...])
        }
        var base = m.cwd
        if dirPart.hasPrefix("~/") {
            base = Store.root.appendingPathComponent(String(dirPart.dropFirst(2)))
        } else if dirPart.hasPrefix("/") {
            base = Store.root.appendingPathComponent(String(dirPart.dropFirst()))
        } else if !dirPart.isEmpty {
            base = m.cwd.appendingPathComponent(dirPart)
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        let showHidden = namePart.hasPrefix(".")
        var entries: [(String, Bool)] = []
        for n in names where n.lowercased().hasPrefix(namePart.lowercased()) && (showHidden || !n.hasPrefix(".")) && n != ".codelab" {
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: base.appendingPathComponent(n).path, isDirectory: &d)
            if cmd == "cd" && !d.boolValue { continue }
            entries.append((n, d.boolValue))
        }
        entries.sort { x, y in
            if x.1 != y.1 { return x.1 }
            return x.0.lowercased() < y.0.lowercased()
        }
        let head = String(s.dropLast(last.count))
        for e in entries.prefix(12) {
            out.append(SuggestItem(title: e.0 + (e.1 ? "/" : ""), subtitle: nil,
                                   result: head + dirPart + e.0 + (e.1 ? "/" : " "),
                                   icon: e.1 ? "folder" : "doc"))
        }
        return out
    }
}

// MARK: - Janela "pendurada" com as sugestões

final class SuggestionVC: UIViewController {
    let items: [SuggestItem]
    let pick: (String?) -> Void

    init(items: [SuggestItem], pick: @escaping (String?) -> Void) {
        self.items = items
        self.pick = pick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -6)
        ])
        for it in items { stack.addArrangedSubview(row(it)) }
    }

    func row(_ it: SuggestItem) -> UIView {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.plain()
        cfg.title = it.title
        cfg.subtitle = it.subtitle
        cfg.image = UIImage(systemName: it.icon)
        cfg.imagePadding = 8
        cfg.baseForegroundColor = it.icon == "exclamationmark.triangle" ? .systemOrange : .label
        cfg.titleAlignment = .leading
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { c in
            var c = c
            c.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            return c
        }
        cfg.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { c in
            var c = c
            c.font = UIFont.systemFont(ofSize: 11)
            c.foregroundColor = UIColor.secondaryLabel
            return c
        }
        b.configuration = cfg
        b.contentHorizontalAlignment = .leading
        b.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let r = it.result
            self.dismiss(animated: true) { self.pick(r) }
        }, for: .touchUpInside)
        return b
    }
}

// MARK: - Terminal digitável

/// O texto do terminal é um só: a saída dos comandos e, no final, a linha onde você digita.
struct TerminalTextView: UIViewRepresentable {
    @ObservedObject var m: TerminalModel
    @Binding var inject: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.spellCheckingType = .no
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 16, right: 8)
        tv.inputAccessoryView = context.coordinator.makeBar()
        tv.addSubview(context.coordinator.bulb)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        context.coordinator.textView = tv
        context.coordinator.rebuild(input: "")
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
        if let t = inject {
            context.coordinator.apply(t)
            DispatchQueue.main.async { inject = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIPopoverPresentationControllerDelegate, UIGestureRecognizerDelegate {
        var parent: TerminalTextView
        weak var textView: UITextView?
        var inputStart = 0
        var lastOut = ""
        var lastPrompt = ""
        var lastBusy = false
        var histIdx = -1
        var items: [SuggestItem] = []
        var clearNext = false
        let bulb = UIButton(type: .system)

        static let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        static let boldFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        static var inputAttrs: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: UIColor.label]
        }

        init(_ p: TerminalTextView) {
            parent = p
            super.init()
            bulb.setImage(UIImage(systemName: "lightbulb.fill"), for: .normal)
            bulb.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .bold), forImageIn: .normal)
            bulb.tintColor = .systemYellow
            bulb.isHidden = true
            bulb.addTarget(self, action: #selector(bulbTapped), for: .touchUpInside)
        }

        // MARK: montar o texto

        func color(_ l: String) -> UIColor {
            let low = l.lowercased()
            if l.hasPrefix("~") && l.contains(" $ ") { return .systemBlue }
            if low.hasPrefix("erro") || low.hasPrefix("error") || low.hasPrefix("fatal") || l.hasPrefix("✗") || l.hasPrefix("❌") { return .systemRed }
            if l.hasPrefix("✓") || l.hasPrefix("✅") { return .systemGreen }
            if l.hasPrefix("⚠️") { return .systemOrange }
            return .label
        }

        func rebuild(input: String) {
            guard let tv = textView else { return }
            let model = parent.m
            let attr = NSMutableAttributedString()
            var body = model.out
            if !body.isEmpty && !body.hasSuffix("\n") { body += "\n" }
            var lines = body.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            if lines.count > 800 { lines = Array(lines.suffix(800)) }
            for l in lines {
                let isCmd = l.hasPrefix("~") && l.contains(" $ ")
                attr.append(NSAttributedString(string: l + "\n", attributes: [
                    .font: isCmd ? Coordinator.boldFont : Coordinator.font,
                    .foregroundColor: color(l)
                ]))
            }
            if !model.busy {
                attr.append(NSAttributedString(string: model.prompt + " ", attributes: [
                    .font: Coordinator.boldFont,
                    .foregroundColor: UIColor.systemBlue
                ]))
                inputStart = attr.length
                attr.append(NSAttributedString(string: input, attributes: Coordinator.inputAttrs))
            } else {
                inputStart = attr.length
            }
            tv.isEditable = !model.busy
            tv.attributedText = attr
            tv.typingAttributes = Coordinator.inputAttrs
            let end = attr.length
            tv.selectedRange = NSRange(location: end, length: 0)
            lastOut = model.out
            lastPrompt = model.prompt
            lastBusy = model.busy
            refreshSuggestions()
            DispatchQueue.main.async { tv.scrollRangeToVisible(NSRange(location: end, length: 0)) }
        }

        func sync() {
            let model = parent.m
            if model.out != lastOut || model.prompt != lastPrompt || model.busy != lastBusy {
                let keep = (clearNext || lastBusy) ? "" : currentInput()
                clearNext = false
                rebuild(input: keep)
            }
        }

        func currentInput() -> String {
            guard let tv = textView else { return "" }
            let ns = tv.text as NSString
            if inputStart > ns.length { return "" }
            return ns.substring(from: inputStart)
        }

        // MARK: edição

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            if parent.m.busy { return false }
            if range.location < inputStart { return false }
            if t == "\n" { submit(); return false }
            if t.contains("\n") {
                tv.insertText(t.replacingOccurrences(of: "\n", with: " "))
                return false
            }
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            histIdx = -1
            refreshSuggestions()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            if tv.selectedRange.length == 0 && tv.selectedRange.location < inputStart {
                tv.selectedRange = NSRange(location: inputStart, length: 0)
            }
        }

        func submit() {
            let model = parent.m
            if model.busy { return }
            let line = currentInput().trimmingCharacters(in: .whitespaces)
            histIdx = -1
            clearNext = true
            if line.isEmpty {
                model.out += model.prompt + "\n"
                return
            }
            model.submit(line)
            UserDefaults.standard.set(Array(model.history.suffix(100)), forKey: "termHistory")
        }

        /// Troca o que está digitado (usado pelas sugestões, pelo histórico e pela ajuda).
        func apply(_ r: String?) {
            guard let r = r, let tv = textView, !parent.m.busy else { return }
            let len = tv.textStorage.length
            if inputStart > len { return }
            tv.textStorage.replaceCharacters(in: NSRange(location: inputStart, length: len - inputStart), with: r)
            tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
            refreshSuggestions()
            tv.becomeFirstResponder()
        }

        // MARK: sublinhado amarelo + lâmpada

        func refreshSuggestions() {
            guard let tv = textView else { return }
            let len = tv.textStorage.length
            guard inputStart <= len else { return }
            let r = NSRange(location: inputStart, length: len - inputStart)
            items = parent.m.busy ? [] : TermSuggest.items(for: currentInput(), model: parent.m)
            tv.textStorage.setAttributes(Coordinator.inputAttrs, range: r)
            if !items.isEmpty && r.length > 0 {
                tv.textStorage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: UIColor.systemYellow
                ], range: r)
            }
            tv.typingAttributes = Coordinator.inputAttrs
            positionBulb(r)
        }

        func positionBulb(_ r: NSRange) {
            guard let tv = textView else { return }
            if items.isEmpty || r.length == 0 {
                bulb.isHidden = true
                return
            }
            tv.layoutManager.ensureLayout(for: tv.textContainer)
            let gr = tv.layoutManager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            let rect = tv.layoutManager.boundingRect(forGlyphRange: gr, in: tv.textContainer)
            let x = rect.maxX + tv.textContainerInset.left + 1
            let y = rect.minY + tv.textContainerInset.top - 9
            bulb.frame = CGRect(x: min(x, tv.bounds.width - 20), y: max(0, y), width: 14, height: 14)
            bulb.isHidden = false
        }

        @objc func bulbTapped() { showSuggestions() }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let tv = textView else { return }
            if !tv.isFirstResponder { tv.becomeFirstResponder() }
            if items.isEmpty { return }
            let pt = g.location(in: tv)
            let p = CGPoint(x: pt.x - tv.textContainerInset.left, y: pt.y - tv.textContainerInset.top)
            let idx = tv.layoutManager.characterIndex(for: p, in: tv.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            if idx >= inputStart && tv.textStorage.length > inputStart { showSuggestions() }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        func topVC() -> UIViewController? {
            var vc = textView?.window?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }

        func showSuggestions() {
            guard !items.isEmpty, let tv = textView, let top = topVC() else { return }
            if top is SuggestionVC { return }
            let vc = SuggestionVC(items: items) { [weak self] r in self?.apply(r) }
            vc.modalPresentationStyle = .popover
            let h = items.reduce(CGFloat(12)) { $0 + ($1.subtitle == nil ? 40 : 54) }
            vc.preferredContentSize = CGSize(width: min(300, tv.bounds.width - 24), height: min(h, 280))
            if let pop = vc.popoverPresentationController {
                pop.sourceView = tv
                pop.sourceRect = bulb.isHidden ? CGRect(x: 20, y: 20, width: 1, height: 1) : bulb.frame
                pop.permittedArrowDirections = [.up, .down]
                pop.delegate = self
            }
            top.present(vc, animated: true)
        }

        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
            .none
        }

        // MARK: barra acima do teclado

        func histUp() {
            let h = parent.m.history
            if h.isEmpty { return }
            histIdx = histIdx < 0 ? h.count - 1 : max(0, histIdx - 1)
            apply(h[histIdx])
        }

        func histDown() {
            let h = parent.m.history
            if histIdx < 0 { return }
            histIdx += 1
            if histIdx >= h.count {
                histIdx = -1
                apply("")
            } else {
                apply(h[histIdx])
            }
        }

        func applyFirst() {
            if let r = items.first(where: { $0.result != nil })?.result { apply(r) }
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
            func add(_ symbol: String?, _ title: String, _ action: @escaping () -> Void) {
                stack.addArrangedSubview(makeButton(symbol: symbol, title: title, action))
            }
            add("keyboard.chevron.compact.down", "⌄") { [weak self] in self?.textView?.resignFirstResponder() }
            add(nil, "Tab") { [weak self] in self?.applyFirst() }
            add("arrow.up", "↑") { [weak self] in self?.histUp() }
            add("arrow.down", "↓") { [weak self] in self?.histDown() }
            for sym in ["/", "~", "-", ".", "|", ">", "\"", "'", "&", "*", "$", "="] {
                add(nil, sym) { [weak self] in self?.textView?.insertText(sym) }
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
    }
}

// MARK: - Tela do terminal

struct TerminalView: View {
    var start: URL? = nil
    @EnvironmentObject var gh: GitHub
    @StateObject private var m = TerminalModel()
    @State private var showHelp = false
    @State private var inject: String? = nil

    init(start: URL? = nil) {
        self.start = start
    }

    var tipBar: some View {
        Group {
            if Prefs.terminalTips, !m.busy, let n = m.next {
                HStack {
                    Text("💡 " + n.desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                    Button("Usar") { inject = n.insert }.font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tipBar
            TerminalTextView(m: m, inject: $inject)
        }
        .dockInset()
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showHelp = true } label: { Label("Comandos", systemImage: "questionmark.circle") }
                    Button { UIPasteboard.general.string = m.out } label: { Label("Copiar tudo", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { m.out = "" } label: { Label("Limpar", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showHelp) {
            CheatSheet { text in inject = text }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if m.out.count > 8000 { m.out = String(m.out.suffix(6000)) }
        }
        .onAppear {
            m.gh = gh
            if !m.started {
                m.started = true
                if let s = start { m.cwd = s }
                m.history = UserDefaults.standard.stringArray(forKey: "termHistory") ?? []
            }
            m.refresh()
        }
    }
}
