//
//  FramedApp.swift
//  Framed
//
//  Created by Vamsi Yerramilli on 27/02/26.
//

import AppKit
import SwiftUI

@main
struct FramedApp: App {
    init() {
        // Initialise the database and apply migrations on first launch.
        // Using the shared singleton here forces initialisation before any views render.
        _ = DatabaseManager.shared
        print("[App] Framed started")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Start DiskArbitration monitoring from the main run loop.
                    // .task runs on the main actor, which is where the DA session must be scheduled.
                    await IngestManager.shared.startMonitoring()
                }
        }
        .commands {
            TestIngestCommands()
        }
    }
}

// MARK: - Development testing command

/// Adds a "File → Test Ingest from Folder…" menu item for verifying the ingest pipeline
/// without a physical SD card. Covers AC-1.3 through AC-1.11.
/// AC-1.2 (DiskArbitration hardware detection) requires a real SD card.
private struct TestIngestCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Test Ingest from Folder…") {
                let panel = NSOpenPanel()
                panel.title = "Choose a folder containing image files"
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Ingest"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                Task {
                    await IngestManager.shared.triggerTestIngest(from: url)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}
