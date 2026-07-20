import SwiftUI
import Translation
import Voice2TextCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if state.isRecording {
                RecordingBar()
                Divider()
            }
            DropZoneView(compact: !state.jobs.isEmpty)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            URLInputRow()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            if !state.jobs.isEmpty {
                JobListView()
                Divider()
            }
            TranscriptView(job: state.selectedJob)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            TranslationBar(configuration: $translationConfig)
            Divider()
            ExportBar(job: state.selectedJob)
        }
        .frame(minWidth: 700, minHeight: 560)
        .dropDestination(for: URL.self) { urls, _ in
            state.add(urls: urls)
            return true
        }
        .translationTask(translationConfig) { session in
            await state.performTranslation(session: session)
        }
        .alert(
            "อัดการประชุมไม่สำเร็จ",
            isPresented: Binding(
                get: { state.recordingError != nil },
                set: { if !$0 { state.recordingError = nil } }
            )
        ) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(state.recordingError ?? "")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Voice2Text")
                .font(.title3.bold())
            Spacer()
            if !state.isRecording {
                Button {
                    state.startRecording()
                } label: {
                    Label("อัดการประชุม", systemImage: "record.circle")
                }
                .disabled(state.modelState != .ready)
                .help("อัดเสียงจากไมโครโฟนพร้อมถอดข้อความสด ๆ")
            }
            ModelStatusChip()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("ตั้งค่าภาษาและโมเดล")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ModelStatusChip: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.modelState {
            case .idle:
                Label("ยังไม่ได้โหลดโมเดล", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 90)
                    Text("ดาวน์โหลดโมเดล \(Int(progress * 100))%")
                        .foregroundStyle(.secondary)
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("กำลังเตรียมโมเดล (ครั้งแรกอาจใช้เวลา 1–3 นาที)")
                        .foregroundStyle(.secondary)
                }
            case .ready:
                Label("โมเดลพร้อมใช้งาน", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                HStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .frame(maxWidth: 280)
                    Button("ลองใหม่") {
                        state.loadModelIfNeeded()
                    }
                }
            }
        }
        .font(.caption)
    }
}

/// แถบควบคุมระหว่างอัดการประชุม
struct RecordingBar: View {
    @EnvironmentObject var state: AppState
    @State private var pulsing = false

    private var elapsedLabel: String {
        if let job = state.jobs.first(where: { if case .recording = $0.status { return true }; return false }),
           case .recording(let elapsed) = job.status {
            return Exporter.clock(elapsed)
        }
        return "00:00:00"
    }

