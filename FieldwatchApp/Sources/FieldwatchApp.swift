import SwiftUI

@main
struct FieldwatchApp: App {
    @StateObject private var store = FieldwatchStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}
