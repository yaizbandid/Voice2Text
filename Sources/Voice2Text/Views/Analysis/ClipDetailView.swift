import SwiftUI
import ClipAnalysisCore

/// แผงรายละเอียดคลิปที่เลือก — เฟสถัดไปจะเพิ่ม transcript, timeline Hook/Body/CTA และปุ่ม Approve
struct ClipDetailView: View {
    @EnvironmentObject var analysis: AnalysisState
    let clip: ClipRecord?
    let selectionCount: Int

    var body: some View {
        if let clip {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    thumbnail(clip)
                    VStack(alignment: .leading, spacing: 4) {
                        PlatformBadge(platform: clip.platform)
                        Text(clip.title)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text(clip.channel ?? "–")
                            .foregroundStyle(.secondary)
                    }
                    metricsGrid(clip)
                    actions(clip)
                    SpeechSection(clip: clip)
                    if let description = clip.description, !description.isEmpty {
                        GroupBox("คำอธิบายคลิป") {
                            Text(description)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(8)
                                .textSelection(.enabled)
                        }
                    }
                    Text("ดึงข้อมูลล่าสุด \(clip.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        } else {
            ContentUnavailableView(
                selectionCount > 1 ? "เลือกไว้ \(selectionCount) คลิป" : "เลือกคลิปเพื่อดูรายละเอียด",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text(selectionCount > 1 ? "คลิกขวาเพื่อดึงยอดใหม่หรือลบพร้อมกัน" : ""))
        }
    }

    private func thumbnail(_ clip: ClipRecord) -> some View {
        AsyncImage(url: clip.thumbnailURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metricsGrid(_ clip: ClipRecord) -> some View {
        let m = clip.metrics
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                stat("วิว", ClipFormat.count(m.views), exact: m.views)
                stat("ไลก์", ClipFormat.count(m.likes), exact: m.likes)
            }
            GridRow {
                stat("คอมเมนต์", ClipFormat.count(m.comments), exact: m.comments)
                stat("ผู้ติดตามช่อง", ClipFormat.count(m.followers), exact: m.followers)
            }
            GridRow {
                stat("Engagement", ClipFormat.percent(m.engagementRate), help: "(ไลก์ + คอมเมนต์) ÷ วิว")
                stat("วิว ÷ ผู้ติดตาม", ClipFormat.ratio(m.viewsPerFollower), help: "มากกว่า 1× = คลิปไปไกลกว่าฐานแฟน")
            }
            GridRow {
                stat("ความยาว", ClipFormat.duration(clip.durationSeconds))
                stat("โพสต์เมื่อ", ClipFormat.date(clip.uploadDate),
                     help: clip.ageDays().map { "\($0) วันที่แล้ว" })
            }
        }
    }

    private func stat(_ label: String, _ value: String, exact: Int? = nil, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .help(help ?? exact.map { $0.formatted() } ?? "ไม่มีข้อมูลจากแพลตฟอร์ม")
    }

    private func actions(_ clip: ClipRecord) -> some View {
        HStack {
            Button {
                NSWorkspace.shared.open(clip.url)
            } label: { Label("เปิดคลิป", systemImage: "safari") }
            Button {
                analysis.refresh([clip.id])
            } label: { Label("ดึงยอดใหม่", systemImage: "arrow.clockwise") }
            Spacer()
            Button(role: .destructive) {
                analysis.delete([clip.id])
            } label: { Image(systemName: "trash") }
            .help("ลบออกจากคลัง")
        }
        .controlSize(.small)
    }
}

/// ผลวัดการพูด + ข้อความถอดเสียง (เฟส 2)
struct SpeechSection: View {
    @EnvironmentObject var analysis: AnalysisState
    let clip: ClipRecord
    @State private var showTranscript = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let activity = analysis.clipActivity[clip.id] {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(activity).font(.callout).lineLimit(2)
                    }
                } else if let speech = clip.speech {
                    metrics(speech)
                } else if clip.transcript != nil {
                    Text("ไม่พบเสียงพูดในคลิปนี้ (อาจเป็นเพลงล้วน)").font(.callout).foregroundStyle(.secondary)
                } else {
                    if let error = clip.transcriptError {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Button {
                        analysis.transcribe([clip.id])
                    } label: { Label("ถอดเสียง & วัดการพูด", systemImage: "waveform.badge.magnifyingglass") }
                    .controlSize(.small)
                }
                if let transcript = clip.transcript, !transcript.segments.isEmpty {
                    DisclosureGroup("ข้อความถอดเสียง (\(transcript.segments.count) ประโยค)", isExpanded: $showTranscript) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(transcript.segments) { segment in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(ClipFormat.duration(segment.start))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(segment.text).font(.callout)
                                }
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("การพูด")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let transcript = clip.transcript, analysis.clipActivity[clip.id] == nil {
            HStack(spacing: 6) {
                if let language = transcript.language {
                    Text("ภาษา: \(languageDisplayName(language))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("ถอดใหม่") { analysis.transcribe([clip.id]) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private func metrics(_ speech: SpeechMetrics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                cell("ความเร็ว", "\(Int(speech.wordsPerMinute.rounded())) คำ/นาที",
                     badge: analysis.paceLabel(for: clip)?.displayName)
                cell("5 วินาทีแรก", speech.openingWPM.map { "\(Int($0.rounded())) คำ/นาที" } ?? "–",
                     help: "ความเร็วช่วงเปิดคลิป (ประมาณช่วง Hook)")
            }
            GridRow {
                cell("เริ่มพูดที่", String(format: "%.1f วิ", speech.timeToFirstWord))
                cell("ช่วงเงียบ > \(String(format: "%.1f", SpeechMetrics.pauseThreshold)) วิ",
                     "\(speech.pauseCount) ครั้ง",
                     help: speech.pauseCount > 0 ? String(format: "นานสุด %.1f วินาที", speech.longestPause) : nil)
            }
            GridRow {
                cell("จำนวนคำ", "\(speech.wordCount)")
                cell("สัดส่วนเวลาพูด", speech.speechRatio.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                     help: "เวลาที่มีเสียงพูด ÷ ความยาวคลิป")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !speech.usedWordTimings {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help("ประมาณจากเวลาของประโยค (ไม่มีเวลาระดับคำ) — ค่าอาจคลาดเคลื่อน")
            }
        }
    }

    private func cell(_ label: String, _ value: String, badge: String? = nil, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
        }
        .help(help ?? "")
    }
}
