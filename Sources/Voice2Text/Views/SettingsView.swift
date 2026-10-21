import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
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
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: modelVariant) {
            Task { await state.loadModel(variant: modelVariant) }
        }
    }
}
