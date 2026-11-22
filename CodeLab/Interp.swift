import Foundation

/// Interpretador de C/C++ e Java para rodar no próprio aparelho.
/// Suporta: variáveis (inclusive globais), arrays (1D e 2D), if/else, while, do-while, for, for-each, switch,
/// funções e recursão, cout/printf/System.out, entrada (cin, Scanner), strings e funções matemáticas.
/// Ainda não suporta: ponteiros, classes com objetos, templates e a STL.
enum Val {
    case int(Int), dbl(Double), str(String), bool(Bool), arr(Int), void
}

struct InterpError: Error { let msg: String }

struct Tok {
    let t: String
    let kind: Int   // 0 identificador, 1 número, 2 string, 3 símbolo, 4 char
}

func lexSource(_ src: String) -> [Tok] {
    let c = Array(src)
    var i = 0
    var out: [Tok] = []
    var lineStart = true
    let ops2 = ["<<", ">>", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "::", "->"]
    while i < c.count {
        let ch = c[i]
        if ch == "\n" { lineStart = true; i += 1; continue }
        if ch == " " || ch == "\t" || ch == "\r" { i += 1; continue }
        if ch == "#" && lineStart {
            while i < c.count && c[i] != "\n" { i += 1 }
            continue
        }
        lineStart = false
        if ch == "/" && i + 1 < c.count && c[i + 1] == "/" {
            while i < c.count && c[i] != "\n" { i += 1 }
            continue
        }
        if ch == "/" && i + 1 < c.count && c[i + 1] == "*" {
            i += 2
            while i + 1 < c.count && !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
            i += 2
            continue
        }
        if ch.isLetter || ch == "_" {
            var s = ""
            while i < c.count && (c[i].isLetter || c[i].isNumber || c[i] == "_") { s.append(c[i]); i += 1 }
            out.append(Tok(t: s, kind: 0))
            continue
        }
        if ch.isNumber {
            var s = ""
            while i < c.count && (c[i].isNumber || c[i] == ".") { s.append(c[i]); i += 1 }
            if i < c.count && "fFlLuU".contains(c[i]) { i += 1 }
            out.append(Tok(t: s, kind: 1))
            continue
        }
        if ch == "\"" || ch == "'" {
            let q = ch
            i += 1
            var s = ""
            while i < c.count && c[i] != q {
                if c[i] == "\\" && i + 1 < c.count {
                    i += 1
                    switch c[i] {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    default: s.append(c[i])
                    }
                } else {
                    s.append(c[i])
                }
                i += 1
            }
            i += 1
            out.append(Tok(t: s, kind: q == "'" ? 4 : 2))
            continue
        }
        if i + 1 < c.count {
            let two = String([ch, c[i + 1]])
            if ops2.contains(two) { out.append(Tok(t: two, kind: 3)); i += 2; continue }
        }
        out.append(Tok(t: String(ch), kind: 3))
        i += 1
    }
    var res: [Tok] = []
    var k = 0
    while k < out.count {
        if out[k].kind == 0 && out[k].t == "std" && k + 1 < out.count && out[k + 1].t == "::" { k += 2; continue }
        res.append(out[k])
        k += 1
    }
    return res
}

final class Interp {
    enum Flow { case next, brk, cont, ret(Val) }
    static let scannerTag = "\u{1}scanner"

    var toks: [Tok] = []
    var pos = 0
    var skip = 0
    var out = ""
    var scopes: [[String: Val]] = [[:]]
    var globals: [String: Val] = [:]
    var globalDecls: [Int] = []
    var funcs: [String: (params: [String], body: Int)] = [:]
    var arrays: [[Val]] = []
    var steps = 0
    var depth = 0
    var fixed = false
    var prec = 6
    var input: [Character] = []
    var ipos = 0
    let java: Bool

    let types: Set<String> = ["int", "long", "short", "double", "float", "bool", "boolean", "string", "String", "char", "auto", "var", "size_t", "Scanner"]
    let mods: Set<String> = ["const", "static", "final", "public", "private", "protected", "unsigned", "signed", "extern", "inline"]
    let keywords: Set<String> = ["return", "if", "else", "while", "for", "new", "do", "break", "continue", "class", "struct", "namespace",
                                 "using", "import", "package", "switch", "case", "default", "throw", "sizeof"]
    let assignOps: Set<String> = ["=", "+=", "-=", "*=", "/=", "%="]

    init(java: Bool, input: String = "") {
        self.java = java
        self.input = Array(input)
    }

    func run(_ src: String) -> String {
        do {
            toks = lexSource(src)
            try scanFuncs()
            guard let m = funcs["main"] else { throw InterpError(msg: "função main não encontrada") }
            globals = [:]
            for idx in globalDecls {
                pos = idx
                skip = 0
                scopes = [globals]
                try decl()
                globals = scopes[0]
            }
            scopes = [[:]]
            scopes[0]["args"] = .arr(newArray([]))
            pos = m.body
            _ = try execBlock()
        } catch let e as InterpError {
            out += "\n[erro] " + e.msg + "\n"
        } catch {
            out += "\n[erro] \(error)\n"
        }
        return out.isEmpty ? "(sem saída)" : out
    }

    // MARK: pré-leitura

    func isGlobalDeclStart(_ i: Int) -> Bool {
        if i > 0 {
            let p = toks[i - 1]
            if !(p.kind == 3 && (p.t == ";" || p.t == "{" || p.t == "}")) { return false }
        }
        var j = i
        while j < toks.count, toks[j].kind == 0, mods.contains(toks[j].t) { j += 1 }
        guard j + 2 < toks.count, toks[j].kind == 0, types.contains(toks[j].t) else { return false }
        var k = j + 1
        while k + 1 < toks.count, toks[k].t == "[", toks[k + 1].t == "]" { k += 2 }
        guard k + 1 < toks.count, toks[k].kind == 0, !keywords.contains(toks[k].t) else { return false }
        let nx = toks[k + 1]
        return nx.kind == 3 && ["=", ";", "[", ","].contains(nx.t)
    }

