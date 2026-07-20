import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("language") private var language = "auto"
    @AppStorage("modelVariant") private var modelVariant = AppState.defaultModel

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
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: modelVariant) {
            Task { await state.loadModel(variant: modelVariant) }
        }
    }
}
