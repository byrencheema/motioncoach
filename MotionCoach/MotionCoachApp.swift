import SwiftUI

@main
struct MotionCoachApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .preferredColorScheme(.light)
                .tint(Court.teal)
        }
    }
}
