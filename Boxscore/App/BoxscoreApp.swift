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
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(router)
                .task { await authService.start() }
                .onOpenURL { router.handle($0) }
        }
    }
}
