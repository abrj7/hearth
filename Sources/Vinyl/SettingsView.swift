import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    var togglePlayback: () -> Void

    private let card = Color.white.opacity(0.045)
    private let hairline = Color.white.opacity(0.08)
    private let accent = Color(red: 0.93, green: 0.56, blue: 0.27)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "opticaldisc.fill").font(.system(size: 20)).foregroundStyle(accent)
                Text("vinyl").font(.system(size: 26, weight: .bold, design: .rounded))
            }
            .padding(.top, 14)

            nowPlaying

            VStack(alignment: .leading, spacing: 12) {
                Text("Scene").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(TurntableScene.Preset.allCases) { sceneCard($0) }
                }
            }
            .padding(14)
            .background(card, in: RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 0) {
                row("rectangle.on.rectangle", "Transparent background", "Sit the turntable on your own wallpaper") {
                    Toggle("", isOn: $state.transparent).labelsHidden().toggleStyle(.switch).tint(accent)
                }
                Divider().overlay(hairline)
                row("arrow.up.left.and.arrow.down.right", "Size", nil) {
                    Picker("", selection: $state.sizeIndex) {
                        ForEach(0..<AppState.sizeNames.count, id: \.self) { Text(AppState.sizeNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                Divider().overlay(hairline)
                row("power", "Launch at login", nil) {
                    Toggle("", isOn: $state.launchAtLogin).labelsHidden().toggleStyle(.switch).tint(accent)
                }
            }
            .background(card, in: RoundedRectangle(cornerRadius: 14))

            Text("Click the turntable on your desktop to play or pause.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(width: 660)
        .preferredColorScheme(.dark)
    }

    private var nowPlaying: some View {
        HStack(spacing: 14) {
            Group {
                if let art = state.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.06)
                        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 60, height: 60)
