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
