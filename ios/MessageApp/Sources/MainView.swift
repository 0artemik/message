import SwiftUI
import UserNotifications

struct MainView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @State private var conversations: [ConversationDTO] = []
    @State private var searchText = ""
    @State private var searchResults: [UserDTO] = []
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var presence: [Int: PresenceStateDTO] = [:]
    @State private var didInitialLoad = false
    @State private var activeConversationId: Int?
    @Environment(\.scenePhase) private var scenePhase

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                searchRow

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    Section {
                        if searchResults.isEmpty {
                            Text("Никого не нашли")
                                .foregroundStyle(c.textSecondary)
                                .listRowBackground(c.sidebar)
                        } else {
                            ForEach(searchResults) { user in
                                Button {
                                    Task { await openDirect(with: user) }
                                } label: {
                                    userRow(user)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(c.sidebar)
                                .listRowSeparatorTint(c.border.opacity(0.6))
                            }
                        }
                    } header: {
                        sectionHeader("Люди")
                    }
                }

                Section {
                    ForEach(conversations) { conv in
                        NavigationLink(value: conv.id) {
                            conversationRow(conv)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            activeConversationId = conv.id
                        })
                        .listRowBackground(c.sidebar)
                        .listRowSeparatorTint(c.border.opacity(0.6))
                    }
                } header: {
                    sectionHeader("Чаты")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.chatBg)
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _, value in
                scheduleSearch(value)
            }
            .toolbarBackground(c.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(c.text)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(session.user?.displayName ?? "")
                        .font(.subheadline)
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                }
            }
            .navigationDestination(for: Int.self) { id in
                if let conv = conversations.first(where: { $0.id == id }) {
                    ChatView(conversation: conv, peerName: conv.peer.displayName)
                        .onDisappear {
                            activeConversationId = nil
                        }
                }
            }
            .task {
                await NotificationService.requestPermissionIfNeeded()
                await load(notify: false)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard scenePhase == .active else { continue }
                    await load(notify: true)
                }
            }
            .refreshable { await load() }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
                    .environmentObject(session)
                    .environmentObject(theme)
            }
        }
        .tint(c.blue)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(c.textSecondary)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Поиск пользователей").foregroundStyle(theme.isDark ? Color.white.opacity(0.65) : c.textSecondary)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundColor(theme.isDark ? .white : c.text)
            .tint(c.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(c.searchBg)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(c.chatBg)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.isDark ? Color.white.opacity(0.82) : c.textSecondary)
            .textCase(nil)
    }

    @ViewBuilder
    private func conversationRow(_ conv: ConversationDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [c.blue.opacity(0.85), c.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Text(initials(conv.peer.displayName))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                if presence[conv.peer.id]?.online == true {
                    Circle()
                        .fill(c.online)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(c.sidebar, lineWidth: 2))
                        .offset(x: 18, y: 18)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(conv.peer.displayName)
                    .font(.headline)
                    .foregroundStyle(c.text)
                Text("\(subtitle(conv))\(presenceSuffix(for: conv.peer.id))")
                    .font(.subheadline)
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
            }
            if conv.unreadCount > 0 {
                Text("\(conv.unreadCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(c.blue))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func userRow(_ user: UserDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [c.blue.opacity(0.85), c.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Text(initials(user.displayName))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                if presence[user.id]?.online == true {
                    Circle()
                        .fill(c.online)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(c.sidebar, lineWidth: 2))
                        .offset(x: 18, y: 18)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundStyle(c.text)
                Text("@\(user.username)\(presenceSuffix(for: user.id))")
                    .font(.subheadline)
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func initials(_ name: String) -> String {
        let p = name.split(separator: " ").map(String.init)
        let a = p.first?.first.map(String.init) ?? "?"
        let b = p.dropFirst().first?.first.map(String.init) ?? ""
        return (a + b).uppercased()
    }

    private func subtitle(_ c: ConversationDTO) -> String {
        guard let last = c.lastMessage else { return "Нет сообщений" }
        if last.kind == "voice" { return "Голосовое сообщение" }
        if last.kind == "video_note" { return "Видеосообщение" }
        if last.kind == "file" { return "📎 \(last.fileName ?? "Файл")" }
        return last.body
    }

    private func load(notify: Bool = true) async {
        errorText = nil
        do {
            let prev = conversations
            let next = try await APIClient.shared.conversations()
            conversations = next
            await refreshPresence(
                for: conversations.map(\.peer.id)
            )
            if didInitialLoad && notify {
                maybeNotifyIncoming(previous: prev, current: next)
            }
            didInitialLoad = true
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не удалось загрузить чаты"
        }
    }

    private func maybeNotifyIncoming(previous: [ConversationDTO], current: [ConversationDTO]) {
        guard !current.isEmpty else { return }
        let prevById = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for conv in current {
            if activeConversationId == conv.id { continue }
            guard let msg = conv.lastMessage else { continue }
            guard msg.senderId != session.user?.id else { continue }
            let prevUnread = prevById[conv.id]?.unreadCount ?? 0
            if conv.unreadCount <= prevUnread { continue }
            NotificationService.postIncomingMessage(
                conversationId: conv.id,
                title: conv.peer.displayName,
                body: previewText(msg)
            )
        }
    }

    private func previewText(_ last: LastMessageDTO) -> String {
        if last.kind == "voice" { return "Голосовое сообщение" }
        if last.kind == "video_note" { return "Видеосообщение" }
        if last.kind == "file" { return "📎 \(last.fileName ?? "Файл")" }
        let body = last.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "Новое сообщение" : body
    }

    private func refreshPresence(for ids: [Int]) async {
        do {
            let batch = try await APIClient.shared.presenceBatch(userIds: ids)
            await MainActor.run {
                for (id, st) in batch {
                    presence[id] = st
                }
            }
        } catch {
            /* ignore presence errors */
        }
    }

    private func presenceSuffix(for userId: Int) -> String {
        guard let p = presence[userId] else { return "" }
        if p.online { return " · в сети" }
        guard let seen = p.lastSeenAt, !seen.isEmpty else { return "" }
        return " · был(а) \(compactSeen(seen))"
    }

    private func compactSeen(_ raw: String) -> String {
        let normalized = raw.contains("T") ? raw : raw.replacingOccurrences(of: " ", with: "T")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date =
            parser.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
            ?? DateFormatter.sqlite.date(from: raw)
        guard let d = date else { return raw }
        let now = Date()
        let sec = Int(now.timeIntervalSince(d))
        if sec < 60 { return "только что" }
        if sec < 3600 { return "\(sec / 60) мин назад" }
        if Calendar.current.isDateInToday(d) {
            return "сегодня в \(DateFormatter.hm.string(from: d))"
        }
        return DateFormatter.dmhm.string(from: d)
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                let users = try await APIClient.shared.searchUsers(query: q)
                if !Task.isCancelled {
                    await MainActor.run {
                        searchResults = users
                    }
                    await refreshPresence(for: users.map(\.id))
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        searchResults = []
                    }
                }
            }
        }
    }

    private func openDirect(with user: UserDTO) async {
        do {
            let conv = try await APIClient.shared.createDirectConversation(userId: user.id)
            searchText = ""
            searchResults = []
            await load()
            path.append(conv.id)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не удалось открыть чат"
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    private var c: TelegramPalette { theme.palette }
    @State private var tab: SettingsTab = .general
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordBusy = false
    @State private var passwordError: String?
    @State private var passwordSuccess: String?
    @State private var sessions: [AuthSessionDTO] = []
    @State private var sessionsBusy = false
    @State private var sessionsError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел", selection: $tab) {
                    Text("Общие").tag(SettingsTab.general)
                    Text("Пароль").tag(SettingsTab.password)
                    Text("Сеансы").tag(SettingsTab.sessions)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Form {
                    switch tab {
                    case .general:
                        Section {
                            Text(session.user?.displayName ?? "")
                                .font(.headline)
                                .foregroundStyle(c.text)
                            Text("@\(session.user?.username ?? "")")
                                .font(.caption)
                                .foregroundStyle(c.textSecondary)
                        }
                        Section("Тема оформления") {
                            Picker("Тема", selection: Binding(
                                get: { theme.isDark },
                                set: { $0 ? theme.setDark() : theme.setLight() }
                            )) {
                                Text("Светлая").tag(false)
                                Text("Тёмная").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        Section {
                            Button("Выйти", role: .destructive) {
                                session.logout()
                                dismiss()
                            }
                        }
                    case .password:
                        Section("Смена пароля") {
                            SecureField("Старый пароль", text: $oldPassword)
                            SecureField("Новый пароль", text: $newPassword)
                            SecureField("Подтвердите новый пароль", text: $confirmPassword)

                            if let passwordError {
                                Text(passwordError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            if let passwordSuccess {
                                Text(passwordSuccess)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }

                            Button(passwordBusy ? "Сохранение..." : "Сменить пароль") {
                                Task { await changePassword() }
                            }
                            .disabled(passwordBusy)
                        }
                    case .sessions:
                        Section {
                            Button(sessionsBusy ? "Обновление..." : "Обновить список") {
                                Task { await loadSessions() }
                            }
                            .disabled(sessionsBusy)
                            Button("Завершить все кроме текущего", role: .destructive) {
                                Task { await revokeOtherSessions() }
                            }
                            .disabled(sessionsBusy)
                        }
                        if let sessionsError {
                            Section {
                                Text(sessionsError)
                                    .foregroundStyle(.red)
                            }
                        }
                        Section("Активные сеансы") {
                            if sessions.isEmpty {
                                Text("Активных сеансов нет")
                                    .foregroundStyle(c.textSecondary)
                            } else {
                                ForEach(sessions) { s in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(clientTitle(s.clientType))
                                                .font(.subheadline.weight(.semibold))
                                            if s.current {
                                                Text("Текущий")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(c.blue.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(s.device)
                                            .font(.caption)
                                            .foregroundStyle(c.textSecondary)
                                            .lineLimit(2)
                                        Text("Вход: \(s.createdAt)")
                                            .font(.caption2)
                                            .foregroundStyle(c.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.chatBg)
            .preferredColorScheme(theme.isDark ? .dark : .light)
            .navigationTitle("Настройки")
            .toolbarBackground(c.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .tint(c.blue)
            .task(id: tab) {
                if tab == .sessions {
                    await loadSessions()
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func clientTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "ios": return "iOS"
        case "android": return "Android"
        default: return "Web"
        }
    }

    private func changePassword() async {
        passwordError = nil
        passwordSuccess = nil
        let oldValue = oldPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmValue = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !oldValue.isEmpty else {
            passwordError = "Введите старый пароль"
            return
        }
        guard newValue.count >= 6 else {
            passwordError = "Новый пароль не короче 6 символов"
            return
        }
        guard newValue == confirmValue else {
            passwordError = "Подтверждение не совпадает"
            return
        }

        passwordBusy = true
        defer { passwordBusy = false }
        do {
            try await APIClient.shared.changePassword(oldPassword: oldValue, newPassword: newValue)
            passwordSuccess = "Пароль изменён. Войдите снова"
            session.logout()
            dismiss()
        } catch {
            passwordError = (error as? LocalizedError)?.errorDescription ?? "Не удалось сменить пароль"
        }
    }

    private func loadSessions() async {
        sessionsBusy = true
        defer { sessionsBusy = false }
        sessionsError = nil
        do {
            sessions = try await APIClient.shared.sessions()
        } catch {
            sessionsError = (error as? LocalizedError)?.errorDescription ?? "Не удалось загрузить сеансы"
        }
    }

    private func revokeOtherSessions() async {
        sessionsBusy = true
        defer { sessionsBusy = false }
        sessionsError = nil
        do {
            try await APIClient.shared.revokeOtherSessions()
            sessions = try await APIClient.shared.sessions()
        } catch {
            sessionsError = (error as? LocalizedError)?.errorDescription ?? "Не удалось завершить другие сеансы"
        }
    }
}

private enum SettingsTab: Hashable {
    case general
    case password
    case sessions
}

private extension DateFormatter {
    static let sqlite: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dmhm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM HH:mm"
        return f
    }()
}
