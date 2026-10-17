//
//  MobileTransfer.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/23.
//

import SwiftUI

struct MobileTransfer: SwiftUI.App {
    @State var vm = ViewModel.shared

    @State var progress = false
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { closeOtherWindows() }
                .sheet(isPresented: $progress) {
                    ProgressView()
                        .interactiveDismissDisabled()
                        .frame(width: 333, height: 222)
                }
                .frame(
                    minWidth: 666, idealWidth: 666, maxWidth: .infinity,
                    minHeight: 444, idealHeight: 444, maxHeight: .infinity,
                    alignment: .center
                )
                .environment(vm)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { commands }
    }

    func closeOtherWindows() {
        let windows = NSApp.windows
        for window in windows {
            if window != NSApp.keyWindow, NSApp.windows.count > 1 {
                window.close()
            } else {
                window.center()
            }
        }
    }
}
