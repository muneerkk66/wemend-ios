import SwiftUI

/// Tapped onboarding: disclosure → name → pronouns → relationship → pacing.
///
/// Built before the voice intake deliberately. This is the fallback for every
/// extraction failure in the voice call, and the permanent edit surface in Settings.
/// The voice call fills this form; it does not replace it.
struct OnboardingView: View {
    @EnvironmentObject private var auth: Auth
    var onFinished: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var pronouns: String?
    @State private var status: String?
    @State private var years = 3
    @State private var pacing: String?
    @State private var busy = false
    @State private var error: String?

    private let steps = 5

    var body: some View {
        ZStack {
            AuroraBackground(tint: Brand.accent(.idle))

            VStack(spacing: 0) {
                progress
                    .padding(.top, 10)

                TabView(selection: $step) {
                    disclosure.tag(0)
                    nameStep.tag(1)
                    pronounStep.tag(2)
                    statusStep.tag(3)
                    pacingStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)

                footer
            }
            .padding(.horizontal, 26)

            if let error {
                VStack {
                    Spacer()
                    Text(error).font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.85)))
                        .padding(.bottom, 100)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { name = auth.displayName ?? "" }
    }

    // MARK: chrome

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Brand.teal : .white.opacity(0.14))
                    .frame(height: 3)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task { await advance() }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.black) }
                    Text(step == steps - 1 ? "Finish" : "Continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canAdvance ? Color.white : Color.white.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(canAdvance ? .black : .white.opacity(0.5))
            }
            .disabled(!canAdvance || busy)

            // Everything except the disclosure is skippable: an enum that includes
            // "prefer not to say" is only honest if the UI lets you use it.
            if step > 0 {
                Button("Prefer not to say") { Task { await advance(skip: true) } }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, 28)
        .padding(.top, 14)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return pronouns != nil
        case 3: return status != nil
        case 4: return pacing != nil
        default: return false
        }
    }

    // MARK: steps

    private var disclosure: some View {
        step_(
            title: "Before we begin",
            // The most important 20 seconds in the app: said plainly, up front,
            // rather than buried in a policy nobody opens.
            body: """
            WeMendAI is software, not a person — and not a therapist.

            I will never repeat anything to your partner unless you approve the exact \
            words first.

            Either of you can stop at any time.
            """
        )
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            head("What should I call you?",
                 "I'll use this when I speak about you to your partner.")
            TextField("Your name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Brand.teal.opacity(0.5)).frame(height: 1)
                }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Spacer()
        }
        .padding(.top, 34)
    }

    private var pronounStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Pronouns, not gender. The reason is concrete and worth stating, so the
            // question reads as purposeful rather than nosy.
            head("How should I refer to you?",
                 "I'll be speaking about you to your partner — \"he said\", \"she mentioned\" — so I want to get this right.")
            chips(["he_him": "He / him", "she_her": "She / her",
                   "they_them": "They / them"], selection: $pronouns)
            Spacer()
        }
        .padding(.top, 34)
    }

    private var statusStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            head("Where are you two right now?", nil)
            chips(["married": "Married", "partners": "Partners",
                   "dating": "Dating", "separated": "Separated"], selection: $status)
            if status != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Together about \(years) \(years == 1 ? "year" : "years")")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                    Slider(value: .init(get: { Double(years) },
                                        set: { years = Int($0) }), in: 0...40, step: 1)
                        .tint(Brand.teal)
                }
                .padding(.top, 10)
                .transition(.opacity)
            }
            Spacer()
        }
        .padding(.top, 34)
    }

    private var pacingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // This replaces the cycle question: it captures what that data would have
            // been used for — how long to hold a cooling-off gap, how directly to
            // push — without touching health data, and everyone gets asked.
            head("When something's difficult…",
                 "This helps me judge how much space to leave between you two.")
            chips(["needs_time": "I need a bit of time before I can talk",
                   "right_away": "I'd rather deal with it right away",
                   "depends": "It depends"], selection: $pacing)
            Spacer()
        }
        .padding(.top, 34)
    }

    // MARK: building blocks

    private func step_(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
            Text(body)
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.75))
                .lineSpacing(6)
            Spacer()
        }
        .padding(.top, 40)
    }

    private func head(_ title: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 25, weight: .bold)).foregroundStyle(.white)
            if let sub {
                Text(sub).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(3)
            }
        }
    }

    private func chips(_ options: [String: String],
                       selection: Binding<String?>) -> some View {
        VStack(spacing: 9) {
            ForEach(options.sorted(by: { $0.value.count < $1.value.count }), id: \.key) { key, label in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = key }
                } label: {
                    HStack {
                        Text(label).font(.system(size: 15))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selection.wrappedValue == key {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundStyle(selection.wrappedValue == key ? .white : .white.opacity(0.72))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(selection.wrappedValue == key
                                  ? Brand.teal.opacity(0.22) : Brand.navyLift.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(selection.wrappedValue == key
                                                  ? Brand.teal.opacity(0.7) : .clear,
                                                  lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: actions

    private func advance(skip: Bool = false) async {
        error = nil
        guard let url = URL(string: Config.defaultServerURL), let token = auth.token else { return }
        let client = ProfileClient(baseURL: url, bearer: token)
        busy = true
        defer { busy = false }

        do {
            switch step {
            case 0:
                // Record the disclosure before anything else: the server refuses to
                // mark onboarding complete without it.
                try await client.setConsent(kind: "ai_disclosure", granted: true)
            case 1:
                try await client.patch(["display_name": name.trimmingCharacters(in: .whitespaces)])
            case 2:
                try await client.patch(["pronouns": skip ? "not_stated" : (pronouns ?? "not_stated")])
            case 3:
                var body: [String: Any] = ["relationship_status": skip ? "not_stated" : (status ?? "not_stated")]
                if !skip { body["together_months"] = years * 12 }
                try await client.patch(body)
            case 4:
                try await client.patch(["pacing_preference": skip ? "not_stated" : (pacing ?? "not_stated"),
                                        "complete_onboarding": true])
                onFinished()
                return
            default: break
            }
            withAnimation { step += 1 }
        } catch {
            if case ClientError.signedOut = error { auth.clear(); return }
            self.error = error.localizedDescription
        }
    }
}
