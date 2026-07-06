import AppKit
import SwiftUI

@main
struct DescriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DescriptModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = "📜"
            button.toolTip = "Descript"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: DescriptPopup(model: model)
                .frame(width: 400)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }

        togglePopup(from: sender)
    }

    private func togglePopup(from sender: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func openPopoverFromMenu(_ sender: NSMenuItem) {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(sender)
        }
        togglePopup(from: button)
    }

    @objc private func quitFromMenu(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Descript", action: #selector(openPopoverFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Descript", action: #selector(quitFromMenu(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
}

struct DescriptPopup: View {
    @ObservedObject var model: DescriptModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.isShowingSettings {
                settingsPanel
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }

            VStack(spacing: 12) {
                sourcePicker
                activeSourcePanel
                notesPanel
                transcriptPanel
            }
            .padding(12)
        }
        .background(Color.zinc950)
        .foregroundStyle(Color.zinc100)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("📜")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Color.zinc950)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.zinc800))

            VStack(alignment: .leading, spacing: 1) {
                Text("Descript")
                    .font(.system(size: 20, weight: .semibold))
                Text("TRANSCRIPT POPUP")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Color.zinc500)
            }

            Spacer()

            Button {
                model.isShowingSettings.toggle()
            } label: {
                Text("Settings")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .foregroundStyle(model.activeAccent.foreground)
                    .background(model.activeAccent.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: model.activeAccent.color.opacity(0.16), radius: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.zinc900.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.zinc800).frame(height: 1)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BUTTON COLOR")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Color.zinc500)
                Spacer()
                Button("Close") {
                    model.isShowingSettings = false
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.zinc400)
                .buttonStyle(.plain)
            }

            colorChooser(title: "YouTube", source: .youtube)
            colorChooser(title: "MP4", source: .mp4)
        }
        .padding(12)
        .background(Color.zinc950.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.zinc800))
        .shadow(color: .black.opacity(0.65), radius: 24, y: 14)
    }

    private func colorChooser(title: String, source: TranscriptSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.zinc500)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Accent.allCases) { accent in
                    Button {
                        model.setAccent(accent, for: source)
                    } label: {
                        Text(accent.title)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .foregroundStyle(accent.foreground)
                            .background(accent.color)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(selectionRing(accent: accent, source: source))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.zinc900.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.zinc800))
    }

    private func selectionRing(accent: Accent, source: TranscriptSource) -> some View {
        let selected = model.accent(for: source) == accent
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(selected ? Color.zinc100 : Color.clear, lineWidth: 1)
            .padding(2)
    }

    private var sourcePicker: some View {
        HStack(spacing: 8) {
            sourceButton(.youtube)
            sourceButton(.mp4)
        }
        .padding(6)
        .background(Color.zinc950)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.zinc800))
    }

    private func sourceButton(_ source: TranscriptSource) -> some View {
        let active = model.source == source
        let accent = model.accent(for: source)

        return Button {
            model.source = source
        } label: {
            Text(source.title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(active ? accent.foreground : Color.zinc400)
                .background(active ? accent.color : Color.zinc900)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activeSourcePanel: some View {
        switch model.source {
        case .youtube:
            youtubePanel
        case .mp4:
            mp4Panel
        }
    }

    private var youtubePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUTUBE URL")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.zinc500)

            TextField("https://youtube.com/watch?v=...", text: $model.youtubeURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(Color.zinc950)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.zinc800))

            HStack(spacing: 8) {
                primaryButton("Extract", accent: model.youtubeAccent) {
                    model.extractYouTube()
                }
                Button("Paste") {
                    model.pasteClipboardToYouTube()
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 72, height: 34)
                .foregroundStyle(Color.zinc400)
                .background(Color.zinc950)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.zinc800))
                .buttonStyle(.plain)
            }
        }
        .panel()
    }

    private var mp4Panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCAL MP4")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.zinc500)

            primaryButton(model.selectedFileName ?? "Choose MP4", accent: model.mp4Accent) {
                model.chooseMP4()
            }

            Text("opens native file picker, then transcribes offline")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.zinc500)
        }
        .panel()
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.zinc500)
            TextEditor(text: $model.notes)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 48)
                .padding(6)
                .background(Color.zinc950)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.zinc800))
        }
        .panel()
    }

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSCRIPT")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Color.zinc500)
                    Text(model.statusText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.activeAccent.color)
                }

                Spacer()

                compactButton("Copy") { model.copyTranscript() }
                compactButton("Save") { model.saveTranscript() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.zinc800).frame(height: 1)
            }

            TextEditor(text: $model.transcript)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(height: 176)
                .padding(8)
                .background(Color.zinc950)
        }
        .background(Color.zinc900.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.zinc800))
    }

    private func primaryButton(_ title: String, accent: Accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(accent.foreground)
                .background(accent.color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: accent.color.opacity(0.16), radius: 12)
        }
        .disabled(model.isBusy)
        .buttonStyle(.plain)
    }

    private func compactButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .frame(height: 28)
            .padding(.horizontal, 10)
            .foregroundStyle(Color.zinc400)
            .background(Color.zinc950)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.zinc800))
            .buttonStyle(.plain)
    }
}

private extension View {
    func panel() -> some View {
        padding(12)
            .background(Color.zinc900.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.zinc800))
    }
}

private extension Color {
    static let zinc100 = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)
    static let zinc400 = Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)
    static let zinc500 = Color(red: 113 / 255, green: 113 / 255, blue: 122 / 255)
    static let zinc800 = Color(red: 39 / 255, green: 39 / 255, blue: 42 / 255)
    static let zinc900 = Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255)
    static let zinc950 = Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255)
}
