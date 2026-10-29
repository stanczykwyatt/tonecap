import SwiftUI
import ToneCore

/// The colors of the panel: near-black glass, quiet grays and one ice-blue accent.
enum Palette {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.078)
    static let raised = Color(red: 0.094, green: 0.106, blue: 0.129)
    static let line = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.5)
    static let accent = Color(red: 0.62, green: 0.82, blue: 1.0)
}

enum PanelTab: String, CaseIterable, Identifiable {
    case sound = "Switch", build = "Board", output = "Output", share = "Share"
    var id: String { rawValue }
}

/// The settings panel under the menu bar icon: dark and dense, with tabs.
struct PanelView: View {
    @Bindable var model: Model
    @State var tab: PanelTab
    var allow: () -> Void = {}
    var openSite: () -> Void = {}
    var copyLink: () -> Void = {}
    var quit: () -> Void = {}
    var loginItem: Binding<Bool> = .constant(false)

    static let width: CGFloat = 340

    init(model: Model, tab: PanelTab = .sound, allow: @escaping () -> Void = {}, openSite: @escaping () -> Void = {}, copyLink: @escaping () -> Void = {}, quit: @escaping () -> Void = {}, loginItem: Binding<Bool> = .constant(false)) {
        self.model = model
        _tab = State(initialValue: tab)
        self.allow = allow
        self.openSite = openSite
        self.copyLink = copyLink
        self.quit = quit
        self.loginItem = loginItem
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.hasAccess {
                tabs
                Divider().overlay(Palette.line)
                Group {
                    switch tab {
                    case .sound: switchTab
                    case .build: boardTab
                    case .output: outputTab
                    case .share: shareTab
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 346, alignment: .top)
            } else {
                AccessCard(allow: allow)
            }
            Divider().overlay(Palette.line)
            footer
        }
        .frame(width: PanelView.width)
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tonecap").font(.system(size: 13, weight: .semibold))
                Text(model.settings.designName ?? "Custom sound")
                    .font(.system(size: 11)).foregroundStyle(Palette.dim).lineLimit(1)
            }
            Spacer()
            Button { model.toggleMute() } label: {
                Text(model.muted ? "MUTED" : "ON")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(model.muted ? Color.white.opacity(0.08) : Palette.accent.opacity(0.18)))
                    .foregroundStyle(model.muted ? Palette.dim : Palette.accent)
            }
            .buttonStyle(.plain)
            .help("Mute or unmute (⌃⌥M)")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Text(item.rawValue.uppercased())
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(tab == item ? Palette.text : Palette.dim)
                        Rectangle().fill(tab == item ? Palette.accent : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.top, 2)
    }

    // MARK: Tabs

    private var switchTab: some View {
        VStack(spacing: 10) {
            ChoiceRow(label: "Type", options: SwitchType.allCases, title: { $0.rawValue.capitalized }, selection: model.settings.design.switchType) { value in model.edit { $0.switchType = value } }
            slider("Spring", \.spring, low: "Light", high: "Heavy") { "\(35 + $0 * 45 / 100) g" }
            slider("Lube", \.lube, low: "Dry", high: "Thick") { "\($0)%" }
            slider("Bottom-out", \.bottomOut, low: "Soft", high: "Hard") { "\($0)%" }
            slider("Top-out", \.topOut, low: "Soft", high: "Hard") { "\($0)%" }
        }
    }

    private var boardTab: some View {
        VStack(spacing: 10) {
            ChoiceRow(label: "Plate", options: Plate.allCases, title: Self.plateName, selection: model.settings.design.plate) { value in model.edit { $0.plate = value } }
            ChoiceRow(label: "Case", options: CaseMaterial.allCases, title: { $0.rawValue.capitalized }, selection: model.settings.design.caseMaterial) { value in model.edit { $0.caseMaterial = value } }
            slider("Foam", \.foam, low: "None", high: "Packed") { "\($0)%" }
            ChoiceRow(label: "Keycaps", options: Keycap.allCases, title: { $0.rawValue.uppercased() }, selection: model.settings.design.keycap) { value in model.edit { $0.keycap = value } }
            slider("Thickness", \.thickness, low: "Thin", high: "Thick") { String(format: "%.1f mm", 1 + Double($0) / 100) }
            ChoiceRow(label: "Profile", options: Profile.allCases, title: { $0.rawValue.capitalized }, selection: model.settings.design.profile) { value in model.edit { $0.profile = value } }
            slider("Stabilizers", \.stabilizers, low: "Rattly", high: "Tuned") { "\($0)%" }
        }
    }

    private var outputTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            ValueSlider(label: "Volume", value: Binding(get: { Int((model.volume * 100).rounded()) }, set: { model.volume = Double($0) / 100 }), low: "", high: "") { "\($0)%" }
            ToggleRow(label: "Mute", detail: "⌃⌥M from anywhere", isOn: Binding(get: { model.muted }, set: { model.muted = $0 }))
            ToggleRow(label: "Play releases", detail: "A softer sound when a key comes back up", isOn: Binding(get: { model.playsReleases }, set: { model.playsReleases = $0 }))
            ToggleRow(label: "Play held keys", detail: "A sound for each repeat while a key is held", isOn: Binding(get: { model.playsRepeats }, set: { model.playsRepeats = $0 }))
            ToggleRow(label: "Open at login", detail: nil, isOn: loginItem)
            SectionLabel("QUIET IN")
            if let front = model.frontApp {
                ToggleRow(label: front.name, detail: "The app you were just using", isOn: Binding(get: { model.isMuted(front.id) }, set: { model.setMuted(front.id, $0) }))
            }
            ForEach(model.settings.mutedApps.filter { $0 != model.frontApp?.id }, id: \.self) { id in
                ToggleRow(label: model.appName(id), detail: nil, isOn: Binding(get: { model.isMuted(id) }, set: { model.setMuted(id, $0) }))
            }
            if model.frontApp == nil && model.settings.mutedApps.isEmpty {
                Text("Switch to an app, then open this panel to keep Tonecap quiet in it.")
                    .font(.system(size: 11)).foregroundStyle(Palette.dim)
            }
        }
    }

    @State private var importText = ""

    private var shareTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("PRESETS")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Design.presets, id: \.name) { preset in
                    Button { model.choose(preset) } label: {
                        Text(preset.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(model.settings.designName == preset.name ? Palette.accent.opacity(0.2) : Palette.raised))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.settings.designName == preset.name ? Palette.accent.opacity(0.6) : Palette.line))
                    }
                    .buttonStyle(.plain)
                }
            }
            SectionLabel("IMPORT A LINK")
            HStack(spacing: 6) {
                TextField("Paste a link from the playground", text: $importText)
                    .textFieldStyle(.plain).font(.system(size: 11.5))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.raised))
                    .onSubmit { model.importDesign(importText) }
                Button("Import") { model.importDesign(importText) }.controlSize(.small)
            }
            if let message = model.importMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.dim)
            }
            SectionLabel("THIS SOUND")
            HStack(spacing: 6) {
                Button("Copy Link", action: copyLink).controlSize(.small)
                Button("Open in Playground", action: openSite).controlSize(.small)
            }
            Text(ShareCode.encode(model.settings.design))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.dim).textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack {
            Button { model.playTest() } label: {
                Label("Test", systemImage: "play.fill").font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
            .disabled(!model.hasAccess && model.player == nil)
            Spacer()
            Text(model.isListening ? "Listening for key presses" : "Not listening")
                .font(.system(size: 10.5)).foregroundStyle(Palette.dim)
            Spacer()
            Button("Quit", action: quit).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func slider(_ label: String, _ path: WritableKeyPath<Design, Int>, low: String, high: String, value: @escaping (Int) -> String) -> some View {
        ValueSlider(label: label, value: Binding(get: { model.settings.design[keyPath: path] }, set: { v in model.edit { $0[keyPath: path] = v } }), low: low, high: high, display: value)
    }

    static func plateName(_ plate: Plate) -> String {
        switch plate {
        case .aluminum: "Alu"
        case .brass: "Brass"
        case .polycarbonate: "PC"
        case .fr4: "FR4"
        case .pom: "POM"
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.dim).padding(.top, 4)
    }
}

/// A label, its value on the right, and a slider under them.
struct ValueSlider: View {
    let label: String
    @Binding var value: Int
    let low: String
    let high: String
    let display: (Int) -> String

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(display(value)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Palette.accent)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: 0...100)
                .controlSize(.small)
                .accessibilityLabel(label)
            if !low.isEmpty {
                HStack {
                    Text(low)
                    Spacer()
                    Text(high)
                }
                .font(.system(size: 9.5)).foregroundStyle(Palette.dim.opacity(0.8))
            }
        }
    }
}