    func scanFuncs() throws {
        var i = 0
        while i + 2 < toks.count {
            let a = toks[i], b = toks[i + 1], c = toks[i + 2]
            if a.kind == 0, b.kind == 0, c.kind == 3, c.t == "(", !keywords.contains(a.t), !keywords.contains(b.t) {
                var k = i + 3
                var groups: [[Tok]] = [[]]
                var d = 1
                while k < toks.count {
                    let t = toks[k]
                    if t.kind == 3 && t.t == "(" { d += 1 }
                    else if t.kind == 3 && t.t == ")" { d -= 1; if d == 0 { break } }
                    if d == 1 && t.kind == 3 && t.t == "," { groups.append([]) } else { groups[groups.count - 1].append(t) }
                    k += 1
                }
                if k + 1 < toks.count && toks[k + 1].kind == 3 && toks[k + 1].t == "{" {
                    var names: [String] = []
                    for g in groups {
                        if g.count == 1 && g[0].t == "void" { continue }
                        if let n = g.last(where: { $0.kind == 0 }) { names.append(n.t) }
                    }
                    funcs[b.t] = (params: names, body: k + 1)
                    var bd = 0
                    var m = k + 1
                    while m < toks.count {
                        if toks[m].kind == 3 {
                            if toks[m].t == "{" { bd += 1 }
                            else if toks[m].t == "}" { bd -= 1; if bd == 0 { break } }
                        }
                        m += 1
                    }
                    i = m + 1
                    continue
                }
            }
            if isGlobalDeclStart(i) { globalDecls.append(i) }
            i += 1
        }
    }

    // MARK: utilidades

    var cur: Tok? { pos < toks.count ? toks[pos] : nil }

    func isOp(_ s: String) -> Bool {
        if let t = cur, t.kind == 3, t.t == s { return true }
        return false
    }

    func isId(_ s: String) -> Bool {
        if let t = cur, t.kind == 0, t.t == s { return true }
        return false
    }

    func expect(_ s: String) throws {
        guard isOp(s) else {
            let near = cur?.t ?? "fim"
            throw InterpError(msg: "esperava '" + s + "' perto de '" + near + "'")
        }
        pos += 1
    }

    func tick() throws {
        steps += 1
        if steps > 3_000_000 { throw InterpError(msg: "limite de execução atingido (loop infinito?)") }
    }

    func lookup(_ n: String) -> Val? {
        for s in scopes.reversed() { if let v = s[n] { return v } }
        return globals[n]
    }

    func assign(_ n: String, _ v: Val) {
        var i = scopes.count - 1
        while i >= 0 {
            if scopes[i][n] != nil { scopes[i][n] = v; return }
            i -= 1
        }
        if globals[n] != nil { globals[n] = v; return }
        scopes[scopes.count - 1][n] = v
    }

