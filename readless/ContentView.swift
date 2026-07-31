//
//  ContentView.swift
//  readless
//
//  Created by 陈晓峰 on 2026/7/31.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state: ReadlessAppState

    init() {
        _state = StateObject(
            wrappedValue: PreviewFixtures.playingState()
        )
    }

    var body: some View {
        MainWindowView(
            state: state,
            actions: PreviewFixtures.actions
        )
        .frame(width: 620, height: 520)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDisplayName("Readless 主窗口")
    }
}
