import SwiftUI
import UniformTypeIdentifiers
import Voice2TextCore

struct DropZoneView: View {
    @EnvironmentObject var state: AppState
    let compact: Bool

    @State private var isTargeted = false
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: compact ? 6 : 14) {
            Image(systemName: "waveform.badge.plus")
                .font(compact ? .title2 : .system(size: 40))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            if !compact {
                Text("ลากไฟล์เสียงหรือวิดีโอมาวางที่นี่")
                    .font(.headline)
                Text("รองรับ mp3, wav, m4a, flac, aiff, mp4, mov")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(compact ? "เพิ่มไฟล์…" : "หรือคลิกเพื่อเลือกไฟล์…") {
                showPicker = true
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 92 : 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            state.add(urls: urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                state.add(urls: urls)
            }
        }
    }
}
