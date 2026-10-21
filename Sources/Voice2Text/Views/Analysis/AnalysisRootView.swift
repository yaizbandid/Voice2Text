import SwiftUI
import UniformTypeIdentifiers
import ClipAnalysisCore

/// แท็บ "วิเคราะห์คลิป" — เฟส 1: วางลิงก์ → ดึงยอด → คลังคลิป
struct AnalysisRootView: View {
    @EnvironmentObject var analysis: AnalysisState
    @State private var input = ""
    @State private var search = ""
    @State private var platformFilter: Platform?
    @State private var exportingCSV = false

    var body: some View {
        VStack(spacing: 0) {
            inputBar
                .padding(12)
            statusArea
            Divider()
            HSplitView {
                ClipTableView(clips: filteredClips)
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                ClipDetailView(clip: analysis.selectedClip, selectionCount: analysis.selectedClipIDs.count)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .toolbar { toolbarContent }
        .searchable(text: $search, placement: .toolbar, prompt: "ค้นหาชื่อคลิป / ช่อง")
        .fileExporter(
            isPresented: $exportingCSV,
            document: CSVDocument(text: analysis.csv(for: analysis.selectedClipIDs.isEmpty ? nil : analysis.selectedClipIDs)),
            contentType: .commaSeparatedText,
            defaultFilename: "voice2text-clips.csv"
        ) { _ in }
    }

    private var filteredClips: [ClipRecord] {
        analysis.clips.filter { clip in
            (platformFilter == nil || clip.platform == platformFilter)
                && (search.isEmpty
                    || clip.title.localizedCaseInsensitiveContains(search)
                    || (clip.channel ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("วางลิงก์ YouTube / Shorts / Reels หรือลิงก์ช่อง (หลายลิงก์ได้ คั่นด้วยการขึ้นบรรทัด)", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(submit)
            Button("ดึงข้อมูล", action: submit)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if let activity = analysis.activity {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(activity).lineLimit(1).truncationMode(.middle)
                if analysis.queuedCount > 0 {
                    Text("รอคิว \(analysis.queuedCount)").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        ForEach(Array(analysis.messages.enumerated()), id: \.offset) { _, message in
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).textSelection(.enabled)
                Spacer()
                Button {
                    analysis.messages.removeAll { $0 == message }
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("แพลตฟอร์ม", selection: $platformFilter) {
                Text("ทุกแพลตฟอร์ม").tag(Platform?.none)
                ForEach(Platform.allCases, id: \.self) { Text($0.displayName).tag(Platform?.some($0)) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button {
                exportingCSV = true
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .help(analysis.selectedClipIDs.isEmpty ? "Export ทั้งคลัง" : "Export เฉพาะที่เลือก")
            .disabled(analysis.clips.isEmpty)
        }
    }

    private func submit() {
        if analysis.submit(input) { input = "" }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - รูปแบบตัวเลข

enum ClipFormat {
    static func count(_ value: Int?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.notation(.compactName).locale(Locale(identifier: "th_TH")))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.percent.precision(.fractionLength(2)))
    }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f×", value)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "th_TH")))
    }
}
