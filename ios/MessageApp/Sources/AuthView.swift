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
                    Text("✈")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))
                        .padding(.top, 24)

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
