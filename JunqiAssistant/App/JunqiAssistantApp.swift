import SwiftUI

@main
struct JunqiAssistantApp: App {
    @StateObject private var model = AssistantViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
