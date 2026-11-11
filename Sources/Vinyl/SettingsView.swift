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
                row("sun.horizon", "Match time of day", "Daylight from 6:30 am, Lamplight after 6:30 pm") {
                    Toggle("", isOn: $state.autoScene).labelsHidden().toggleStyle(.switch).tint(accent)
                }
                Divider().overlay(hairline)
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

            Text("On your desktop: click the tonearm to play or pause, and the brass buttons to skip.")
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(state.track?.title ?? "Nothing playing").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(state.track?.artist ?? "Play a track in Spotify or Apple Music").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                if let t = state.track {
                    Text(t.player.displayName).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if state.track != nil {
                Button(action: togglePlayback) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func sceneCard(_ p: TurntableScene.Preset) -> some View {
        let selected = state.preset == p
        return Button {
            state.pick(p)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if state.thumbnails.indices.contains(p.rawValue) {
                        Image(nsImage: state.thumbnails[p.rawValue]).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.05)
                    }
                }
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipped()
                HStack {
                    Text(p.title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? accent : Color.white.opacity(0.25))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.opacity(0.9) : hairline, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func row<Control: View>(_ icon: String, _ title: String, _ subtitle: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
