import Foundation

enum APIConfig {
    /// Без завершающего /. Для iPhone в сети Wi‑Fi укажите IP машины с сервером.
    static var baseURL: URL = URL(string: "http://127.0.0.1:3001")!
}
