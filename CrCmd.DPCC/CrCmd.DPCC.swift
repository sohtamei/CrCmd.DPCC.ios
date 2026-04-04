import SwiftUI

@main
struct CrCmd_DPCC: App {
    @AppStorage("eulaAccepted") private var eulaAccepted = false

    var body: some Scene {
        WindowGroup {
            if eulaAccepted {
                ContentView()
            } else {
                EulaView()
            }
        }
    }
}
