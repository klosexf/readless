//
//  readlessApp.swift
//  readless
//
//  Created by 陈晓峰 on 2026/7/31.
//

import SwiftUI

@main
struct readlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