    var body: some View {
        HStack(spacing: 12) {
            if state.isFinalizing {
                ProgressView()
                    .controlSize(.small)
                Text("กำลังปิดงาน — ถอดช่วงท้ายและบันทึกไฟล์เสียง…")
                    .fontWeight(.semibold)
                Spacer()
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .opacity(pulsing ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
                Text("กำลังอัดการประชุม")
                    .fontWeight(.semibold)
                Text(elapsedLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("ข้อความจะทยอยขึ้นด้านล่างเป็นช่วง ๆ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) {
                    state.stopRecording()
                } label: {
                    Label("หยุดและบันทึก", systemImage: "stop.circle.fill")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.06))
    }
}

struct URLInputRow: View {
    @EnvironmentObject var state: AppState
    @State private var urlText = ""
    @State private var showInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("หรือวางลิงก์ YouTube / วิดีโอออนไลน์ แล้วกด Enter", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("ถอดจากลิงก์") {
                    submit()
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if showInvalid {
                Text("ลิงก์ไม่ถูกต้อง — ต้องขึ้นต้นด้วย http:// หรือ https://")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        guard !urlText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if state.addRemote(urlText) {
            urlText = ""
            showInvalid = false
        } else {
            showInvalid = true
        }
    }
}

/// แถบแปลภาษา — ใช้ Apple Translation (แปลในเครื่อง ไม่ส่งข้อมูลออก)
struct TranslationBar: View {
    @EnvironmentObject var state: AppState
    @Binding var configuration: TranslationSession.Configuration?
    @AppStorage("targetLanguage") private var targetCode = "th"
    @State private var languageTags: [String] = []

    private var job: TranscriptionJob? { state.selectedJob }
    private var canTranslate: Bool {
        guard let job else { return false }
        return job.status == .done && !job.segments.isEmpty && job.translationProgress == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("แปลเป็น")
                Picker("", selection: $targetCode) {
                    ForEach(languageTags, id: \.self) { tag in
                        Text(languageDisplayName(tag)).tag(tag)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                if let progress = job?.translationProgress {
                    ProgressView(value: progress)
                        .frame(width: 110)
                    Text("กำลังแปล \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        startTranslation()
                    } label: {
                        Label("แปล", systemImage: "character.book.closed")
                    }
                    .disabled(!canTranslate)
                }

                Spacer()

                if job?.hasTranslation == true {
                    Picker("", selection: Binding(
                        get: { state.displayMode },
                        set: { state.displayMode = $0 }
                    )) {
                        ForEach(TranscriptDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
            }
            if let error = state.translationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .task {
            await loadSupportedLanguages()
        }
    }

    private func startTranslation() {
        guard let job else { return }
        state.translationError = nil

        let target = Locale.Language(identifier: targetCode)
        if let detected = job.detectedLanguage,
           let targetPrimary = target.languageCode?.identifier,
           detected.lowercased().hasPrefix(targetPrimary.lowercased()) {
            state.translationError = "ข้อความต้นฉบับเป็นภาษา\(languageDisplayName(detected))อยู่แล้ว เลือกภาษาอื่นได้เลย"
            return
        }

        let source = job.detectedLanguage.map { Locale.Language(identifier: $0) }
        state.pendingTranslation = PendingTranslation(jobID: job.id, targetCode: targetCode)

        if var existing = configuration, existing.source == source, existing.target == target {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func loadSupportedLanguages() async {
        let languages = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        var tags: [String] = []
        for language in languages {
            let tag = language.minimalIdentifier
            if seen.insert(tag).inserted {
                tags.append(tag)
            }
        }
        // เอาไทยกับอังกฤษขึ้นก่อน ที่เหลือเรียงตามชื่อภาษาไทย (เลือกรหัสตรงเป๊ะก่อน กันหยิบ en-AU มาแทน en)
        let priority = ["th", "en"]
        let front = priority.compactMap { code in
            tags.first { $0 == code } ?? tags.first { $0.hasPrefix(code) }
        }
        let rest = tags.filter { !front.contains($0) }
            .sorted { languageDisplayName($0) < languageDisplayName($1) }
        languageTags = front + rest
        if !languageTags.contains(targetCode), let first = languageTags.first {
            targetCode = first
        }
    }
}

struct ExportBar: View {
    @EnvironmentObject var state: AppState
    let job: TranscriptionJob?

    private var segments: [TranscriptSegment] { job?.segments ?? [] }
    private var variant: Exporter.Variant {
        job?.hasTranslation == true ? state.displayMode.exportVariant : .original
    }

    var body: some View {
        HStack(spacing: 10) {
            if let job, !segments.isEmpty {
                Text(exportDescription(job))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                copyAll()
            } label: {
                Label("คัดลอก", systemImage: "doc.on.doc")
            }
            Button {
                save(text: Exporter.plainText(segments, variant: variant), ext: "txt")
            } label: {
                Label("บันทึก .txt", systemImage: "doc.text")
            }
            Button {
                save(text: Exporter.srt(segments, variant: variant), ext: "srt")
            } label: {
                Label("บันทึก .srt", systemImage: "captions.bubble")
            }
        }
        .disabled(segments.isEmpty)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func exportDescription(_ job: TranscriptionJob) -> String {
        var text = "\(job.displayName) • \(segments.count) ช่วง"
        if job.hasTranslation {
            text += " • บันทึกแบบ: \(state.displayMode.label)"
        }
        return text
    }

    private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Exporter.plainText(segments, variant: variant), forType: .string)
    }

    private func save(text: String, ext: String) {
        guard let job else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = job.suggestedExportBase + ".\(ext)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
