import SwiftUI
import Voice2TextCore

struct TranscriptView: View {
    @EnvironmentObject var state: AppState
    let job: TranscriptionJob?

    private var mode: TranscriptDisplayMode {
        job?.hasTranslation == true ? state.displayMode : .original
    }

    var body: some View {
        if let job, !(job.segments.isEmpty && job.liveText.isEmpty) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(job.segments) { segment in
                            SegmentRow(segment: segment, mode: mode)
                                .id(segment.id)
                        }
                        if !job.liveText.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(liveTail(job.liveText))
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .id("live")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: job.segments.count) {
                    if let lastID = job.segments.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: job.liveText) {
                    if !job.liveText.isEmpty {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text(placeholderText)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var placeholderText: String {
        guard let job else { return "ข้อความที่ถอดได้จะแสดงที่นี่" }
        switch job.status {
        case .queued: return "รอคิวถอดเสียง…"
        case .preparingDownload(let message): return message
        case .downloading: return "กำลังดาวน์โหลดจากลิงก์…"
        case .extracting: return "กำลังแยกเสียงจากวิดีโอ…"
        case .transcribing: return "กำลังเริ่มถอดเสียง…"
        case .recording: return "กำลังฟัง… พูดได้เลย ข้อความจะขึ้นเป็นช่วง ๆ"
        case .finalizingRecording: return "กำลังปิดงานและบันทึกไฟล์เสียง…"
        case .failed(let message): return "ผิดพลาด: \(message)"
        case .done: return "ไฟล์นี้ไม่พบเสียงพูด"
        }
    }

    /// แสดงเฉพาะท้ายข้อความสด ๆ กันล้นจอ
    private func liveTail(_ text: String) -> String {
        let limit = 300
        guard text.count > limit else { return text }
        return "…" + text.suffix(limit)
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment
    let mode: TranscriptDisplayMode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Exporter.clock(segment.start))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                switch mode {
                case .original:
                    Text(segment.text)
                        .textSelection(.enabled)
                case .translated:
                    Text(segment.translation ?? segment.text)
                        .textSelection(.enabled)
                case .bilingual:
                    Text(segment.text)
                        .textSelection(.enabled)
                    if let translation = segment.translation {
                        Text(translation)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
