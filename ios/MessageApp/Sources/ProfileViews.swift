import PhotosUI
import SwiftUI

private func profileInitials(_ name: String) -> String {
    let parts = name.split(separator: " ").map(String.init)
    let first = parts.first?.first.map(String.init) ?? "?"
    let second = parts.dropFirst().first?.first.map(String.init) ?? ""
    return (first + second).uppercased()
}

struct ProfileHeroCard: View {
    let user: UserDTO
    let subtitle: String
    let avatarBusy: Bool
    let onAvatarPicked: ((PhotosPickerItem?) -> Void)?
    let onEditName: (() -> Void)?

    @EnvironmentObject var theme: ThemeStore
    @State private var showFullscreenAvatar = false
    @State private var avatarItem: PhotosPickerItem?

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    showFullscreenAvatar = true
                } label: {
                    AvatarCircleView(user: user, size: 110)
                        .environmentObject(theme)
                }
                .buttonStyle(.plain)

                if let onAvatarPicked {
                    PhotosPicker(
                        selection: $avatarItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        profileEditBadge(systemName: avatarBusy ? "arrow.triangle.2.circlepath" : "pencil")
                    }
                    .buttonStyle(.plain)
                    .disabled(avatarBusy)
                    .onChange(of: avatarItem) { value in
                        onAvatarPicked(value)
                    }
                }
            }

            Text("@\(user.username)")
                .font(.subheadline)
                .foregroundStyle(c.textSecondary)

            HStack(spacing: 8) {
                Text(user.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(c.text)

                if let onEditName {
                    Button {
                        onEditName()
                    } label: {
                        profileEditBadge(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)


            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(c.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(c.header)
        )
        .fullScreenCover(isPresented: $showFullscreenAvatar) {
            FullScreenAvatarView(user: user)
                .environmentObject(theme)
        }
    }

    private func profileEditBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(c.text)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(c.border.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(theme.isDark ? 0.24 : 0.12), radius: 8, y: 3)
    }
}

extension ProfileHeroCard {
    init(
        user: UserDTO,
        subtitle: String,
        avatarBusy: Bool = false,
        onAvatarPicked: ((PhotosPickerItem?) -> Void)? = nil,
        onEditName: (() -> Void)? = nil
    ) {
        self.user = user
        self.subtitle = subtitle
        self.avatarBusy = avatarBusy
        self.onAvatarPicked = onAvatarPicked
        self.onEditName = onEditName
    }
}

struct AvatarCircleView: View {
    let user: UserDTO
    let size: CGFloat

    @EnvironmentObject var theme: ThemeStore
    @State private var image: UIImage?

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [c.blue.opacity(0.9), c.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: c.blue.opacity(0.25), radius: 16, y: 8)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(profileInitials(user.displayName))
                    .font(.system(size: size * 0.31, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .task(id: user.avatarUrl) {
            await loadAvatar()
        }
    }

    private func loadAvatar() async {
        guard let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty else {
            image = nil
            return
        }
        do {
            let data = try await APIClient.shared.downloadAvatar(path: avatarUrl)
            if let ui = UIImage(data: data) {
                image = ui
            } else {
                image = nil
            }
        } catch {
            image = nil
        }
    }
}

struct UserProfileSheet: View {
    let user: UserDTO
    let subtitle: String

    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProfileHeroCard(user: user, subtitle: subtitle)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Имя")
                                .font(.caption)
                                .foregroundStyle(c.textSecondary)
                            Text(user.displayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(c.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Логин")
                                .font(.caption)
                                .foregroundStyle(c.textSecondary)
                            Text("@\(user.username)")
                                .font(.body)
                                .foregroundStyle(c.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(c.header)
                    )
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(c.chatBg)
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

struct FullScreenAvatarView: View {
    let user: UserDTO

    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                AvatarCircleView(user: user, size: 220)
                    .environmentObject(theme)
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Закрыть") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.45))
                        .clipShape(Capsule())
                }
                .padding()

                Spacer()
            }
        }
        .task(id: user.avatarUrl) {
            await loadAvatar()
        }
        .onTapGesture {
            dismiss()
        }
    }

    private func loadAvatar() async {
        guard let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty else {
            image = nil
            return
        }
        do {
            let data = try await APIClient.shared.downloadAvatar(path: avatarUrl)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}

struct AvatarPickerButton: View {
    let busy: Bool
    let onPicked: (PhotosPickerItem?) -> Void

    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(
            selection: $item,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Text(busy ? "Загрузка фото..." : "Изменить фото")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .disabled(busy)
        .onChange(of: item) { value in
            onPicked(value)
        }
    }
}
