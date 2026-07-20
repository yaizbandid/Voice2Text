# ฟีเจอร์อัดการประชุม + ถอดเสียงสด (ถอดออกเมื่อ 6 ก.ค. 2026 ตามคำขอผู้ใช้)

โฟลเดอร์นี้เก็บสำเนาไฟล์ทั้งหมด ณ เวอร์ชัน v1.1.1 ซึ่งเป็นสภาพ "ก่อนถอดฟีเจอร์"
(ฟีเจอร์ผ่านการแก้บักและ review ครบแล้ว ใช้งานได้จริง)

## วิธีกู้คืนฟีเจอร์

1. คัดลอก `LiveSession.swift` และ `LiveTranscriber.swift` กลับไปที่ `Sources/Voice2TextCore/`
2. เทียบไฟล์ที่เหลือในโฟลเดอร์นี้กับไฟล์ปัจจุบัน แล้วนำส่วนที่เกี่ยวกับ recording กลับไป:
   - `TranscriptionService.swift` — เมธอด `transcribeSamples(_:language:)` และ `loadSamples(from:)`
   - `AppState.swift` — source `.recording`, status `.recording/.finalizingRecording`,
     `isRecording/isFinalizing/recordingError`, `startRecording/beginRecording/stopRecording`,
     guard `!isRecording` ใน processQueueIfNeeded/workLoop/loadModel
   - `ContentView.swift` — ปุ่ม "อัดการประชุม" ใน header, struct `RecordingBar`, alert ของ recordingError
   - `JobListView.swift` — case `.recording/.finalizingRecording` ใน JobRow + เมนู "แสดงไฟล์เสียงใน Finder"
   - `TranscriptView.swift` — placeholder ของ case `.recording/.finalizingRecording`
   - `main.swift` (V2TCLI) — โหมด `--simulate-live`
3. เพิ่ม `NSMicrophoneUsageDescription` กลับเข้า `Resources/Info.plist`
