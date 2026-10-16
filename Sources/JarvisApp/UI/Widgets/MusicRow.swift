import JarvisKit
import SwiftUI

/// What's playing in Music or Spotify, with previous, play/pause and next. A plain row, no card.
/// Click the song to open the app that's playing it.
struct MusicRow: View {
    let nowPlaying: NowPlaying?
    let tint: Color
    let playPause: () -> Void
    let previous: () -> Void
    let next: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .opacity(nowPlaying == nil ? 0.35 : 0.8)
                    if let nowPlaying {
                        Text(nowPlaying.title).fontWeight(.semibold)
                        Text(nowPlaying.artist).foregroundStyle(tint.opacity(0.5))
                    } else {
                        Text("Nothing playing").foregroundStyle(tint.opacity(0.35))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .disabled(nowPlaying == nil)
            .help(nowPlaying.map { "Open \($0.player == .spotify ? "Spotify" : "Music")" } ?? "")
            if let nowPlaying {
                Button(action: previous) {
                    Image(systemName: "backward.fill")
                }
                Button(action: playPause) {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: next) {
                    Image(systemName: "forward.fill")
                }
            }
        }
        .font(.system(size: 18, weight: .medium))
        .lineLimit(1)
        .buttonStyle(.plain)
    }
}
