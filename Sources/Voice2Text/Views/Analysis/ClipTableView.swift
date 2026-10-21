import SwiftUI
import ClipAnalysisCore

/// ตารางคลังคลิป — เรียงตามคอลัมน์ได้ ค่าที่ไม่มีข้อมูลอยู่ท้ายเสมอ
struct ClipTableView: View {
    @EnvironmentObject var analysis: AnalysisState
    let clips: [ClipRecord]
    @State private var sortOrder = [KeyPathComparator(\ClipRow.createdAt, order: .reverse)]

    var body: some View {
        if analysis.clips.isEmpty {
            ContentUnavailableView(
                "ยังไม่มีคลิปในคลัง",
                systemImage: "film.stack",
                description: Text("วางลิงก์คลิป หรือลิงก์ช่อง เช่น youtube.com/@ชื่อช่อง/shorts แล้วกด \"ดึงข้อมูล\""))
        } else {
            Table(rows, selection: $analysis.selectedClipIDs, sortOrder: $sortOrder) {
                TableColumn("คลิป", value: \.title) { row in
                    HStack(spacing: 6) {
                        PlatformBadge(platform: row.clip.platform)
                        Text(row.clip.title).lineLimit(1)
                    }
                    .help(row.clip.title)
                }
                .width(min: 180, ideal: 260)
                TableColumn("ช่อง", value: \.channel) { Text($0.channel).lineLimit(1) }
                    .width(min: 70, ideal: 110)
                TableColumn("วิว", value: \.views) { Text(ClipFormat.count($0.clip.metrics.views)).monospacedDigit() }
                    .width(min: 50, ideal: 64)
                TableColumn("ไลก์", value: \.likes) { Text(ClipFormat.count($0.clip.metrics.likes)).monospacedDigit() }
                    .width(min: 50, ideal: 60)
                TableColumn("คอมเมนต์", value: \.comments) { Text(ClipFormat.count($0.clip.metrics.comments)).monospacedDigit() }
                    .width(min: 50, ideal: 64)
                TableColumn("ER", value: \.engagement) { Text(ClipFormat.percent($0.clip.metrics.engagementRate)).monospacedDigit() }
                    .width(min: 50, ideal: 60)
                TableColumn("การพูด", value: \.wpm) { row in
                    if let activity = analysis.clipActivity[row.id] {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(activity).font(.caption).lineLimit(1)
                        }
                        .help(activity)
                    } else if let speech = row.clip.speech {
                        Text("\(Int(speech.wordsPerMinute.rounded())) · \(analysis.paceLabel(for: row.clip)?.displayName ?? "")")
                            .monospacedDigit()
                            .help("คำต่อนาที · ระดับความเร็ว")
                    } else if row.clip.transcriptError != nil {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            .help(row.clip.transcriptError ?? "")
                    } else {
                        Text("–").foregroundStyle(.secondary)
                    }
                }
                .width(min: 70, ideal: 90)
                TableColumn("โพสต์", value: \.uploaded) { Text(ClipFormat.date($0.clip.uploadDate)) }
                    .width(min: 70, ideal: 90)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("ดึงยอดใหม่") { analysis.refresh(ids) }
                Button("ถอดเสียง & วัดการพูด") { analysis.transcribe(ids) }
                Button("เปิดคลิปในเบราว์เซอร์") {
                    for clip in analysis.clips where ids.contains(clip.id) { NSWorkspace.shared.open(clip.url) }
                }
                Divider()
                Button("ลบออกจากคลัง", role: .destructive) { analysis.delete(ids) }
            } primaryAction: { ids in
                for clip in analysis.clips where ids.contains(clip.id) { NSWorkspace.shared.open(clip.url) }
            }
            .onDeleteCommand { analysis.delete(analysis.selectedClipIDs) }
        }
    }

    private var rows: [ClipRow] {
        clips.map(ClipRow.init).sorted(using: sortOrder)
    }
}

/// ห่อ ClipRecord ให้ทุกคอลัมน์เรียงได้ — ค่าว่างแทนด้วย -1 ให้ไปอยู่ท้ายเมื่อเรียงมากไปน้อย
struct ClipRow: Identifiable {
    let clip: ClipRecord
    var id: String { clip.id }
    var title: String { clip.title }
    var channel: String { clip.channel ?? "" }
    var views: Int { clip.metrics.views ?? -1 }
    var likes: Int { clip.metrics.likes ?? -1 }
    var comments: Int { clip.metrics.comments ?? -1 }
    var engagement: Double { clip.metrics.engagementRate ?? -1 }
    var wpm: Double { clip.speech?.wordsPerMinute ?? -1 }
    var uploaded: Date { clip.uploadDate ?? .distantPast }
    var createdAt: Date { clip.createdAt }
}

struct PlatformBadge: View {
    let platform: Platform

    var body: some View {
        Text(platform.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var color: Color {
        switch platform {
        case .youtube: return .red
        case .shorts: return .orange
        case .reels: return .purple
        }
    }
}
