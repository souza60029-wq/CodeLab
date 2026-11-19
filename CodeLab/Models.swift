import SwiftUI

enum Lang: String, CaseIterable, Identifiable {
    case cpp, godot, java, android, ios
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpp: return "C / C++"
        case .godot: return "Godot"
        case .java: return "Java"
        case .android: return "Android"
        case .ios: return "iOS"
        }
    }
    var hint: String {
        switch self {
        case .cpp: return "Roda no aparelho"
        case .godot: return "GDScript + projeto"
        case .java: return "Roda no aparelho"
        case .android: return "Java ou Kotlin → APK"
        case .ios: return "Projeto vazio → IPA"
        }
    }
    var icon: String {
        switch self {
        case .cpp: return "chevron.left.forwardslash.chevron.right"
        case .godot: return "gamecontroller"
        case .java: return "cup.and.saucer"
        case .android: return "iphone.homebutton"
        case .ios: return "apple.logo"
        }
    }
}

final class Store: ObservableObject {
    static let root: URL = {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Projects")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    func dir(_ l: Lang, _ n: String) -> URL {
        Store.root.appendingPathComponent(l.rawValue).appendingPathComponent(n)
    }

    func projects(_ l: Lang) -> [String] {
        let p = Store.root.appendingPathComponent(l.rawValue).path
        return ((try? FileManager.default.contentsOfDirectory(atPath: p)) ?? []).sorted()
    }

    func create(_ l: Lang, _ n: String, kotlin: Bool = false, minSdk: Int = 24, sample: Int = 0) {
        let d = dir(l, n)
        for (p, c) in Templates.files(l, n, kotlin: kotlin, minSdk: minSdk, sample: sample) {
            let u = d.appendingPathComponent(p)
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? c.write(to: u, atomically: true, encoding: .utf8)
        }
    }

    func delete(_ l: Lang, _ n: String) {
        try? FileManager.default.removeItem(at: dir(l, n))
    }

    static func cleanName(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    }

    static func files(in d: URL) -> [String] {
        let subs = (try? FileManager.default.subpathsOfDirectory(atPath: d.path)) ?? []
        return subs.filter { p in
            if p == ".codelab" || p.hasPrefix(".codelab/") { return false }
            if p == ".git" || p.hasPrefix(".git/") { return false }
            if p.hasSuffix(".DS_Store") { return false }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: d.appendingPathComponent(p).path, isDirectory: &isDir)
            return !isDir.boolValue
        }.sorted()
    }
}
