# Voice2Text 🎙️

แอป Mac สำหรับถอดเสียงจากไฟล์เสียงหรือวิดีโอเป็นข้อความ — ทำงานในเครื่อง 100% ไม่ส่งข้อมูลขึ้นอินเทอร์เน็ต

🌐 **เว็บดาวน์โหลด:** https://voice2textz.netlify.app/ (อัปเดตโดยลาก `Voice2Text-website.zip` ตัวใหม่ไปวางที่แท็บ Deploys บน Netlify)

- เอนจิ้น: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML) รันบน Neural Engine ของชิป Apple Silicon → เบาเครื่อง กินไฟต่ำ
- **ถอดตามภาษาต้นทางอัตโนมัติ** — เสียงภาษาไหนก็ถอดเป็นภาษานั้น (ตรวจจับเอง แสดงภาษาที่พบในรายการงาน) รองรับไทยปนอังกฤษ (โมเดลเริ่มต้น: Whisper large-v3 turbo แบบ quantized ~630MB)
- **แปลภาษาในตัว** — เลือกภาษาปลายทางได้ 30+ ภาษา ผ่าน Apple Translation (แปลในเครื่อง ไม่ส่งข้อมูลออก) ดูแบบต้นฉบับ/คำแปล/สองภาษาคู่กัน
- **ส่งต่อให้ AI** — ปุ่ม "ส่งให้ AI" คัดลอก transcript แล้วเปิด NotebookLM / ChatGPT / Gemini / Claude ให้วางต่อทันที
- รองรับไฟล์: mp3, wav, m4a, aac, flac, aiff, caf, mp4, mov, m4v
- **รองรับลิงก์ YouTube / วิดีโอออนไลน์** — วางลิงก์ในช่องแล้วกด Enter (ใช้ yt-dlp ซึ่งแอปติดตั้งให้อัตโนมัติครั้งแรก, ดึงเฉพาะเสียงเพื่อประหยัดเน็ตและเวลา)
- Export: คัดลอก / .txt / .srt (ใช้ทำซับวิดีโอได้)

## วิธี build

```bash
./scripts/build-app.sh
open build/Voice2Text.app
```

ต้องมี Xcode (หรืออย่างน้อย Command Line Tools + Swift 5.10 ขึ้นไป) และ macOS 15 ขึ้นไป (ฟีเจอร์แปลภาษาใช้ Apple Translation framework)

## การแปลภาษา

1. ถอดเสียงเสร็จแล้ว เลือกภาษาปลายทางที่แถบ "แปลเป็น" ด้านล่าง แล้วกดปุ่มแปล
2. ครั้งแรกของแต่ละคู่ภาษา ระบบ macOS จะขอดาวน์โหลดแพ็กภาษา (ครั้งเดียว หลังจากนั้นแปลออฟไลน์ได้)
3. สลับมุมมอง ต้นฉบับ / คำแปล / สองภาษา ได้ และปุ่มบันทึก .txt/.srt จะ export ตามมุมมองที่เลือกอยู่ (.srt สองภาษา = ซับคู่)

## การใช้งานครั้งแรก

เปิดแอปครั้งแรก ระบบจะดาวน์โหลดโมเดล (~630MB) มาเก็บไว้ที่
`~/Library/Application Support/Voice2Text` — หลังจากนั้นทำงานออฟไลน์ตลอด
การโหลดโมเดลเข้าหน่วยความจำครั้งแรกอาจใช้เวลา 1–3 นาที (ระบบกำลัง optimize ให้เข้ากับ Neural Engine) ครั้งถัดไปจะเร็วขึ้นมาก

## เครื่องมือทดสอบผ่าน Terminal

```bash
swift build                                 # build แบบ debug
.build/debug/v2t <ไฟล์>                     # ถอดเสียงด้วยโมเดล tiny (ทดสอบเร็ว)
.build/debug/v2t <ไฟล์> --model openai_whisper-large-v3-v20240930_626MB --lang th
.build/debug/v2t "https://www.youtube.com/watch?v=..."   # ถอดจากลิงก์ได้ด้วย
.build/debug/v2t --list-models              # ดูรายชื่อโมเดลทั้งหมด
```

## โครงสร้างโปรเจกต์

```
Sources/
├── Voice2TextCore/        # ส่วนกลาง ใช้ร่วมกันระหว่างแอปและ CLI
│   ├── TranscriptionService.swift   # จัดการโมเดล + ถอดเสียง (WhisperKit)
│   ├── MediaDownloader.swift        # ดาวน์โหลดจากลิงก์ (yt-dlp / URLSession)
│   ├── MediaConverter.swift         # แยกเสียงจากวิดีโอ (AVFoundation)
│   ├── Exporter.swift               # แปลงเป็น .txt / .srt
│   └── Models.swift
├── Voice2Text/            # แอป SwiftUI
│   ├── Voice2TextApp.swift
│   ├── AppState.swift               # คิวงาน + สถานะโมเดล
│   └── Views/
└── V2TCLI/                # เครื่องมือทดสอบผ่าน Terminal (v2t)
```

## หมายเหตุเรื่องลิงก์

- ลิงก์ YouTube และเว็บวิดีโอส่วนใหญ่ใช้ได้เลย (yt-dlp รองรับกว่าพันเว็บ)
- ลิงก์ไฟล์ตรง เช่น `https://example.com/audio.mp3` ก็ใช้ได้
- บางเว็บที่สตรีมแบบ HLS อาจต้องติดตั้ง ffmpeg เพิ่ม: `brew install ffmpeg`
- โปรดใช้กับคอนเทนต์ที่คุณมีสิทธิ์ใช้งานเท่านั้น

## แผนต่อไป

- แยกผู้พูด (speaker diarization)
- ค้นหาในข้อความ + ไฮไลต์ตามช่วงเวลา
- สรุปประชุมอัตโนมัติ

หมายเหตุ: ฟีเจอร์อัดการประชุม+ถอดสดถูกถอดออกใน v1.2.0 ตามความต้องการผู้ใช้ —
โค้ดเก็บไว้ที่ `archive/phase4-live-recording/` พร้อมวิธีกู้คืนใน RECOVERY.md