/// A row of pill buttons, one lit.
struct ChoiceRow<T: Hashable>: View {
    let label: String
    let options: [T]
    let title: (T) -> String
    let selection: T
    let choose: (T) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).frame(width: 64, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(options, id: \.self) { option in
                    Button { choose(option) } label: {
                        Text(title(option))
                            .font(.system(size: 11, weight: option == selection ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(option == selection ? Palette.accent.opacity(0.22) : .clear))
                            .foregroundStyle(option == selection ? Palette.accent : Palette.dim)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.raised))
        }
    }
}

struct ToggleRow: View {
    let label: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.dim) }
            }
            Spacer()
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// Shown until Input Monitoring is on.
struct AccessCard: View {
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow Input Monitoring").font(.system(size: 14, weight: .semibold))
            Text("To play a sound as you type in any app, macOS asks you to allow Tonecap to know when a key goes down and comes up.")
                .font(.system(size: 12)).foregroundStyle(Palette.text.opacity(0.8))
            VStack(alignment: .leading, spacing: 5) {
                Label("It learns which key, never which letter or what you type", systemImage: "checkmark")
                Label("It keeps nothing, and has no internet access", systemImage: "checkmark")
                Label("It plays nothing while you type a password", systemImage: "checkmark")
            }
            .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
            Button("Allow Input Monitoring…", action: allow).controlSize(.regular).keyboardShortcut(.defaultAction)
            Text("Turn on Tonecap in System Settings → Privacy & Security → Input Monitoring, then come back here.")
                .font(.system(size: 10.5)).foregroundStyle(Palette.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
    }
}
