import SwiftUI
import ClipAnalysisCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    // อ่าน/เขียนคีย์เดียวกับ AnalysisState โดยตรง ให้ฟอร์มอัปเดตทันทีที่แก้
    @AppStorage("analysis.autoTranscribe") private var autoTranscribe = true
    @AppStorage("analysis.pace.th.slow") private var thaiSlow = PaceThresholds.thaiDefault.slowBelow
    @AppStorage("analysis.pace.th.normal") private var thaiNormal = PaceThresholds.thaiDefault.normalBelow
    @AppStorage("analysis.pace.th.fast") private var thaiFast = PaceThresholds.thaiDefault.fastBelow
    @AppStorage("analysis.pace.other.slow") private var otherSlow = PaceThresholds.englishDefault.slowBelow
    @AppStorage("analysis.pace.other.normal") private var otherNormal = PaceThresholds.englishDefault.normalBelow
    @AppStorage("analysis.pace.other.fast") private var otherFast = PaceThresholds.englishDefault.fastBelow
    @AppStorage("language") private var language = "auto"
    @AppStorage("modelVariant") private var modelVariant = AppState.defaultModel
    @AppStorage("analysis.cookiesBrowser") private var cookiesBrowser = ""
    @AppStorage("analysis.collectionLimit") private var collectionLimit = 20

    var body: some View {
        Form {
            Picker("ภาษาของเสียง", selection: $language) {
                Text("ตรวจจับอัตโนมัติ — ถอดตามภาษาต้นทาง (แนะนำ)").tag("auto")
                Text("บังคับไทย (กรณีตรวจจับพลาด)").tag("th")
                Text("บังคับอังกฤษ").tag("en")
            }

            Picker("โมเดลถอดเสียง", selection: $modelVariant) {
                Text("เร็ว — ความแม่นพอใช้ (~500MB)").tag("openai_whisper-small")
                Text("สมดุล — แนะนำ (~630MB)").tag(AppState.defaultModel)
                Text("แม่นที่สุด (~1.6GB)").tag("openai_whisper-large-v3-v20240930")
            }
            .pickerStyle(.radioGroup)

            Text("เปลี่ยนโมเดลแล้วระบบจะดาวน์โหลดให้อัตโนมัติในครั้งแรก โมเดลถูกเก็บไว้ในเครื่องที่ Library/Application Support/Voice2Text และทุกอย่างทำงานแบบออฟไลน์")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("วิเคราะห์คลิป") {
                Picker("ใช้คุกกี้จากเบราว์เซอร์", selection: $cookiesBrowser) {
                    Text("ไม่ใช้").tag("")
                    Text("Chrome").tag("chrome")
                    Text("Safari").tag("safari")
                    Text("Firefox").tag("firefox")
                    Text("Brave").tag("brave")
                    Text("Edge").tag("edge")
                }
                Text("จำเป็นสำหรับ Instagram Reels — เบราว์เซอร์ที่เลือกต้องล็อกอิน Instagram ไว้ (Safari ต้องให้สิทธิ์ Full Disk Access กับแอปก่อน) ไม่ส่งคุกกี้ไปที่ใดนอกจากเว็บต้นทาง")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("ลิงก์ช่อง: ดึงล่าสุด \(collectionLimit) คลิป", value: $collectionLimit, in: 1...200, step: 5)
                Toggle("ดึงข้อมูลแล้วถอดเสียง + วัดการพูดต่ออัตโนมัติ", isOn: $autoTranscribe)
            }

            Section("เกณฑ์ความเร็วพูด (คำต่อนาที)") {
                paceRow("ไทย", slow: $thaiSlow, normal: $thaiNormal, fast: $thaiFast)
                paceRow("ภาษาอื่น", slow: $otherSlow, normal: $otherNormal, fast: $otherFast)
                HStack {
                    Text("ต่ำกว่าช่องแรก = ช้า · ถึงช่องที่สอง = ปกติ · ถึงช่องที่สาม = เร็ว · เกินนั้น = เร็วมาก ภาษาไทยนับคำด้วยตัวตัดคำของ macOS ตัวเลขจึงสูงกว่าภาษาอังกฤษ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("ค่าเริ่มต้น") {
                        let th = PaceThresholds.thaiDefault, other = PaceThresholds.englishDefault
                        (thaiSlow, thaiNormal, thaiFast) = (th.slowBelow, th.normalBelow, th.fastBelow)
                        (otherSlow, otherNormal, otherFast) = (other.slowBelow, other.normalBelow, other.fastBelow)
                    }
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: modelVariant) {
            Task { await state.loadModel(variant: modelVariant) }
        }
    }

    private func paceRow(_ title: String, slow: Binding<Double>, normal: Binding<Double>, fast: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            ForEach(Array([("ช้า <", slow), ("ปกติ <", normal), ("เร็ว <", fast)].enumerated()), id: \.offset) { _, item in
                Text(item.0).font(.caption).foregroundStyle(.secondary)
                TextField("", value: item.1, format: .number.precision(.fractionLength(0)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
