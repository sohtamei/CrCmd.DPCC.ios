import SwiftUI

@main
struct CrCmd_ios_sample_dp_ccApp: App {
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
