import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore

    @State private var isRegister = false
    @State private var username = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var busy = false
    @State private var showServerSheet = false
    @State private var backendHost = APIConfig.backendHost
    @State private var backendPort = APIConfig.backendPort

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [c.authGradientTop, c.authGradientMid, c.authGradientBot],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Button {
                            backendHost = APIConfig.backendHost
                            backendPort = APIConfig.backendPort
                            showServerSheet = true
                        } label: {
                            Image(systemName: "server.rack")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 28)
                    }
                    .padding(.top, 20)

                    Text("✈")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))

                    Text("Message")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Picker("", selection: $isRegister) {
                        Text("Вход").tag(false)
                        Text("Регистрация").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 14) {
                        if isRegister {
                            fieldLabel("Логин")
                            TextField("", text: $username)
                                .authField()
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            fieldLabel("Email")
                            TextField("", text: $email)
                                .authField()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()

                            fieldLabel("Имя")
                            TextField("Как вас видят другие", text: $displayName)
                                .authField()
                        } else {
                            fieldLabel("Логин")
                            TextField("", text: $username)
                                .authField()
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        fieldLabel("Пароль")
                        SecureField("", text: $password)
                            .authField()

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(Color.red.opacity(0.95))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(busy ? "…" : (isRegister ? "Создать аккаунт" : "Войти"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(c.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(busy || !canSubmit)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(c.bg)
                            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showServerSheet) {
            NavigationStack {
                Form {
                    Section("Локальный backend") {
                        TextField("IP Mac", text: $backendHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Порт", text: $backendPort)
                            .keyboardType(.numberPad)
                        Text("Текущий адрес: \(APIConfig.baseURL.absoluteString)")
                            .font(.footnote)
                            .foregroundStyle(c.textSecondary)
                    }

                    Section {
                        Button("Сохранить") {
                            APIConfig.updateBackend(host: backendHost, port: backendPort)
                            errorText = nil
                            showServerSheet = false
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .background(c.chatBg)
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .navigationTitle("Сервер")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { showServerSheet = false }
                    }
                }
            }
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(c.textSecondary)
    }

    private var canSubmit: Bool {
        if isRegister {
            return username.count >= 3 && email.contains("@") && password.count >= 6
        }
        return !username.isEmpty && !password.isEmpty
    }

    private func submit() async {
        errorText = nil
        busy = true
        defer { busy = false }
        do {
            if isRegister {
                let dn = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                try await session.register(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    password: password,
                    displayName: dn.isEmpty ? username : dn
                )
            } else {
                try await session.login(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Ошибка"
        }
    }
}

private extension View {
    func authField() -> some View {
        padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1)
            )
    }
}
