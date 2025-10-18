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
        let storeURL = URL.documentsDirectory.appending(path: "dailyapp_versioned.store")
        let config = ModelConfiguration(url: storeURL)
        
        do {
            let schema = Schema(versionedSchema: TaskSchemaV2.self)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Container creation failed: \(error)")
            
            // Clean up and try again
            try? FileManager.default.removeItem(at: storeURL)
            
            do {
                let schema = Schema(versionedSchema: TaskSchemaV2.self)
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