    func num(_ v: Val) -> Double {
        switch v {
        case .int(let i): return Double(i)
        case .dbl(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .str(let s): return Double(s) ?? 0
        case .arr, .void: return 0
        }
    }

    func toInt(_ d: Double) -> Int {
        if d.isNaN || d.isInfinite { return 0 }
        return Int(max(min(d, 9e18), -9e18))
    }

    func truthy(_ v: Val) -> Bool {
        switch v {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .dbl(let d): return d != 0
        case .str(let s): return !s.isEmpty
        case .arr: return true
        case .void: return false
        }
    }

    func text(_ v: Val) -> String {
        switch v {
        case .int(let i): return String(i)
        case .dbl(let d): return java ? "\(d)" : String(format: "%g", d)
        case .str(let s): return s
        case .bool(let b): return java ? (b ? "true" : "false") : (b ? "1" : "0")
        case .arr: return "[array]"
        case .void: return ""
        }
    }

    func coerce(_ ty: String, _ v: Val) -> Val {
        if skip > 0 { return .int(0) }
        switch ty {
        case "int", "long", "short", "size_t": return .int(toInt(num(v)))
        case "double", "float": return .dbl(num(v))
        case "bool", "boolean": return .bool(truthy(v))
        case "string", "String": return .str(text(v))
        case "char":
            if case .int(let i) = v { return .str(String(Character(UnicodeScalar(UInt8(clamping: i))))) }
            return v
        default: return v
        }
    }

    func defaultVal(_ ty: String) -> Val {
        switch ty {
        case "double", "float": return .dbl(0)
        case "bool", "boolean": return .bool(false)
        case "string", "String", "char": return .str("")
        default: return .int(0)
        }
    }

    // MARK: arrays

    func newArray(_ a: [Val]) -> Int {
        arrays.append(a)
        return arrays.count - 1
    }

    func makeArray(_ dims: [Int], _ ty: String) throws -> Val {
        var total = 1
        for d in dims {
            if d < 0 { throw InterpError(msg: "NegativeArraySizeException: " + String(d)) }
            total *= max(1, d)
            if total > 2_000_000 { throw InterpError(msg: "array grande demais") }
        }
        return buildArray(dims, ty)
    }

    func buildArray(_ dims: [Int], _ ty: String) -> Val {
        if dims.count == 1 { return .arr(newArray(Array(repeating: defaultVal(ty), count: dims[0]))) }
        var items: [Val] = []
        for _ in 0..<dims[0] { items.append(buildArray(Array(dims.dropFirst()), ty)) }
        return .arr(newArray(items))
    }

    func getIndex(_ v: Val, _ i: Int) throws -> Val {
        guard case .arr(let id) = v else { throw InterpError(msg: "isso não é um array") }
        guard i >= 0 && i < arrays[id].count else {
            throw InterpError(msg: "índice " + String(i) + " fora do limite (tamanho " + String(arrays[id].count) + ")")
        }
        return arrays[id][i]
    }

    func setIndex(_ base: Val, _ idxs: [Int], _ nv: Val) throws {
        var curV = base
        for k in 0..<(idxs.count - 1) { curV = try getIndex(curV, idxs[k]) }
        guard case .arr(let id) = curV else { throw InterpError(msg: "isso não é um array") }
        let last = idxs[idxs.count - 1]
        guard last >= 0 && last < arrays[id].count else {
            throw InterpError(msg: "índice " + String(last) + " fora do limite (tamanho " + String(arrays[id].count) + ")")
        }
        arrays[id][last] = nv
    }

    func indexValue(_ v: Val, _ i: Int) throws -> Val {
        if case .str(let s) = v {
            let arr = Array(s)
            return (i >= 0 && i < arr.count) ? .str(String(arr[i])) : .str("")
        }
        return try getIndex(v, i)
    }

    func parseIndices() throws -> [Int] {
        var idxs: [Int] = []
        while isOp("[") {
            pos += 1
            let iv = try expr()
            try expect("]")
            idxs.append(toInt(num(iv)))
        }
        return idxs
    }

    func readVar(_ name: String, _ idxs: [Int]) throws -> Val {
        var v = lookup(name) ?? .int(0)
        for i in idxs { v = try getIndex(v, i) }
        return v
    }

    func writeVar(_ name: String, _ idxs: [Int], _ nv: Val) throws {
        if idxs.isEmpty { assign(name, nv); return }
        guard let base = lookup(name) else { throw InterpError(msg: "variável '" + name + "' não declarada") }
        try setIndex(base, idxs, nv)
    }

    func arrayLiteral(_ ty: String) throws -> Val {
        try expect("{")
        var items: [Val] = []
        if !isOp("}") {
            while true {
                if isOp("{") { items.append(try arrayLiteral(ty)) } else { items.append(coerce(ty, try expr())) }
                if isOp(",") {
                    pos += 1
                    if isOp("}") { break }
                } else { break }
            }
        }
        try expect("}")
        if skip > 0 { return .int(0) }
        return .arr(newArray(items))
    }

    func sizeOf(_ v: Val) -> Int {
        switch v {
        case .int: return 4
        case .dbl: return 8
        case .bool, .str: return 1
        case .arr(let id):
            let first = arrays[id].first ?? .int(0)
            return arrays[id].count * sizeOf(first)
        case .void: return 0
        }
    }

    // MARK: entrada

    func skipWS() {
        while ipos < input.count && input[ipos].isWhitespace { ipos += 1 }
    }

    func readToken() throws -> String {
        skipWS()
        if ipos >= input.count { throw InterpError(msg: "a entrada acabou (preencha o campo Entrada)") }
        var s = ""
        while ipos < input.count && !input[ipos].isWhitespace { s.append(input[ipos]); ipos += 1 }
        return s
    }

    func readLine() throws -> String {
        if ipos >= input.count { throw InterpError(msg: "a entrada acabou (preencha o campo Entrada)") }
        var s = ""
        while ipos < input.count && input[ipos] != "\n" { s.append(input[ipos]); ipos += 1 }
        if ipos < input.count { ipos += 1 }
        if s.hasSuffix("\r") { s.removeLast() }
        return s
    }

    func readInto(_ old: Val) throws -> Val {
        let t = try readToken()
        switch old {
        case .int:
            guard let i = Int(t) else { throw InterpError(msg: "entrada inválida: esperava um inteiro e veio \"" + t + "\"") }
            return .int(i)
        case .dbl:
            guard let d = Double(t) else { throw InterpError(msg: "entrada inválida: esperava um número e veio \"" + t + "\"") }
            return .dbl(d)
        case .bool:
            return .bool(t == "1" || t.lowercased() == "true")
        default:
            return .str(t)
        }
    }

    func scannerCall(_ m: String, _ a: [Val]) throws -> Val {
        switch m {
        case "nextInt", "nextLong", "nextShort":
            let t = try readToken()
            guard let i = Int(t) else { throw InterpError(msg: "InputMismatchException: \"" + t + "\"") }
            return .int(i)
        case "nextDouble", "nextFloat":
            let t = try readToken()
            guard let d = Double(t) else { throw InterpError(msg: "InputMismatchException: \"" + t + "\"") }
            return .dbl(d)
        case "nextBoolean":
            return .bool(try readToken().lowercased() == "true")
        case "next":
            return .str(try readToken())
        case "nextLine":
            return .str(try readLine())
        case "hasNextLine":
            return .bool(ipos < input.count)
        case "hasNext", "hasNextInt", "hasNextDouble":
            skipWS()
            if ipos >= input.count { return .bool(false) }
            if m == "hasNext" { return .bool(true) }
            var j = ipos
            var s = ""
            while j < input.count && !input[j].isWhitespace { s.append(input[j]); j += 1 }
            return .bool(m == "hasNextInt" ? Int(s) != nil : Double(s) != nil)
        case "close":
            return .void
        default:
            throw InterpError(msg: "Scanner." + m + "() não suportado")
        }
    }

    // MARK: operadores

    func bin(_ op: String, _ a: Val, _ b: Val) throws -> Val {
        if skip > 0 { return .int(0) }
        if op == "+" {
            if case .str = a { return .str(text(a) + text(b)) }
            if case .str = b { return .str(text(a) + text(b)) }
        }
        if op == "==" || op == "!=" {
            var eq = false
            if case .str(let x) = a, case .str(let y) = b { eq = (x == y) }
            else if case .arr(let x) = a, case .arr(let y) = b { eq = (x == y) }
            else { eq = num(a) == num(b) }
            return .bool(op == "==" ? eq : !eq)
        }
        if case .int(let x) = a, case .int(let y) = b {
            switch op {
            case "+": return .int(x &+ y)
            case "-": return .int(x &- y)
            case "*": return .int(x &* y)
            case "/":
                if y == 0 { throw InterpError(msg: "divisão por zero") }
                return .int(x / y)
            case "%":
                if y == 0 { throw InterpError(msg: "divisão por zero") }
                return .int(x % y)
            case "<": return .bool(x < y)
            case ">": return .bool(x > y)
            case "<=": return .bool(x <= y)
            case ">=": return .bool(x >= y)
            default: break
            }
        }
        let x = num(a), y = num(b)
        switch op {
        case "+": return .dbl(x + y)
        case "-": return .dbl(x - y)
        case "*": return .dbl(x * y)
        case "/": return .dbl(x / y)
        case "%": return .dbl(fmod(x, y))
        case "<": return .bool(x < y)
        case ">": return .bool(x > y)
        case "<=": return .bool(x <= y)
        case ">=": return .bool(x >= y)
        default: throw InterpError(msg: "operador '" + op + "' não suportado")
        }
    }

    // MARK: expressões

    func expr() throws -> Val { try assignExpr() }

    func assignExpr() throws -> Val {
        if let t = cur, t.kind == 0, !keywords.contains(t.t), pos + 1 < toks.count {
            let n1 = toks[pos + 1]
            if n1.kind == 3 && assignOps.contains(n1.t) {
                let name = t.t
                let op = n1.t
                pos += 2
                let rhs = try assignExpr()
                if skip > 0 { return rhs }
                var v = rhs
                if op != "=" { v = try bin(String(op.dropLast()), lookup(name) ?? .int(0), rhs) }
                assign(name, v)
                return v
            }
            if n1.kind == 3 && n1.t == "[" {
                let save = pos
                skip += 1
                pos += 1
                _ = try parseIndices()
                var isAssign = false
                if let c = cur, c.kind == 3, assignOps.contains(c.t) || c.t == "++" || c.t == "--" { isAssign = true }
                skip -= 1
                pos = save
                if isAssign {
                    let name = t.t
                    pos += 1
                    let idxs = try parseIndices()
                    let op = cur?.t ?? "="
                    pos += 1
                    if op == "++" || op == "--" {
                        if skip > 0 { return .int(0) }
                        let old = try readVar(name, idxs)
                        try writeVar(name, idxs, try bin("+", old, .int(op == "++" ? 1 : -1)))
                        return old
                    }
                    let rhs = try assignExpr()
                    if skip > 0 { return rhs }
                    var v = rhs
                    if op != "=" { v = try bin(String(op.dropLast()), try readVar(name, idxs), rhs) }
                    try writeVar(name, idxs, v)
                    return v
                }
            }
        }
        return try ternary()
    }

    func ternary() throws -> Val {
        let c = try orExpr()
        if isOp("?") {
            pos += 1
            let cond = skip == 0 ? truthy(c) : false
            if !cond { skip += 1 }
            let t = try assignExpr()
            if !cond { skip -= 1 }
            try expect(":")
            if cond { skip += 1 }
            let f = try assignExpr()
            if cond { skip -= 1 }
            if skip > 0 { return .int(0) }
            return cond ? t : f
        }
        return c
    }

    func orExpr() throws -> Val {
        var l = try andExpr()
        while isOp("||") {
            pos += 1
            let short = skip == 0 && truthy(l)
            if short { skip += 1 }
            let r = try andExpr()
            if short { skip -= 1 }
            l = skip > 0 ? .int(0) : .bool(short ? true : truthy(r))
        }
        return l
    }

    func andExpr() throws -> Val {
        var l = try eqExpr()
        while isOp("&&") {
            pos += 1
            let short = skip == 0 && !truthy(l)
            if short { skip += 1 }
            let r = try eqExpr()
            if short { skip -= 1 }
            l = skip > 0 ? .int(0) : .bool(short ? false : truthy(r))
        }
        return l
    }

    func eqExpr() throws -> Val {
        var l = try relExpr()
        while isOp("==") || isOp("!=") {
            let op = cur!.t
            pos += 1
            l = try bin(op, l, try relExpr())
        }
        return l
    }

    func relExpr() throws -> Val {
        var l = try addExpr()
        while isOp("<") || isOp(">") || isOp("<=") || isOp(">=") {
            let op = cur!.t
            pos += 1
            l = try bin(op, l, try addExpr())
        }
        return l
    }

    func addExpr() throws -> Val {
        var l = try mulExpr()
        while isOp("+") || isOp("-") {
            let op = cur!.t
            pos += 1
            l = try bin(op, l, try mulExpr())
        }
        return l
    }

    func mulExpr() throws -> Val {
        var l = try unary()
        while isOp("*") || isOp("/") || isOp("%") {
            let op = cur!.t
            pos += 1
            l = try bin(op, l, try unary())
        }
        return l
    }

    func unary() throws -> Val {
        if isOp("!") {
            pos += 1
            let v = try unary()
            return skip > 0 ? .int(0) : .bool(!truthy(v))
        }
        if isOp("-") {
            pos += 1
            let v = try unary()
            if skip > 0 { return .int(0) }
            if case .int(let i) = v { return .int(-i) }
            return .dbl(-num(v))
        }
        if isOp("+") { pos += 1; return try unary() }
        if (isOp("++") || isOp("--")), pos + 1 < toks.count, toks[pos + 1].kind == 0 {
            let d = isOp("++") ? 1 : -1
            let n = toks[pos + 1].t
            pos += 2
            if skip > 0 { return .int(0) }
            let nv = try bin("+", lookup(n) ?? .int(0), .int(d))
            assign(n, nv)
            return nv
        }
        return try primary()
    }

    func readArgs() throws -> [Val] {
        try expect("(")
        var args: [Val] = []
        if !isOp(")") {
            while true {
                args.append(try expr())
                if isOp(",") { pos += 1 } else { break }
            }
        }
        try expect(")")
        return args
    }

    func newExpr() throws -> Val {
        pos += 1
        guard let tn = cur, tn.kind == 0 else { throw InterpError(msg: "esperava um tipo depois de 'new'") }
        pos += 1
        if tn.t == "Scanner" || tn.t == "BufferedReader" || tn.t == "InputStreamReader" {
            if isOp("(") {
                var d = 0
                repeat {
                    if isOp("(") { d += 1 } else if isOp(")") { d -= 1 }
                    pos += 1
                } while d > 0 && cur != nil
            }
            return .str(Interp.scannerTag)
        }
        if types.contains(tn.t) {
            var dims: [Int] = []
            while isOp("[") {
                pos += 1
                if isOp("]") { pos += 1 } else {
                    let dv = try expr()
                    dims.append(toInt(num(dv)))
                    try expect("]")
                }
            }
            if isOp("{") { return try arrayLiteral(tn.t) }
            if skip > 0 { return .int(0) }
            if dims.isEmpty { throw InterpError(msg: "faltou o tamanho do array") }
            return try makeArray(dims, tn.t)
        }
        throw InterpError(msg: "'new " + tn.t + "' (objetos) ainda não é suportado")
    }

    func sizeofExpr() throws -> Val {
        pos += 1
        try expect("(")
        var result = 4
        if let c = cur, c.kind == 0, types.contains(c.t) {
            pos += 1
            switch c.t {
            case "double", "long": result = 8
            case "char", "bool", "boolean": result = 1
            case "short": result = 2
            default: result = 4
            }
        } else {
            let v = try expr()
            if skip == 0 { result = sizeOf(v) }
        }
        try expect(")")
        return .int(result)
    }

    func namespaceExpr() throws -> Val {
        let ns = toks[pos].t
        let name = toks[pos + 2].t
        pos += 3
        if isOp("(") {
            let args = try readArgs()
            if skip > 0 { return .int(0) }
            return try suffix(try nsCall(ns, name, args))
        }
        switch ns + "." + name {
        case "Integer.MAX_VALUE": return .int(Int(Int32.max))
        case "Integer.MIN_VALUE": return .int(Int(Int32.min))
        case "Long.MAX_VALUE": return .int(Int.max)
        case "Long.MIN_VALUE": return .int(Int.min)
        case "Double.MAX_VALUE": return .dbl(Double.greatestFiniteMagnitude)
        default: throw InterpError(msg: ns + "." + name + " não suportado")
        }
    }

    func nsCall(_ ns: String, _ name: String, _ a: [Val]) throws -> Val {
        func arg(_ i: Int) -> Val { i < a.count ? a[i] : .int(0) }
        switch ns + "." + name {
        case "Integer.parseInt", "Long.parseLong":
            let s = text(arg(0)).trimmingCharacters(in: .whitespaces)
            guard let v = Int(s) else { throw InterpError(msg: "NumberFormatException: \"" + s + "\"") }
            return .int(v)
        case "Double.parseDouble":
            let s = text(arg(0)).trimmingCharacters(in: .whitespaces)
            guard let v = Double(s) else { throw InterpError(msg: "NumberFormatException: \"" + s + "\"") }
            return .dbl(v)
        case "String.valueOf", "Integer.toString", "Double.toString", "Long.toString", "Boolean.toString":
            return .str(text(arg(0)))
        case "String.format":
            return .str(format(a))
        case "Arrays.toString":
            guard case .arr(let id) = arg(0) else { return .str("null") }
            return .str("[" + arrays[id].map { text($0) }.joined(separator: ", ") + "]")
        case "Arrays.sort":
            guard case .arr(let id) = arg(0) else { return .void }
            var tmp = arrays[id]
            tmp.sort { (x: Val, y: Val) -> Bool in
                if case .str(let p) = x, case .str(let q) = y { return p < q }
                return num(x) < num(y)
            }
            arrays[id] = tmp
            return .void
        case "Arrays.fill":
            guard case .arr(let id) = arg(0) else { return .void }
            arrays[id] = Array(repeating: arg(1), count: arrays[id].count)
            return .void
        case "Character.isDigit": return .bool(text(arg(0)).first?.isNumber ?? false)
        case "Character.isLetter": return .bool(text(arg(0)).first?.isLetter ?? false)
        case "Character.isUpperCase": return .bool(text(arg(0)).first?.isUppercase ?? false)
        case "Character.isLowerCase": return .bool(text(arg(0)).first?.isLowercase ?? false)
        case "Character.toUpperCase": return .str(text(arg(0)).uppercased())
        case "Character.toLowerCase": return .str(text(arg(0)).lowercased())
        default: throw InterpError(msg: ns + "." + name + "() não suportado")
        }
    }

    func primary() throws -> Val {
        guard let t = cur else { throw InterpError(msg: "expressão incompleta") }
        if t.kind == 1 {
            pos += 1
            if t.t.contains(".") { return .dbl(Double(t.t) ?? 0) }
            return .int(Int(t.t) ?? 0)
        }
        if t.kind == 2 || t.kind == 4 {
            pos += 1
            return try suffix(.str(t.t))
        }
        if t.kind == 3 && t.t == "(" {
            if pos + 2 < toks.count, toks[pos + 1].kind == 0, types.contains(toks[pos + 1].t),
               toks[pos + 2].kind == 3, toks[pos + 2].t == ")" {
                let ty = toks[pos + 1].t
                pos += 3
                let v = try unary()
                return coerce(ty, v)
            }
            pos += 1
            let v = try expr()
            try expect(")")
            return try suffix(v)
        }
        if t.kind == 0 {
            switch t.t {
            case "true": pos += 1; return .bool(true)
            case "false": pos += 1; return .bool(false)
            case "null", "nullptr": pos += 1; return .int(0)
            case "new": return try newExpr()
            case "sizeof": return try sizeofExpr()
            case "cin": pos += 1; return .str("cin")
            case "Math":
                pos += 1
                try expect(".")
                guard let n = cur, n.kind == 0 else { throw InterpError(msg: "Math. incompleto") }
                pos += 1
                if n.t == "PI" && !isOp("(") { return .dbl(Double.pi) }
                if n.t == "E" && !isOp("(") { return .dbl(exp(1.0)) }
                return try suffix(try call(n.t))
            default: break
            }
            if ["Arrays", "Integer", "Double", "Long", "String", "Character", "Boolean"].contains(t.t),
               pos + 2 < toks.count, toks[pos + 1].kind == 3, toks[pos + 1].t == ".", toks[pos + 2].kind == 0 {
                return try namespaceExpr()
            }
            let name = t.t
            pos += 1
            if isOp("(") { return try suffix(try call(name)) }
            if isOp("++") || isOp("--") {
                let d = isOp("++") ? 1 : -1
                pos += 1
                if skip > 0 { return .int(0) }
                let old = lookup(name) ?? .int(0)
                assign(name, try bin("+", old, .int(d)))
                return old
            }
            if skip > 0 { return try suffix(.int(0)) }
            guard let v = lookup(name) else { throw InterpError(msg: "variável '" + name + "' não declarada") }
            return try suffix(v)
        }
        throw InterpError(msg: "símbolo inesperado '" + t.t + "'")
    }

    func suffix(_ v0: Val) throws -> Val {
        var v = v0
        while true {
            if isOp("."), pos + 1 < toks.count, toks[pos + 1].kind == 0 {
                let m = toks[pos + 1].t
                pos += 2
                if m == "length" && !isOp("(") {
                    if skip > 0 { v = .int(0); continue }
                    if case .arr(let id) = v { v = .int(arrays[id].count) } else { v = .int(text(v).count) }
                    continue
                }
                let args = try readArgs()
                if skip > 0 { v = .int(0); continue }
                if case .str(let tag) = v, tag == Interp.scannerTag {
                    v = try scannerCall(m, args)
                    continue
                }
                let s = text(v)
                let a0 = args.first ?? .int(0)
                let a1 = args.count > 1 ? args[1] : .int(0)
                switch m {
                case "length", "size": v = .int(s.count)
                case "isEmpty", "empty": v = .bool(s.isEmpty)
                case "charAt", "at":
                    let arr = Array(s)
                    let i = toInt(num(a0))
                    v = (i >= 0 && i < arr.count) ? .str(String(arr[i])) : .str("")
                case "equals": v = .bool(s == text(a0))
                case "equalsIgnoreCase": v = .bool(s.lowercased() == text(a0).lowercased())
                case "toUpperCase": v = .str(s.uppercased())
                case "toLowerCase": v = .str(s.lowercased())
                case "trim": v = .str(s.trimmingCharacters(in: .whitespacesAndNewlines))
                case "contains": v = .bool(s.contains(text(a0)))
                case "startsWith": v = .bool(s.hasPrefix(text(a0)))
                case "endsWith": v = .bool(s.hasSuffix(text(a0)))
                case "indexOf", "find":
                    if let r = s.range(of: text(a0)) { v = .int(s.distance(from: s.startIndex, to: r.lowerBound)) } else { v = .int(-1) }
                case "replace": v = .str(s.replacingOccurrences(of: text(a0), with: text(a1)))
                case "compareTo": v = .int(s == text(a0) ? 0 : (s < text(a0) ? -1 : 1))
                case "substring", "substr":
                    let arr = Array(s)
                    let from = max(0, min(arr.count, toInt(num(a0))))
                    var to = arr.count
                    if args.count > 1 {
                        let second = toInt(num(a1))
                        to = m == "substr" ? min(arr.count, from + max(0, second)) : max(from, min(arr.count, second))
                    }
                    v = .str(String(arr[from..<to]))
                default: throw InterpError(msg: "método ." + m + "() não suportado")
                }
            } else if isOp("[") {
                if skip > 0 {
                    pos += 1
                    _ = try expr()
                    try expect("]")
                    v = .int(0)
                    continue
                }
                switch v {
                case .arr, .str:
                    pos += 1
                    let i = toInt(num(try expr()))
                    try expect("]")
                    v = try indexValue(v, i)
                default:
                    return v
                }
            } else {
                return v
            }
        }
    }

    func call(_ name: String) throws -> Val {
        let args = try readArgs()
        if skip > 0 { return .int(0) }
        func arg(_ i: Int) -> Val { i < args.count ? args[i] : .int(0) }
        if let f = funcs[name] {
            try tick()
            depth += 1
            defer { depth -= 1 }
            if depth > 300 { throw InterpError(msg: "recursão profunda demais") }
            let savedPos = pos
            let savedScopes = scopes
            scopes = [[:]]
            for (i, p) in f.params.enumerated() { scopes[0][p] = arg(i) }
            pos = f.body
            let fl = try execBlock()
            pos = savedPos
            scopes = savedScopes
            if case .ret(let v) = fl { return v }
            return .void
        }
        switch name {
        case "printf": out += format(args); return .void
        case "puts": out += text(arg(0)) + "\n"; return .void
        case "sqrt": return .dbl(num(arg(0)).squareRoot())
        case "cbrt": return .dbl(cbrt(num(arg(0))))
        case "pow": return .dbl(pow(num(arg(0)), num(arg(1))))
        case "sin": return .dbl(sin(num(arg(0))))
        case "cos": return .dbl(cos(num(arg(0))))
        case "tan": return .dbl(tan(num(arg(0))))
        case "log": return .dbl(log(num(arg(0))))
        case "log10": return .dbl(log10(num(arg(0))))
        case "exp": return .dbl(exp(num(arg(0))))
        case "floor": return .dbl(floor(num(arg(0))))
        case "ceil": return .dbl(ceil(num(arg(0))))
        case "round":
            let r = num(arg(0)).rounded()
            return java ? .int(toInt(r)) : .dbl(r)
        case "fabs": return .dbl(abs(num(arg(0))))
        case "abs":
            if case .int(let i) = arg(0) { return .int(abs(i)) }
            return .dbl(abs(num(arg(0))))
        case "min", "max":
            let a = arg(0), b = arg(1)
            let useA = name == "min" ? num(a) <= num(b) : num(a) >= num(b)
            return useA ? a : b
        case "random": return .dbl(Double.random(in: 0..<1))
        case "rand": return .int(Int.random(in: 0...32767))
        case "srand": return .void
        case "to_string": return .str(text(arg(0)))
        case "stoi", "atoi": return .int(Int(text(arg(0)).trimmingCharacters(in: .whitespaces)) ?? 0)
        case "stod", "atof": return .dbl(Double(text(arg(0)).trimmingCharacters(in: .whitespaces)) ?? 0)
        case "strlen": return .int(text(arg(0)).count)
        case "toupper": return .str(text(arg(0)).uppercased())
        case "tolower": return .str(text(arg(0)).lowercased())
        case "isdigit": return .bool(text(arg(0)).first?.isNumber ?? false)
        case "isalpha": return .bool(text(arg(0)).first?.isLetter ?? false)
        case "isupper": return .bool(text(arg(0)).first?.isUppercase ?? false)
        case "islower": return .bool(text(arg(0)).first?.isLowercase ?? false)
        default: throw InterpError(msg: "função '" + name + "' não encontrada")
        }
    }

    func format(_ args: [Val]) -> String {
        guard let f = args.first else { return "" }
        let fmt = Array(text(f))
        var res = ""
        var ai = 1
        var i = 0
        while i < fmt.count {
            if fmt[i] != "%" { res.append(fmt[i]); i += 1; continue }
            i += 1
            if i < fmt.count && fmt[i] == "%" { res.append("%"); i += 1; continue }
            var spec = "%"
            while i < fmt.count && "-+ 0#123456789.".contains(fmt[i]) { spec.append(fmt[i]); i += 1 }
            while i < fmt.count && "lhz".contains(fmt[i]) { i += 1 }
            guard i < fmt.count else { break }
            let conv = fmt[i]
            i += 1
            if conv == "n" { res += "\n"; continue }
            let a: Val = ai < args.count ? args[ai] : Val.int(0)
            ai += 1
            switch conv {
            case "d", "i": res += String(format: spec + "ld", toInt(num(a)))
            case "f", "F": res += String(format: spec + "f", num(a))
            case "e", "g": res += String(format: spec + String(conv), num(a))
            case "x", "X": res += String(format: spec + "l" + String(conv), toInt(num(a)))
            case "c":
                if case .int(let n) = a { res.append(Character(UnicodeScalar(UInt8(clamping: n)))) } else { res += text(a) }
            case "s": res += text(a)
            default: res += spec + String(conv)
            }
        }
        return res
    }

    // MARK: comandos

    func execBlock() throws -> Flow {
        try expect("{")
        scopes.append([:])
        var result: Flow = .next
        var flowed = false
        while !isOp("}") {
            if cur == nil { throw InterpError(msg: "faltou '}'") }
            let f = try stmt()
            if case .next = f { continue }
            if !flowed { flowed = true; result = f; skip += 1 }
        }
        if flowed { skip -= 1 }
        pos += 1
        scopes.removeLast()
        return result
    }

    func isDecl() -> Bool {
        var j = pos
        while j < toks.count, toks[j].kind == 0, mods.contains(toks[j].t) { j += 1 }
        guard j + 1 < toks.count, toks[j].kind == 0, types.contains(toks[j].t) else { return false }
        let n = toks[j + 1]
        return n.kind == 0 || n.t == "[" || n.t == "*"
    }

    func decl() throws {
        while let t = cur, t.kind == 0, mods.contains(t.t) { pos += 1 }
        let ty = cur?.t ?? "int"
        pos += 1
        var javaDims = 0
        while isOp("["), pos + 1 < toks.count, toks[pos + 1].t == "]" {
            pos += 2
            javaDims += 1
        }
        if isOp("*") { throw InterpError(msg: "ponteiros ainda não são suportados") }
        while true {
            guard let n = cur, n.kind == 0 else { throw InterpError(msg: "nome de variável esperado") }
            pos += 1
            var dims: [Int] = []
            while isOp("[") {
                pos += 1
                if isOp("]") { dims.append(-1) } else {
                    let dv = try expr()
                    dims.append(toInt(num(dv)))
                }
                try expect("]")
            }
            var v = defaultVal(ty)
            if javaDims > 0 || !dims.isEmpty {
                if isOp("=") {
                    pos += 1
                    if isOp("{") { v = try arrayLiteral(ty) } else { v = try expr() }
                    if skip == 0, case .arr(let id) = v, let d0 = dims.first, d0 > arrays[id].count {
                        arrays[id] += Array(repeating: defaultVal(ty), count: d0 - arrays[id].count)
                    }
                } else if skip == 0 {
                    if dims.isEmpty || dims.contains(-1) { throw InterpError(msg: "faltou o tamanho do array '" + n.t + "'") }
                    v = try makeArray(dims, ty)
                } else {
                    v = .int(0)
                }
            } else if isOp("=") {
                pos += 1
                v = coerce(ty, try expr())
            } else if isOp("(") {
                pos += 1
                v = coerce(ty, try expr())
                try expect(")")
            }
            if skip == 0 { scopes[scopes.count - 1][n.t] = v }
            if isOp(",") { pos += 1; continue }
            break
        }
        try expect(";")
    }

    func stmt() throws -> Flow {
        try tick()
        guard let t = cur else { throw InterpError(msg: "fim inesperado do código") }
        if t.kind == 3 {
            if t.t == "{" { return try execBlock() }
            if t.t == ";" { pos += 1; return .next }
        }
        if t.kind == 0 {
            switch t.t {
            case "if": return try ifStmt()
            case "while": return try whileStmt()
            case "do": return try doWhileStmt()
            case "for": return try forStmt()
            case "switch": return try switchStmt()
            case "return":
                pos += 1
                var v: Val = .void
                if !isOp(";") { v = try expr() }
                try expect(";")
                return skip > 0 ? .next : .ret(v)
            case "break":
                pos += 1
                try expect(";")
                return skip > 0 ? .next : .brk
            case "continue":
                pos += 1
                try expect(";")
                return skip > 0 ? .next : .cont
            case "cout", "cerr":
                try coutStmt()
                return .next
            case "cin":
                try cinStmt()
                return .next
            case "getline":
                try getlineStmt()
                return .next
            case "System":
                try javaPrint()
                return .next
            default: break
            }
            if isDecl() { try decl(); return .next }
        }
        _ = try expr()
        try expect(";")
        return .next
    }

    func ifStmt() throws -> Flow {
        pos += 1
        try expect("(")
        let c = try expr()
        try expect(")")
        let go = skip == 0 && truthy(c)
        var flow: Flow = .next
        if go {
            flow = try stmt()
        } else {
            skip += 1
            _ = try stmt()
            skip -= 1
        }
        if isId("else") {
            pos += 1
            if !go && skip == 0 {
                flow = try stmt()
            } else {
                skip += 1
                _ = try stmt()
                skip -= 1
            }
        }
        return flow
    }

    func whileStmt() throws -> Flow {
        pos += 1
        let condPos = pos
        if skip > 0 {
            try expect("(")
            _ = try expr()
            try expect(")")
            _ = try stmt()
            return .next
        }
        var result: Flow = .next
        loop: while true {
            try tick()
            pos = condPos
            try expect("(")
            let c = try expr()
            try expect(")")
            if !truthy(c) {
                skip += 1
                _ = try stmt()
                skip -= 1
                break
            }
            let f = try stmt()
            switch f {
            case .brk: break loop
            case .ret: result = f; break loop
            default: break
            }
        }
        return result
    }

    func whileTail() throws -> Val {
        guard isId("while") else { throw InterpError(msg: "esperava 'while' depois do bloco do-while") }
        pos += 1
        try expect("(")
        let c = try expr()
        try expect(")")
        try expect(";")
        return c
    }

    func doWhileStmt() throws -> Flow {
        pos += 1
        let bodyPos = pos
        if skip > 0 {
            _ = try stmt()
            _ = try whileTail()
            return .next
        }
        var result: Flow = .next
        loop: while true {
            try tick()
            pos = bodyPos
            let f = try stmt()
            switch f {
            case .brk:
                skip += 1
                _ = try whileTail()
                skip -= 1
                break loop
            case .ret:
                result = f
                skip += 1
                _ = try whileTail()
                skip -= 1
                break loop
            default: break
            }
            let c = try whileTail()
            if !truthy(c) { break }
        }
        return result
    }

    func forStmt() throws -> Flow {
        pos += 1
        try expect("(")
        if skip > 0 {
            var d = 1
            while d > 0 {
                guard let t = cur else { throw InterpError(msg: "for incompleto") }
                if t.kind == 3 {
                    if t.t == "(" { d += 1 } else if t.t == ")" { d -= 1 }
                }
                pos += 1
            }
            _ = try stmt()
            return .next
        }

        // for-each:  for (int x : lista)
        var j = pos
        while j < toks.count, toks[j].kind == 0, mods.contains(toks[j].t) { j += 1 }
        if j + 2 < toks.count, toks[j].kind == 0, types.contains(toks[j].t),
           toks[j + 1].kind == 0, toks[j + 2].kind == 3, toks[j + 2].t == ":" {
            let ty = toks[j].t
            let name = toks[j + 1].t
            pos = j + 3
            let coll = try expr()
            try expect(")")
            var elems: [Val] = []
            switch coll {
            case .arr(let id): elems = arrays[id]
            case .str(let s): elems = s.map { Val.str(String($0)) }
            default: throw InterpError(msg: "o for-each espera um array ou um texto")
            }
            let bodyPos = pos
            skip += 1
            _ = try stmt()
            skip -= 1
            let endPos = pos
            var result: Flow = .next
            scopes.append([:])
            loop: for e in elems {
                try tick()
                scopes[scopes.count - 1][name] = coerce(ty, e)
                pos = bodyPos
                let f = try stmt()
                switch f {
                case .brk: break loop
                case .ret: result = f; break loop
                default: break
                }
            }
            scopes.removeLast()
            pos = endPos
            return result
        }

        scopes.append([:])
        if isOp(";") { pos += 1 }
        else if isDecl() { try decl() }
        else { _ = try expr(); try expect(";") }
        let condPos = pos
        skip += 1
        if !isOp(";") { _ = try expr() }
        skip -= 1
        try expect(";")
        let incPos = pos
        skip += 1
        if !isOp(")") { _ = try expr() }
        skip -= 1
        try expect(")")
        let bodyPos = pos
        skip += 1
        _ = try stmt()
        skip -= 1
        let endPos = pos
        var result: Flow = .next
        loop: while true {
            try tick()
            pos = condPos
            if !isOp(";") {
                let c = try expr()
                if !truthy(c) { break }
            }
            pos = bodyPos
            let f = try stmt()
            switch f {
            case .brk: break loop
            case .ret: result = f; break loop
            default: break
            }
            pos = incPos
            if !isOp(")") { _ = try expr() }
        }
        pos = endPos
        scopes.removeLast()
        return result
    }

    func switchStmt() throws -> Flow {
        pos += 1
        try expect("(")
        let v = try expr()
        try expect(")")
        try expect("{")
        let bodyStart = pos

        // fim do switch
        var endPos = bodyStart
        var d = 0
        var k = bodyStart
        while k < toks.count {
            let t = toks[k]
            if t.kind == 3 && t.t == "{" { d += 1 }
            else if t.kind == 3 && t.t == "}" {
                if d == 0 { endPos = k; break }
                d -= 1
            }
            k += 1
        }
        if skip > 0 {
            pos = endPos + 1
            return .next
        }

        // etiquetas
        var labels: [(Val, Int)] = []
        var defaultPos: Int? = nil
        var i = bodyStart
        d = 0
        while i < endPos {
            let t = toks[i]
            if t.kind == 3 && t.t == "{" { d += 1 }
            else if t.kind == 3 && t.t == "}" { d -= 1 }
            else if d == 0 && t.kind == 0 && t.t == "case" {
                pos = i + 1
                let cv = try expr()
                try expect(":")
                labels.append((cv, pos))
                i = pos
                continue
            } else if d == 0 && t.kind == 0 && t.t == "default" {
                pos = i + 1
                try expect(":")
                defaultPos = pos
                i = pos
                continue
            }
            i += 1
        }

        var start: Int? = nil
        for (cv, p) in labels {
            if truthy(try bin("==", v, cv)) { start = p; break }
        }
        if start == nil { start = defaultPos }
        guard let s0 = start else {
            pos = endPos + 1
            return .next
        }
        pos = s0
        scopes.append([:])
        var result: Flow = .next
        run: while pos < endPos {
            if isId("case") {
                pos += 1
                skip += 1
                _ = try expr()
                skip -= 1
                try expect(":")
                continue
            }
            if isId("default") {
                pos += 1
                try expect(":")
                continue
            }
            let f = try stmt()
            switch f {
            case .next: continue
            case .brk: break run
            default:
                result = f
                break run
            }
        }
        scopes.removeLast()
        pos = endPos + 1
        return result
    }

    func coutText(_ v: Val) -> String {
        if case .dbl(let d) = v {
            if fixed { return String(format: "%." + String(prec) + "f", d) }
            if prec != 6 { return String(format: "%." + String(prec) + "g", d) }
        }
        return text(v)
    }

    func coutStmt() throws {
        pos += 1
        while isOp("<<") {
            pos += 1
            if isId("endl") { pos += 1; if skip == 0 { out += "\n" }; continue }
            if isId("fixed") { pos += 1; fixed = true; continue }
            if isId("setprecision") {
                pos += 1
                try expect("(")
                let p = try expr()
                try expect(")")
                if skip == 0 { prec = toInt(num(p)) }
                continue
            }
            let v = try expr()
            if skip == 0 { out += coutText(v) }
        }
        try expect(";")
    }

    func cinStmt() throws {
        pos += 1
        while isOp(">>") {
            pos += 1
            guard let n = cur, n.kind == 0 else { throw InterpError(msg: "esperava uma variável depois de >>") }
            pos += 1
            let idxs = try parseIndices()
            if skip == 0 {
                let old = try readVar(n.t, idxs)
                try writeVar(n.t, idxs, try readInto(old))
            }
        }
        try expect(";")
    }

    func getlineStmt() throws {
        pos += 1
        try expect("(")
        if isId("cin") { pos += 1 }
        try expect(",")
        guard let n = cur, n.kind == 0 else { throw InterpError(msg: "esperava uma variável em getline") }
        pos += 1
        try expect(")")
        try expect(";")
        if skip == 0 { assign(n.t, .str(try readLine())) }
    }

    func javaPrint() throws {
        pos += 1
        try expect(".")
        pos += 1
        try expect(".")
        guard let m = cur, m.kind == 0 else { throw InterpError(msg: "System.out incompleto") }
        pos += 1
        let args = try readArgs()
        try expect(";")
        if skip > 0 { return }
        let a0 = args.first ?? .str("")
        switch m.t {
        case "println": out += text(a0) + "\n"
        case "print": out += text(a0)
        case "printf", "format": out += format(args)
        default: throw InterpError(msg: "System.out." + m.t + " não suportado")
        }
    }
}
