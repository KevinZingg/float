import Foundation

/// Turns what people type into a URL: "3000" and ":5173" mean localhost, bare hosts get https.
enum URLInput {
    static func url(from input: String) -> URL? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if let port = port(s) { return URL(string: "http://localhost:\(port)") }
        if s.contains("://") { return URL(string: s) }
        let local = s.hasPrefix("localhost") || s.hasPrefix("127.0.0.1") || s.hasPrefix("0.0.0.0")
        return URL(string: (local ? "http://" : "https://") + s)
    }

    /// Whether the launcher should treat the input as a preview rather than a shell command.
    static func looksLikeURL(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return false }
        return port(s) != nil || s.hasPrefix("http") || s.hasPrefix("localhost") || s.contains(".")
    }

    /// "3000" or ":3000" → 3000.
    private static func port(_ s: String) -> Int? {
        let digits = s.hasPrefix(":") ? String(s.dropFirst()) : s
        guard let n = Int(digits), (1...65535).contains(n) else { return nil }
        return n
    }
}
