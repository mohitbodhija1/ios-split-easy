//
//  SplitMateApp.swift
//  SplitMate
//
//  Created by Mohit Bodhija on 18/04/26.
//

import SwiftUI

@main
struct SplitMateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(sessionStore)
        }
    }
}
