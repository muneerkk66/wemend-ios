import SwiftUI

@main
struct WeMendAIApp: App {
    @StateObject private var auth = Auth()

    var body: some Scene {
        WindowGroup {
            // Signed-out users only ever see SignInView; nothing else in the app can
            // make a request, because VoiceClient has no bearer to send.
            if auth.isSignedIn {
                ContentView().environmentObject(auth)
            } else {
                SignInView().environmentObject(auth)
            }
        }
    }
}
