import SwiftUI

@main
struct WeMendAIApp: App {
    @StateObject private var auth = Auth()

    var body: some Scene {
        WindowGroup {
            // Three gates, in order. A signed-out user can make no request at all —
            // VoiceClient has no bearer to send. An incomplete user cannot reach the
            // call screen, because the mediator needs a name and pronouns to speak
            // about them correctly to their partner.
            //
            // Wrapped in a Group so `.task` and `.environmentObject` have a single
            // view to attach to rather than being repeated on each branch.
            Group {
                if !auth.isSignedIn {
                    SignInView()
                } else if !auth.onboardingComplete {
                    OnboardingView { auth.markOnboardingComplete() }
                } else {
                    ContentView()
                }
            }
            .environmentObject(auth)
            // Onboarding state lives server-side, so a reinstall holding a valid
            // token must reconcile rather than repeat onboarding.
            .task { await auth.refresh() }
        }
    }
}
