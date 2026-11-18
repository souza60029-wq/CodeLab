import Foundation

/// Terminal real: usa o ios_system (o mesmo motor do a-Shell) para rodar ls, grep, sed, awk, tar, curl etc.
/// As funções são buscadas em tempo de execução (dlsym); se o framework não estiver no app, o terminal antigo continua funcionando.
enum RealShell {
    typealias SysFn = @convention(c) (UnsafePointer<CChar>?) -> Int32
    typealias StreamsFn = @convention(c) (UnsafeMutablePointer<FILE>?, UnsafeMutablePointer<FILE>?, UnsafeMutablePointer<FILE>?) -> Void
    typealias InitFn = @convention(c) () -> Void
    typealias ExecFn = @convention(c) (UnsafePointer<CChar>?) -> Bool

    static var sys: SysFn?
    static var streams: StreamsFn?
    static var isExec: ExecFn?
    static var ready = false
    static var tried = false

    final class Box { var data = Data() }

    static func setup() -> Bool {
        if tried { return ready }
        tried = true
        if let dir = Bundle.main.privateFrameworksPath {
            _ = dlopen(dir + "/ios_system.framework/ios_system", RTLD_NOW | RTLD_GLOBAL)
        }
        guard let def = UnsafeMutableRawPointer(bitPattern: -2) else { return false }
        guard let s = dlsym(def, "ios_system") else { return false }
        sys = unsafeBitCast(s, to: SysFn.self)
        if let p = dlsym(def, "ios_setStreams") { streams = unsafeBitCast(p, to: StreamsFn.self) }
        if let p = dlsym(def, "ios_executable") { isExec = unsafeBitCast(p, to: ExecFn.self) }
        if let p = dlsym(def, "initializeEnvironment") { unsafeBitCast(p, to: InitFn.self)() }
        ready = true
        return true
    }

    static func has(_ cmd: String) -> Bool {
        guard setup(), let f = isExec else { return false }
        return cmd.withCString { f($0) }
    }

    static func run(_ line: String, cwd: URL) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(line, cwd))
            }
        }
    }

    static func runSync(_ line: String, _ cwd: URL) -> String {
        guard setup(), let sys = sys else { return "terminal real indisponível neste build" }
        var fds: [Int32] = [0, 0]
        if pipe(&fds) != 0 { return "erro ao criar pipe" }
        let rfd = fds[0]
        guard let wr = fdopen(fds[1], "w") else { return "erro ao abrir pipe" }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.data = FileHandle(fileDescriptor: rfd, closeOnDealloc: true).readDataToEndOfFile()
            group.leave()
        }
        streams?(stdin, wr, wr)
        _ = ("cd '" + cwd.path + "'").withCString { sys($0) }
        let rc = line.withCString { sys($0) }
        fflush(wr)
        streams?(stdin, stdout, stderr)
        fclose(wr)
        group.wait()
        var out = String(decoding: box.data, as: UTF8.self)
        while out.hasSuffix("\n") { out.removeLast() }
        if out.isEmpty && rc != 0 { out = "(código de saída " + String(rc) + ")" }
        return out
    }
}
