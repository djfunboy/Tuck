import SwiftUI
import AppKit

private enum Candy {
    static let ink = Color(red: 0.19, green: 0.10, blue: 0.32)
    static let pink = Color(red: 0.94, green: 0.12, blue: 0.43)
    static let violet = Color(red: 0.36, green: 0.17, blue: 0.76)
    static let mint = Color(red: 0.02, green: 0.51, blue: 0.37)
    static let paper = Color(red: 1, green: 0.985, blue: 0.95)
    static let secondary = Color(red: 0.40, green: 0.35, blue: 0.48)
    static let rainbow: [Color] = [pink, Color(red: 1, green: 0.43, blue: 0.12), Color(red: 1, green: 0.77, blue: 0.08), Color(red: 0.08, green: 0.69, blue: 0.49), Color(red: 0.12, green: 0.52, blue: 0.94), violet]
}

struct TuckView: View {
    @ObservedObject var model: PromptModel
    let isMCP: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSetup = false
    @State private var showManual = false
    @State private var copied = false
    @State private var setupError: String?
    @State private var float = false

    var body: some View {
        if isMCP {
            MCPPromptView(model: model).id(model.presentationID)
        } else {
            setupBody
        }
    }

    private var setupBody: some View {
        ZStack {
            Candy.paper
            decorations.accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 22) {
                    if model.request != nil {
                        HStack(spacing: 12) {
                            Image(systemName: "rainbow").symbolRenderingMode(.multicolor).font(.system(size: 40))
                            Text("Tuck").font(.system(size: 31, weight: .heavy, design: .rounded))
                        }.padding(.top, 12)
                    } else { hero }
                    if let request = model.request {
                        SecretEntryView(model: model, request: request, showsMismatch: .constant(false))
                    } else if let outcome = model.lastOutcome {
                        outcomeView(outcome)
                    } else if showSetup {
                        setup
                    } else {
                        welcome
                    }
                    Label("Saved in Apple Keychain. Kept off the chat.", systemImage: "lock.shield")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Candy.ink.opacity(0.7))
                    HStack(spacing: 18) {
                        Link("Support", destination: URL(string: "https://tuckaway.dev/support/")!)
                        Link("Privacy", destination: URL(string: "https://tuckaway.dev/privacy/")!)
                    }.font(.caption).tint(Candy.violet)
                }.padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 24)
            }.scrollIndicators(.never)
        }
        .foregroundStyle(Candy.ink)
        .frame(width: 520, height: 640)
        .preferredColorScheme(.light)
    }

    // MARK: Personality
    private var decorations: some View {
        ZStack {
            Text("✦").font(.system(size: 25)).foregroundStyle(Candy.pink).rotationEffect(.degrees(12)).offset(x: 190, y: -180)
            Text("✧").font(.system(size: 30)).foregroundStyle(Candy.violet).offset(x: -198, y: -110)
            Text("✦").font(.system(size: 15)).foregroundStyle(Candy.mint).offset(x: 190, y: 230)
        }
    }

    private var hero: some View {
        VStack(spacing: 4) {
            ZStack {
                RainbowArch().frame(width: 172, height: 86).offset(y: -15)
                HStack(spacing: -14) {
                    Circle().frame(width: 52, height: 52)
                    Circle().frame(width: 75, height: 75).offset(y: -9)
                    Circle().frame(width: 58, height: 58)
                }.foregroundStyle(.white).offset(y: 45)
                SmilingKey().frame(width: 96, height: 118).rotationEffect(.degrees(-23)).offset(y: float ? 20 : 25)
            }.frame(height: 169).accessibilityHidden(true)
            Text("Tuck").font(.system(size: 39, weight: .heavy, design: .rounded)).tracking(-1.2)
            Text("Your agent asks. You tuck it away.")
                .font(.system(size: 15, weight: .medium, design: .rounded)).padding(.top, 3)
        }.onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { float = true }
            }
        }
    }

    // MARK: Connection is the primary experience
    private var welcome: some View {
        VStack(spacing: 19) {
            Text("Less Terminal. More ✨")
                .font(.system(size: 23, weight: .bold, design: .rounded))
            Text("Connect your agent once. When it needs a key,\nwe’ll take it from there with soft hands.")
                .font(.system(size: 14)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 17) {
                step("bubble.left.and.bubble.right.fill", "Agent asks", .purple)
                Image(systemName: "arrow.right").foregroundStyle(Candy.violet.opacity(0.4))
                step("key.fill", "You tuck", Candy.pink)
                Image(systemName: "arrow.right").foregroundStyle(Candy.violet.opacity(0.4))
                step("lock.shield.fill", "All tucked in", Candy.mint)
            }.padding(.vertical, 6)
            Button { showSetup = true } label: {
                HStack { Text("Connect your agent"); Image(systemName: "sparkles") }.frame(maxWidth: .infinity)
            }.buttonStyle(CandyButton()).accessibilityIdentifier("connectButton")
        }.padding(24).background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 27))
    }

    private func step(_ symbol: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .semibold, design: .rounded))
        }.frame(minWidth: 65)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("One tiny introduction.").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button { showSetup = false } label: { Image(systemName: "arrow.left") }.buttonStyle(.plain).accessibilityLabel("Back")
            }
            Text("Paste these instructions into your local coding agent. It will connect Tuck and install a small skill so it knows when to open the popup.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Upgrading from Keydrop? Copy these instructions to your agent again.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Button {
                do {
                    let instructions = try Self.setupRequest()
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(instructions, forType: .string)
                    setupError = copied ? nil : String(localized: "Couldn’t copy. Please try again.")
                } catch {
                    copied = false
                    setupError = String(localized: "The bundled setup skill couldn’t be loaded. Please reinstall Tuck.")
                }
            } label: {
                Label(copied ? "Copied! Paste into your agent" : "Copy instructions for my agent", systemImage: copied ? "checkmark" : "sparkles").frame(maxWidth: .infinity)
            }.buttonStyle(CandyButton()).accessibilityIdentifier("copySetupButton")
            if let setupError {
                Text(setupError).font(.caption).foregroundStyle(.red).accessibilityIdentifier("setupError")
            }
            Text("Then ask: “Save a key with Tuck.”")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Candy.violet)
            DisclosureGroup("Set up manually instead", isExpanded: $showManual) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("For clients that don’t edit their own settings, add this server in the client’s MCP configuration, then restart the client. Keep Tuck at this app location.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    ScrollView([.horizontal, .vertical]) {
                        Text(Self.configuration).font(.system(size: 11, design: .monospaced)).fixedSize().textSelection(.enabled).padding(10)
                    }.scrollIndicators(.never).frame(height: 145).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    Button("Copy MCP configuration") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.configuration, forType: .string)
                    }.accessibilityIdentifier("copyConfigButton")
                }.padding(.top, 8)
            }.font(.caption).tint(Candy.violet)
        }.padding(24).background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 27))
    }

    // MARK: Completion
    private func outcomeView(_ outcome: SaveOutcome) -> some View {
        VStack(spacing: 15) {
            Text(outcome == .saved ? "✦  🌈  ✦" : "☁️").font(.system(size: 32)).accessibilityHidden(true)
            Text(outcome == .saved ? "You’re golden." : (outcome == .timedOut ? "This request expired." : "No drop this time."))
                .font(.system(size: 26, weight: .heavy, design: .rounded)).accessibilityIdentifier("outcomeTitle")
            Text(outcome == .saved ? "Your key is tucked into Apple Keychain.\nYour agent got the good news—not the key." : "Nothing was saved or sent to your agent.")
                .multilineTextAlignment(.center).font(.callout).fixedSize(horizontal: false, vertical: true)
            if outcome == .saved {
                Text("macOS may ask permission when another tool first uses it.")
                    .font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button("Lovely. Done.") {
                if isMCP { NSApplication.shared.keyWindow?.close() }
                else { model.resetOutcome() }
            }.buttonStyle(CandyButton())
        }.frame(maxWidth: .infinity).padding(24).background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 27))
    }

    // MARK: Agent setup
    /// Hosted setup steps, so wording changes ship with the website instead of an App Store release.
    static let setupURL = "https://tuckaway.dev/setup/SETUP.md"

    static func setupRequest(bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: "SKILL", withExtension: "md") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let skill = try String(contentsOf: url, encoding: .utf8)
        let executable = "/Applications/Tuck.app/Contents/MacOS/Tuck"
        return """
        Set up Tuck for this local coding agent.

        The current setup steps are at \(setupURL). Fetch that page and follow it. If you cannot fetch it, follow these steps instead:

        1. If an MCP server named keydrop is configured, or any MCP entry points at /Applications/Keydrop.app, remove that old entry. Register a stdio MCP server named tuck that runs \(executable) with the single argument --mcp. Register it at this client's user or global level so it works in every project and folder, not only the current one, using the client's documented command or configuration file. Keep one tuck entry. Preserve unrelated MCP settings. Never put credentials in configuration.
        2. Install the tuck skill in this client's supported personal skill directory, with automatic discovery enabled. Fetch the canonical copy from https://tuckaway.dev/skill/SKILL.md; if you cannot fetch it, use the SKILL.md below. Use the client's documented location. Preserve unrelated skills; if a tuck skill already exists, compare it and preserve user customizations. If this client does not support skills, explain that limitation and retain the MCP connection; do not invent an install location or edit unrelated global instructions.
        3. Verify that tuck is registered at the user or global level, that server discovery includes save_credential, and that the skill file was installed. Tell me if the client needs a restart; most clients load a new MCP server only in a new session. Do not open a test prompt until I ask.

        SKILL.md:
        ```markdown
        \(skill)
        ```
        """
    }

    static var configuration: String {
        let path = "/Applications/Tuck.app/Contents/MacOS/Tuck"
        let object: [String: Any] = ["mcpServers": ["tuck": ["command": path, "args": ["--mcp"]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), let string = String(data: data, encoding: .utf8) else { return "Configuration unavailable." }
        return string
    }
}

private struct SmilingKey: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(Candy.violet).frame(width: 22, height: 76).offset(y: 23)
            RoundedRectangle(cornerRadius: 6).fill(Candy.violet).frame(width: 35, height: 16).offset(x: 14, y: 50)
            RoundedRectangle(cornerRadius: 5).fill(Candy.violet).frame(width: 29, height: 14).offset(x: 11, y: 29)
            Circle().fill(Candy.violet).frame(width: 77, height: 77).offset(y: -24)
            Circle().fill(Color(red: 1, green: 0.79, blue: 0.12)).frame(width: 57, height: 57).offset(y: -24)
            HStack(spacing: 17) {
                Capsule().frame(width: 5, height: 8)
                Capsule().frame(width: 5, height: 8)
            }.foregroundStyle(Candy.ink).offset(y: -29)
            HStack(spacing: 29) {
                Ellipse().frame(width: 9, height: 5)
                Ellipse().frame(width: 9, height: 5)
            }.foregroundStyle(.pink.opacity(0.65)).offset(y: -21)
            Path { p in
                p.move(to: CGPoint(x: 41, y: 44))
                p.addQuadCurve(to: CGPoint(x: 55, y: 44), control: CGPoint(x: 48, y: 53))
            }.stroke(Candy.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

private struct RainbowArch: View {
    var body: some View {
        GeometryReader { geometry in
            let band = geometry.size.width / 17
            ZStack(alignment: .top) {
                ForEach(Candy.rainbow.indices, id: \.self) { index in
                    Circle().strokeBorder(Candy.rainbow[index], lineWidth: band + 0.5)
                        .frame(width: geometry.size.width - CGFloat(index) * band * 2,
                               height: geometry.size.width - CGFloat(index) * band * 2)
                        .offset(y: CGFloat(index) * band)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct MCPPromptView: View {
    // MARK: Request presentation
    @ObservedObject var model: PromptModel
    @State private var destination: CredentialRequest?
    @State private var showsMismatch = false
    @State private var keyHops = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PromptModel) {
        self.model = model
        _destination = State(initialValue: model.request)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SmilingKey().frame(width: 96, height: 118)
                    .scaleEffect(0.39).rotationEffect(.degrees(-22))
                    .frame(width: 38, height: 46)
                    .offset(y: keyHops ? -6 : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tuck").font(.system(size: 24, weight: .heavy, design: .rounded)).tracking(-0.8)
                    Text("Straight to Apple Keychain.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Candy.secondary)
                }
                Spacer()
                ZStack(alignment: .bottomTrailing) {
                    RainbowArch().frame(width: 62, height: 31)
                    Image(systemName: "cloud.fill").font(.system(size: 20)).foregroundStyle(.white)
                        .offset(x: 5, y: 7)
                }.frame(width: 62, height: 46).accessibilityHidden(true)
            }
            if let destination {
                SecretEntryView(model: model, request: destination, showsMismatch: $showsMismatch)
            }
        }
        .padding(16)
        .frame(
            width: 340,
            height: (model.errorMessage == nil && !showsMismatch ? 260 : 350)
                + (destination?.providerLink == nil ? 0 : 6)
        )
        .background(Candy.paper)
        .clipped()
        .foregroundStyle(Candy.ink)
        .preferredColorScheme(.light)
        .onChange(of: model.lastOutcome == .saved) { _, saved in
            guard saved, !reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { keyHops = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) { keyHops = false }
            }
        }
    }
}

private struct SecretEntryView: View {
    // MARK: Entry state
    @ObservedObject var model: PromptModel
    let request: CredentialRequest
    @State private var secret = ""
    @State private var isSubmitting = false
    @State private var replaceRequested = false
    @State private var savedCount = 0
    @Binding var showsMismatch: Bool
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var saved: Bool { model.lastOutcome == .saved }
    // Advisory only. Computed from the field's current text; nothing here is stored or sent.
    private var recognition: KeyRecognition? { KeyRecognizer.recognize(secret) }
    private var whitespaceHint: String? { KeyRecognizer.whitespaceHint(secret) }
    private var mismatch: String? {
        guard let recognition else { return nil }
        return DestinationMismatch.check(recognition: recognition, service: request.service, account: request.account)
    }

    // MARK: Body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    destinationRow("Service", value: request.service, identifier: "requestService")
                    destinationRow("Account", value: request.account, identifier: "requestAccount")
                    if let providerLink = request.providerLink {
                        providerLinkRow(providerLink)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            SecureField("Password or token", text: $secret)
                .textFieldStyle(.plain).focused($focused)
                .font(.system(size: 13))
                .padding(.horizontal, 11).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(focused && !saved ? Candy.violet : Candy.ink.opacity(0.22), lineWidth: focused && !saved ? 2 : 1)
                }
                .accessibilityLabel("Password or token").accessibilityIdentifier("secretField")
                .disabled(saved || isSubmitting)
                .onSubmit {
                    if !model.requiresReplacement && !secret.isEmpty && !isSubmitting {
                        replaceRequested = false
                        isSubmitting = true
                    }
                }
            HStack(alignment: .top, spacing: 8) {
                if saved {
                    let confirmation: LocalizedStringKey = model.clipboardCleared
                        ? "Saved to Keychain · Clipboard cleared"
                        : "Saved in Apple Keychain · all \(savedCount) characters"
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Candy.mint)
                        .accessibilityLabel(confirmation)
                        .accessibilityIdentifier("saveConfirmation")
                } else if let recognition {
                    Label("Looks like \(KeyRecognizer.article(for: recognition.provider)) \(recognition.provider)", systemImage: "key.horizontal")
                        .font(.system(size: 10)).foregroundStyle(Candy.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keyRecognition")
                } else {
                    Text(request.providerLink == nil
                         ? "Clipboard clears after pasting. Clipboard history apps may keep earlier copies."
                         : "Clipboard clears after paste. History apps may retain copies.")
                        .font(.system(size: 10)).foregroundStyle(Candy.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !secret.isEmpty {
                    // Length only, shown natively; the count never leaves this window.
                    let count = "\(secret.count) \(secret.count == 1 ? "character" : "characters")"
                    Text(whitespaceHint.map { "\(count) · \($0)" } ?? count)
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Candy.secondary).fixedSize()
                        .accessibilityIdentifier("characterCount")
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(Color(red: 0.68, green: 0.09, blue: 0.23))
                    .accessibilityIdentifier("saveError").fixedSize(horizontal: false, vertical: true)
            } else if let mismatch, let recognition {
                Text("This looks like \(KeyRecognizer.article(for: recognition.provider)) \(recognition.provider), but the destination mentions \(KeyFormats.familyDisplayNames[mismatch] ?? mismatch).")
                    .font(.caption).foregroundStyle(Color(red: 0.68, green: 0.09, blue: 0.23))
                    .accessibilityIdentifier("destinationMismatch").fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { secret = ""; model.cancel() }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("cancelButton")
                    .buttonStyle(PromptButton(primary: false)).disabled(saved)
                Spacer()
                Button {
                    replaceRequested = model.requiresReplacement
                    isSubmitting = true
                } label: {
                    HStack(spacing: saved || isSubmitting ? 6 : 0) {
                        if isSubmitting { ProgressView().controlSize(.small) }
                        Image(systemName: "checkmark")
                            .frame(width: saved ? 13 : 0)
                            .opacity(saved ? 1 : 0)
                            .symbolEffect(.bounce, value: saved && !reduceMotion)
                        Text(saved ? "Saved" : (isSubmitting ? "Saving…" : (model.requiresReplacement ? "Replace in Keychain" : "Save to Keychain")))
                    }
                    .frame(minWidth: 54)
                }
                .buttonStyle(PromptButton(primary: true, completed: saved))
                .disabled(secret.isEmpty || model.isSaving || isSubmitting || model.request == nil)
                .accessibilityIdentifier("saveButton")
            }
        }
        .task(id: isSubmitting) {
            guard isSubmitting else { return }
            // Give the pressed/progress state a frame before the synchronous Keychain call.
            // View cancellation (close, EOF, or a new request) cancels this task first.
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled, model.request == request else { return }
            savedCount = secret.count
            model.save(secret, replace: replaceRequested)
            isSubmitting = false
        }
        .onChange(of: mismatch, initial: true) { _, value in showsMismatch = value != nil }
        .onAppear { focused = true; model.clearField = { secret = "" } }
        .onDisappear { secret = ""; model.clearField = nil }
    }

    // MARK: Destination
    private func destinationRow(_ title: LocalizedStringKey, value: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Candy.secondary)
                .frame(width: 46, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }

    private func providerLinkRow(_ providerLink: ProviderLink) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 46, height: 1).accessibilityHidden(true)
            Link(destination: providerLink.url) {
                Label("Open \(providerLink.displayHost)", systemImage: "arrow.up.right.square")
            }
            .font(.system(size: 11, weight: .semibold)).tint(Candy.violet)
            .accessibilityIdentifier("providerLink")
            .accessibilityLabel("Open agent-suggested provider page at \(providerLink.displayHost). Not verified by Tuck.")
            .help("Suggested by your agent · not verified by Tuck")
            .disabled(saved || isSubmitting)
        }
    }
}

private struct PromptButton: ButtonStyle {
    let primary: Bool
    var completed = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(primary && !completed ? .white : Candy.ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: completed ? [Color(red: 1, green: 0.76, blue: 0.12), Color(red: 1, green: 0.93, blue: 0.61), Color(red: 0.98, green: 0.75, blue: 0.14)] : [Candy.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Candy.ink.opacity(0.18), lineWidth: 1)
                }
            }
            .overlay {
                if primary && completed {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Color(red: 1, green: 0.94, blue: 0.69), lineWidth: 1)
                    GoldGlint(reduceMotion: reduceMotion).clipShape(RoundedRectangle(cornerRadius: 20))
                }
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(configuration.isPressed ? 0.20 : 0))
            }
            .shadow(color: completed ? Color.orange.opacity(0.35) : .clear, radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(enabled || completed ? 1 : 0.5)
    }
}

private struct GoldGlint: View {
    let reduceMotion: Bool
    @State private var passed = false

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28).rotationEffect(.degrees(20))
                .offset(x: passed ? geometry.size.width + 28 : -40)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: passed)
        }
        .onAppear { if !reduceMotion { passed = true } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CandyButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 13)
            .background(Candy.violet, in: Capsule())
            .shadow(color: Candy.violet.opacity(0.15), radius: 0, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
    }
}
