//
//  DailyAppApp.swift
//  DailyApp
//
//  Created by Ashwin, Antony on 12/10/25.
//

import SwiftUI
import SwiftData

@main
struct DailyAppApp: App {
    var sharedModelContainer: ModelContainer = {
        // Create configuration with a custom store filename to avoid previous incompatible store
        let storeURL = URL.documentsDirectory.appending(path: "dailyapp.store")
        let config = ModelConfiguration(url: storeURL)

        // Clean up legacy default.store if present (one-time dev convenience)
        do {
            let legacy = URL.documentsDirectory.appending(path: "default.store")
            if FileManager.default.fileExists(atPath: legacy.path()) {
                try FileManager.default.removeItem(at: legacy)
            }
        } catch {
            print("Store cleanup warning: \(error)")
        }
        do {
            return try ModelContainer(for: TaskEntry.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
