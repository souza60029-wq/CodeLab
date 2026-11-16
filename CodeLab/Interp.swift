import Foundation

/// Interpretador pequeno de C/C++ e Java para rodar no próprio aparelho.
/// Suporta: variáveis, if/else, while, for, funções, recursão, cout/printf/System.out, strings e operadores básicos.
/// Ainda não suporta: arrays, ponteiros, classes com objetos, entrada (cin/Scanner), variáveis globais.
enum Val {
    case int(Int), dbl(Double), str(String), bool(Bool), void
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
    // remove "std ::"
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

    var toks: [Tok] = []
    var pos = 0
    var skip = 0
    var out = ""
    var scopes: [[String: Val]] = [[:]]
    var funcs: [String: (params: [String], body: Int)] = [:]
    var steps = 0
    var depth = 0
    var fixed = false
    var prec = 6
    let java: Bool

    let types: Set<String> = ["int", "long", "short", "double", "float", "bool", "boolean", "string", "String", "char", "auto", "var", "size_t"]
    let mods: Set<String> = ["const", "static", "final", "public", "private", "protected", "unsigned", "signed", "extern", "inline"]
    let keywords: Set<String> = ["return", "if", "else", "while", "for", "new", "do", "break", "continue", "class", "struct", "namespace", "using", "import", "package", "switch", "case", "throw", "sizeof"]

    init(java: Bool) { self.java = java }

    func run(_ src: String) -> String {
        do {
            toks = lexSource(src)
            try scanFuncs()
            guard let m = funcs["main"] else { throw InterpError(msg: "função main não encontrada") }
            pos = m.body
            scopes = [[:]]
            _ = try execBlock()
        } catch let e as InterpError {
            out += "\n[erro] " + e.msg + "\n"
        } catch {
            out += "\n[erro] \(error)\n"
        }
        return out.isEmpty ? "(sem saída)" : out
    }

    // MARK: pré-leitura das funções

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
        return nil
    }

    func assign(_ n: String, _ v: Val) {
        var i = scopes.count - 1
        while i >= 0 {
            if scopes[i][n] != nil { scopes[i][n] = v; return }
            i -= 1
        }
        scopes[scopes.count - 1][n] = v
    }

    func num(_ v: Val) -> Double {
        switch v {
        case .int(let i): return Double(i)
        case .dbl(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .str(let s): return Double(s) ?? 0
        case .void: return 0
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
        case .void: return false
        }
    }

    func text(_ v: Val) -> String {
        switch v {
        case .int(let i): return String(i)
        case .dbl(let d): return java ? "\(d)" : String(format: "%g", d)
        case .str(let s): return s
        case .bool(let b): return java ? (b ? "true" : "false") : (b ? "1" : "0")
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

    // MARK: operadores

    func bin(_ op: String, _ a: Val, _ b: Val) throws -> Val {
        if skip > 0 { return .int(0) }
        if op == "+" {
            if case .str = a { return .str(text(a) + text(b)) }
            if case .str = b { return .str(text(a) + text(b)) }
        }
        if op == "==" || op == "!=" {
            var eq = false
            if case .str(let x) = a, case .str(let y) = b { eq = (x == y) } else { eq = num(a) == num(b) }
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
        if let t = cur, t.kind == 0, pos + 1 < toks.count, toks[pos + 1].kind == 3,
           ["=", "+=", "-=", "*=", "/=", "%="].contains(toks[pos + 1].t), !keywords.contains(t.t) {
            let name = t.t
            let op = toks[pos + 1].t
            pos += 2
            let rhs = try assignExpr()
            if skip > 0 { return rhs }
            var v = rhs
            if op != "=" { v = try bin(String(op.dropLast()), lookup(name) ?? .int(0), rhs) }
            assign(name, v)
            return v
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
            if t.t == "true" { pos += 1; return .bool(true) }
            if t.t == "false" { pos += 1; return .bool(false) }
            if t.t == "Math" {
                pos += 1
                try expect(".")
                guard let n = cur, n.kind == 0 else { throw InterpError(msg: "Math. incompleto") }
                pos += 1
                return try call(n.t)
            }
            if t.t == "new" { throw InterpError(msg: "'new' (objetos) ainda não é suportado") }
            if t.t == "cin" || t.t == "Scanner" { throw InterpError(msg: "entrada de dados (cin/Scanner) ainda não é suportada") }
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
            if skip > 0 { return .int(0) }
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
                let args = try readArgs()
                if skip > 0 { v = .int(0); continue }
                let s = text(v)
                let a0 = args.first ?? .int(0)
                switch m {
                case "length", "size": v = .int(s.count)
                case "charAt", "at":
                    let arr = Array(s)
                    let i = toInt(num(a0))
                    v = (i >= 0 && i < arr.count) ? .str(String(arr[i])) : .str("")
                case "equals": v = .bool(s == text(a0))
                case "toUpperCase": v = .str(s.uppercased())
                case "toLowerCase": v = .str(s.lowercased())
                default: throw InterpError(msg: "método ." + m + "() não suportado")
                }
            } else if isOp("["), skip == 0, case .str(let s) = v {
                pos += 1
                let i = toInt(num(try expr()))
                try expect("]")
                let arr = Array(s)
                v = (i >= 0 && i < arr.count) ? .str(String(arr[i])) : .str("")
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
        case "pow": return .dbl(pow(num(arg(0)), num(arg(1))))
        case "floor": return .dbl(floor(num(arg(0))))
        case "ceil": return .dbl(ceil(num(arg(0))))
        case "round": return .dbl(num(arg(0)).rounded())
        case "fabs": return .dbl(abs(num(arg(0))))
        case "abs":
            if case .int(let i) = arg(0) { return .int(abs(i)) }
            return .dbl(abs(num(arg(0))))
        case "min", "max":
            let a = arg(0), b = arg(1)
            let useA = name == "min" ? num(a) <= num(b) : num(a) >= num(b)
            return useA ? a : b
        case "to_string": return .str(text(arg(0)))
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
        if isOp("*") { throw InterpError(msg: "ponteiros ainda não são suportados") }
        if isOp("[") { throw InterpError(msg: "arrays ainda não são suportados") }
        while true {
            guard let n = cur, n.kind == 0 else { throw InterpError(msg: "nome de variável esperado") }
            pos += 1
            if isOp("[") { throw InterpError(msg: "arrays ainda não são suportados") }
            var v = defaultVal(ty)
            if isOp("=") {
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
            case "for": return try forStmt()
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
            case "System":
                try javaPrint()
                return .next
            case "cin", "Scanner":
                throw InterpError(msg: "entrada de dados (cin/Scanner) ainda não é suportada")
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
