import MapKit
import Playgrounds
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Map()
    }
}

#Preview {
    ContentView()
}
