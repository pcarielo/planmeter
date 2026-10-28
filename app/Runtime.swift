import Foundation

enum Runtime {
    static let identifier = "io.github.pcarielo.planmeter"
    static let testModes:Set<String>=["--self-test","--ui-self-test","--confetti-self-test","--loop-self-test"]
    static var isTest: Bool { CommandLine.arguments.contains { testModes.contains($0) } }
    static var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PlanMeter", isDirectory: true)
    }
    static func cliEnvironment(binary: String, inherited: [String:String]) -> [String:String] {
        var result = inherited
        result.removeValue(forKey:"OPENAI_API_KEY"); result.removeValue(forKey:"CODEX_API_KEY")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var seen = Set<String>()
        let candidates = [URL(fileURLWithPath:binary).deletingLastPathComponent().path, home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] + (inherited["PATH"] ?? "").split(separator:":").map(String.init)
        result["PATH"] = candidates.filter { $0.hasPrefix("/") && seen.insert($0).inserted }.joined(separator:":")
        return result
    }
    static func codexPath() -> String {
        if isTest { return "/nonexistent/planmeter-test-codex" }
        let fm = FileManager.default
        if let data = try? Data(contentsOf: stateDirectory.appendingPathComponent("config.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = json["codexPath"] as? String, path.hasPrefix("/"), fm.isExecutableFile(atPath: path) { return path }
        let home = fm.homeDirectoryForCurrentUser.path
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return directories.map { $0 + "/codex" }.first { fm.isExecutableFile(atPath: $0) } ?? "/nonexistent/planmeter-codex"
    }
}
