//
//  BoxscoreApp.swift
//  Boxscore
//
//  Created by Cooper Xu on 2026/7/15.
//

import SwiftUI

@main
struct BoxscoreApp: App {
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .task { await authService.start() }
        }
    }
}
