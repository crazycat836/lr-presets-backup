import SwiftUI

@main
struct LRPresetsBackupApp: App {
    var body: some Scene {
        WindowGroup("Mac 備份") {
            ContentView()
        }
        .defaultSize(width: 640, height: 900)
        .windowResizability(.contentMinSize)
    }
}
