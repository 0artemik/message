//
//  ContentView.swift
//  messangerapp
//
//  Created by Vasya Pupkin on 08.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isRestoringSession {
                ProgressView()
                    .tint(theme.palette.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.palette.chatBg.ignoresSafeArea())
            } else if session.token == nil {
                AuthView()
            } else {
                MainView()
            }
        }
        .environmentObject(session)
        .environmentObject(theme)
        .environment(\.telegramPalette, theme.palette)
        .onAppear {
            session.handleScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { phase in
            session.handleScenePhase(phase)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
        .environmentObject(ThemeStore())
}
