import Foundation

enum APIConfig {
    private static let backendHostKey = "api.backend.host"
    private static let backendPortKey = "api.backend.port"
    private static let defaultHost = "127.0.0.1"
    private static let defaultPort = "3001"

    /// Без завершающего /. Для iPhone в сети Wi‑Fi укажите IP машины с сервером.
    static var baseURL: URL {
        let host = storedHost
        let port = storedPort
        return URL(string: "http://\(host):\(port)")!
    }

    static var backendHost: String { storedHost }
    static var backendPort: String { storedPort }

    static func updateBackend(host: String, port: String) {
        let normalizedHost = normalizedHostValue(host)
        let normalizedPort = normalizedPortValue(port)
        UserDefaults.standard.set(normalizedHost, forKey: backendHostKey)
        UserDefaults.standard.set(normalizedPort, forKey: backendPortKey)
    }

    private static var storedHost: String {
        let value = UserDefaults.standard.string(forKey: backendHostKey) ?? defaultHost
        return normalizedHostValue(value)
    }

    private static var storedPort: String {
        let value = UserDefaults.standard.string(forKey: backendPortKey) ?? defaultPort
        return normalizedPortValue(value)
    }

    private static func normalizedHostValue(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultHost }
        let withoutScheme = trimmed
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        let hostOnly = withoutScheme.split(separator: ":").first.map(String.init) ?? withoutScheme
        return hostOnly.isEmpty ? defaultHost : hostOnly
    }

    private static func normalizedPortValue(_ port: String) -> String {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intPort = Int(trimmed), (1...65535).contains(intPort) else {
            return defaultPort
        }
        return String(intPort)
    }
}
