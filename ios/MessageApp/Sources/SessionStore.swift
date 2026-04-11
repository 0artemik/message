import Combine
import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var token: String?
    @Published var user: UserDTO?
    @Published private(set) var isRestoringSession = true

    private let key = "message.auth.token"
    private var cancellables = Set<AnyCancellable>()
    private var presenceTimer: Timer?
    private var currentPushToken: String?

    init() {
        token = UserDefaults.standard.string(forKey: key)
        APIClient.shared.setToken(token)
        NotificationCenter.default.publisher(for: .apiUnauthorized)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logout()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pushTokenUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let token = note.object as? String, !token.isEmpty else { return }
                self?.currentPushToken = token
                Task { await self?.registerPushTokenIfPossible() }
            }
            .store(in: &cancellables)
        Task { await hydrateUser() }
    }

    private func startPresenceHeartbeatIfNeeded() {
        presenceTimer?.invalidate()
        presenceTimer = nil
        guard token != nil else { return }
        Task { try? await APIClient.shared.presencePing() }
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard self?.token != nil else { return }
            Task { try? await APIClient.shared.presencePing() }
        }
    }

    private func stopPresenceHeartbeat() {
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startPresenceHeartbeatIfNeeded()
        default:
            stopPresenceHeartbeat()
        }
    }

    func hydrateUser() async {
        guard let t = token else {
            isRestoringSession = false
            return
        }
        do {
            guard let url = URL(string: "/api/auth/me", relativeTo: APIConfig.baseURL) else { return }
            var req = URLRequest(url: url)
            req.setValue("ios", forHTTPHeaderField: "X-Client-Type")
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                isRestoringSession = false
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    logout()
                } else {
                    APIClient.shared.setToken(t)
                }
                isRestoringSession = false
                return
            }
            struct Me: Decodable, Sendable {
                let user: UserDTO
            }
            let me = try JSONDecoder().decode(Me.self, from: data)
            user = me.user
            APIClient.shared.setToken(t)
            startPresenceHeartbeatIfNeeded()
            await registerPushTokenIfPossible()
        } catch {
            APIClient.shared.setToken(t)
        }
        isRestoringSession = false
    }

    func login(username: String, password: String) async throws {
        APIClient.shared.setToken(nil)
        let res = try await APIClient.shared.login(username: username, password: password)
        applyAuth(res)
    }

    func register(username: String, email: String, password: String, displayName: String) async throws {
        APIClient.shared.setToken(nil)
        let res = try await APIClient.shared.register(
            username: username,
            email: email,
            password: password,
            displayName: displayName
        )
        applyAuth(res)
    }

    private func applyAuth(_ res: AuthResponse) {
        token = res.token
        user = res.user
        UserDefaults.standard.set(res.token, forKey: key)
        APIClient.shared.setToken(res.token)
        startPresenceHeartbeatIfNeeded()
        Task { await registerPushTokenIfPossible() }
    }

    func logout() {
        stopPresenceHeartbeat()
        token = nil
        user = nil
        isRestoringSession = false
        UserDefaults.standard.removeObject(forKey: key)
        Task { APIClient.shared.setToken(nil) }
    }

    private func registerPushTokenIfPossible() async {
        guard token != nil else { return }
        guard let push = currentPushToken, !push.isEmpty else { return }
        try? await APIClient.shared.registerPushToken(token: push)
    }
}
