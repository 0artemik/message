import SwiftUI

@main
struct MessageAppApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore()
    @StateObject private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }
}
