//
//  VisorApp.swift
//  Visor
//
//  Created by Danniel Yu on 7/3/R8.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct VisorApp: App {
    @State private var environment = AppEnvironment()
    @State private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // 申请后台执行时间（最多 30 秒）
                    bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "VisorStreaming") {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                        bgTaskID = .invalid
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                        bgTaskID = .invalid
                    }
                }
        }
        .modelContainer(environment.modelContainer)
    }
}
