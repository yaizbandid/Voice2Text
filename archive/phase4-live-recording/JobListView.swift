import SwiftUI

struct JobListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: $state.selectedJobID) {
            ForEach(state.jobs) { job in
                JobRow(job: job)
                    .tag(job.id)
                    .contextMenu {
                        if let recordingURL = job.recordingURL {
                            Button("แสดงไฟล์เสียงใน Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([recordingURL])
                            }
                        }
                        Button("ลบออกจากรายการ", role: .destructive) {
                            state.remove(job.id)
                        }
                        .disabled(job.isActive)
                    }
            }
        }
        .listStyle(.inset)
        .frame(height: min(CGFloat(state.jobs.count) * 46 + 20, 180))
        .onDeleteCommand {
            if let selectedID = state.selectedJobID {
                state.remove(selectedID)
            }
        }
    }
}

struct JobRow: View {
    @EnvironmentObject var state: AppState
    let job: TranscriptionJob
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)
                Text(job.statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer()
            switch job.status {
            case .transcribing(let progress):
                ProgressView(value: progress)
                    .frame(width: 110)
            case .downloading(let progress) where progress >= 0:
                ProgressView(value: progress)
                    .frame(width: 110)
            case .recording:
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            case .extracting, .preparingDownload, .downloading, .finalizingRecording:
                ProgressView()
                    .controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .queued:
                EmptyView()
            }
            Button {
                state.remove(job.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(hovering && !job.isActive ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(job.isActive)
            .opacity(job.isActive ? 0.25 : (hovering ? 1 : 0.45))
            .help(job.isActive ? "ลบไม่ได้ระหว่างงานกำลังทำงาน" : "ลบออกจากรายการ")
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }

    private var statusColor: Color {
        if case .failed = job.status { return .orange }
        return .secondary
    }
}
