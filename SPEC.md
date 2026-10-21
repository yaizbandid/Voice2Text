# Voice2Text — Spec ฟีเจอร์ "วิเคราะห์คลิป" (Clip Analysis)

> สถานะ: Draft v0.1 · 2026-10-20 · branch `feature/clip-analysis`
> แผนเป็นเฟสอยู่ที่ [ROADMAP.md](ROADMAP.md)

## 1. เป้าหมาย

เพิ่มแท็บใหม่ในแอป Voice2Text (แยกจากหน้าถอดเสียงเดิม) สำหรับ

1. ดึงข้อมูลคลิปจาก **YouTube (วิดีโอยาว), YouTube Shorts และ Instagram Reels** — ยอดวิว ไลก์ คอมเมนต์ ผู้ติดตาม
2. วิเคราะห์โครงสร้างคลิป — Hook / Body (การเล่าเรื่อง) / CTA, ความเร็วการพูด, อารมณ์
3. เก็บผลเป็น **คลัง** แล้วสรุปสถิติ — รูปแบบไหนพบบ่อยกี่ % และได้ engagement เท่าไร
4. ให้ผู้ใช้ **Approve** ผลวิเคราะห์ เพื่อใช้เป็นแกนอ้างอิงในการวิเคราะห์ครั้งถัดไป (Playbook)
5. ปุ่ม **Generate Script** — ใส่หัวข้อ แล้วได้สคริปต์ตามโครงสร้างต้นแบบ

### ไม่อยู่ในขอบเขต (ตอนนี้)
- TikTok, Facebook
- วิเคราะห์ภาพในคลิป (การตัดต่อ, ตัวหนังสือบนจอ) และอารมณ์จากน้ำเสียงจริง → เฟสหลัง
- โพสต์คลิป/สคริปต์ขึ้นแพลตฟอร์ม

## 2. หลักการออกแบบ

| หลักการ | รายละเอียด |
|---|---|
| ถอดเสียงยังทำในเครื่อง | ใช้ `TranscriptionService` (WhisperKit) ตัวเดิม ไม่ส่งไฟล์เสียงขึ้นคลาวด์ |
| ส่งขึ้นคลาวด์เฉพาะ "ข้อความ" | LLM ได้รับเฉพาะ transcript + metadata เท่านั้น — ถูกและเร็ว |
| ประเภทต้องตายตัว (Taxonomy) | AI ต้องเลือกจากรายการที่กำหนด เพื่อให้นับสถิติได้ — เพิ่มประเภทใหม่ได้ผ่านการ Approve เท่านั้น |
| คน Approve ก่อนเป็นแกน | ผลที่ยังไม่ Approve ไม่ถูกใช้เป็นตัวอย่างอ้างอิง และแยกแสดงในสถิติ |
| เปลี่ยนผู้ให้บริการ AI ได้ | `LLMProvider` protocol — Gemini เป็นค่าเริ่มต้น, DeepSeek / Qwen เสียบเพิ่มได้ |
| ไม่เพิ่ม dependency ถ้าไม่จำเป็น | เก็บข้อมูลเป็นไฟล์ JSON, เรียก API ด้วย `URLSession` |

## 3. ภาพรวมการทำงาน

```
ลิงก์คลิป / ลิงก์ช่อง (หลายคลิป)
   │
   ├─▶ 1. MetadataFetcher   yt-dlp -J --skip-download  → ยอดวิว ไลก์ คอมเมนต์ ฯลฯ
   ├─▶ 2. MediaDownloader    (ของเดิม) ดึงเฉพาะเสียง
   ├─▶ 3. TranscriptionService (ของเดิม) + word timestamps
   ├─▶ 4. SpeechMetrics      คำนวณในเครื่อง: ความเร็วพูด ช่วงเงียบ เวลาเข้าเรื่อง
   ├─▶ 5. ClipAnalyzer       LLM + Taxonomy + ตัวอย่างที่ Approve แล้ว → JSON
   │
   ▼
ClipRecord (status: pendingReview)
   │  ผู้ใช้ตรวจ แก้ไข → Approve / Reject
   ▼
คลัง (Library) ──▶ สถิติ (Insights) ──▶ Generate Script
          └──▶ Playbook (Taxonomy + ตัวอย่างอ้างอิง) ──▶ ใช้ในการวิเคราะห์ครั้งถัดไป
```

## 4. โครงสร้างโค้ด

เพิ่ม target ใหม่ใน `Package.swift` แยกจากของเดิม เพื่อไม่ให้กระทบหน้าถอดเสียง

```
Sources/
├── Voice2TextCore/            # ของเดิม (แก้เล็กน้อย: เปิด wordTimestamps)
├── ClipAnalysisCore/          # ใหม่ — ไม่มี UI, ทดสอบผ่าน CLI ได้
│   ├── Models/
│   │   ├── ClipRecord.swift          # ข้อมูลคลิป 1 ตัว (metadata + transcript + analysis + review)
│   │   ├── ClipMetrics.swift         # ยอดวิว ไลก์ ฯลฯ + engagement ที่คำนวณแล้ว
│   │   ├── ClipAnalysis.swift        # ผลวิเคราะห์โครงสร้าง (ตรงกับ JSON schema ข้อ 7)
│   │   ├── Taxonomy.swift            # ประเภท Hook / Body / CTA / อารมณ์ (มีเวอร์ชัน)
│   │   └── GeneratedScript.swift
│   ├── Fetch/
│   │   ├── MetadataFetcher.swift     # yt-dlp -J, --flat-playlist สำหรับลิงก์ช่อง
│   │   └── PlatformDetector.swift    # youtube / shorts / reels จาก URL
│   ├── Metrics/
│   │   └── SpeechMetrics.swift       # WPM, ช่วงเงียบ, ตัดคำไทยด้วย NLTokenizer
│   ├── LLM/
│   │   ├── LLMProvider.swift         # protocol + ข้อผิดพลาด + การนับ token/ค่าใช้จ่าย
│   │   ├── GeminiProvider.swift      # Gemini API (responseSchema = JSON)
│   │   └── OpenAICompatibleProvider.swift  # DeepSeek / Qwen (OpenAI-compatible endpoint)
│   ├── Analysis/
│   │   ├── ClipAnalyzer.swift        # ประกอบ prompt + ตรวจ JSON + retry
│   │   ├── PromptBuilder.swift       # ใส่ Taxonomy + ตัวอย่างที่ Approve
│   │   └── ScriptGenerator.swift
│   ├── Store/
│   │   ├── LibraryStore.swift        # อ่าน/เขียน JSON ใน Application Support
│   │   └── KeychainStore.swift       # เก็บ API key
│   └── Insights/
│       └── InsightsEngine.swift      # สรุป % และ engagement ตามประเภท
├── Voice2Text/
│   ├── Voice2TextApp.swift    # เปลี่ยนเป็น TabView: ถอดเสียง | วิเคราะห์คลิป
│   └── Views/
│       ├── (ของเดิม)
│       └── Analysis/
│           ├── AnalysisRootView.swift    # sidebar: วิเคราะห์ใหม่ / คลัง / สถิติ / Playbook / สร้างสคริปต์
│           ├── AnalyzeInputView.swift
│           ├── ClipDetailView.swift      # timeline Hook/Body/CTA + ปุ่ม Approve
│           ├── LibraryView.swift
│           ├── InsightsView.swift        # ใช้ Swift Charts
│           ├── PlaybookView.swift
│           └── ScriptGeneratorView.swift
└── V2TCLI/                    # เพิ่มคำสั่ง: v2t analyze <url>, v2t meta <url>
```

## 5. การดึงข้อมูลจากแพลตฟอร์ม

### 5.1 คำสั่ง
- คลิปเดียว: `yt-dlp -J --skip-download --no-warnings <url>`
- ลิงก์ช่อง/เพลย์ลิสต์: `yt-dlp --flat-playlist -J --playlist-end <N> <url>` → ได้รายการ id แล้ววนดึงทีละคลิป
  - Shorts ของช่อง: `https://www.youtube.com/@<handle>/shorts`
- (ทางเลือก) คอมเมนต์: `--write-comments --extractor-args "youtube:max_comments=100"`

### 5.2 ฟิลด์ที่ใช้

| ฟิลด์ yt-dlp | ใช้เป็น | YouTube | Reels |
|---|---|---|---|
| `view_count` | ยอดวิว | ✅ | ⚠️ บางครั้งไม่มี |
| `like_count` | ไลก์ | ✅ (ถ้าเจ้าของไม่ซ่อน) | ⚠️ |
| `comment_count` | คอมเมนต์ | ✅ | ⚠️ |
| `channel_follower_count` | ผู้ติดตาม | ✅ | ⚠️ |
| `duration` | ความยาว (วินาที) | ✅ | ✅ |
| `upload_date` | วันโพสต์ | ✅ | ✅ |
| `title`, `description`, `tags` | ส่งให้ LLM เป็นบริบท | ✅ | ✅ (caption) |
| `channel`, `uploader_id` | กรองตามช่อง | ✅ | ✅ |

ทดสอบแล้ว (2026-10-20, yt-dlp 2026.08.19): YouTube คืนค่า view/like/comment/follower/duration ครบ

**Instagram Reels:** มักต้องใช้คุกกี้ของเบราว์เซอร์ที่ล็อกอินแล้ว
→ ตั้งค่าในแอป: เลือกเบราว์เซอร์ แล้วส่ง `--cookies-from-browser <chrome|safari|...>` (ผู้ใช้ต้องเปิดเอง ค่าเริ่มต้นปิด)
→ ถ้าค่าใดไม่มี ให้เก็บเป็น `nil` และแสดง "ไม่มีข้อมูล" ห้ามใส่ 0

### 5.3 ค่าที่คำนวณ
- `engagementRate = (likes + comments) / views` (ไม่นับแชร์ เพราะ YouTube ไม่เปิดเผย)
- `viewsPerFollower = views / followers` — คะแนน "คลิปทะลุฐาน" (outlier)
- `ageDays` = วันนี้ − upload_date (คลิปใหม่ยอดยังไม่นิ่ง → ใช้กรองในสถิติ)
- เก็บ `fetchedAt` ทุกครั้ง และดึงซ้ำได้เพื่ออัปเดตตัวเลข

## 6. การวิเคราะห์การพูด (ในเครื่อง ไม่ใช้ AI)

- เปิด `DecodingOptions.wordTimestamps = true` เฉพาะงานวิเคราะห์ (หน้าถอดเสียงเดิมไม่เปลี่ยน)
- ตัดคำไทย/อังกฤษด้วย `NLTokenizer(unit: .word)`

| ค่า | วิธีคำนวณ |
|---|---|
| `wordsPerMinute` | จำนวนคำ ÷ เวลาที่มีเสียงพูด (ไม่นับช่วงเงียบ) |
| `wpmBySection` | WPM แยก Hook / Body / CTA (ใช้ช่วงเวลาจากผล LLM) |
| `pauseCount`, `longestPause` | ช่องว่างระหว่างคำ > 0.6 วินาที |
| `timeToFirstWord` | วินาทีแรกที่เริ่มพูด |
| `paceLabel` | ช้า / ปกติ / เร็ว / เร็วมาก — เกณฑ์ปรับได้ใน Settings (ค่าเริ่มต้นแยกภาษาไทย/อังกฤษ) |

## 7. การวิเคราะห์ด้วย AI

### 7.1 Taxonomy เริ่มต้น (v1)

**Hook**
| key | ชื่อ | ตัวอย่าง |
|---|---|---|
| `question` | ตั้งคำถาม | "รู้ไหมว่า…?" |
| `pain_point` | จี้ปัญหา | "ใครเคยเป็นแบบนี้บ้าง…" |
| `bold_claim` | ประโยคฟันธง | "นี่คือวิธีที่ดีที่สุด…" |
| `statistic` | ตัวเลข/สถิติ | "90% ของคนทำผิด…" |
| `story_open` | เปิดด้วยเรื่องเล่า | "เมื่อวานผมเจอ…" |
| `curiosity_gap` | ชวนสงสัย/ค้างไว้ | "ข้อ 3 คือสิ่งที่ไม่มีใครบอก…" |
| `result_first` | โชว์ผลลัพธ์ก่อน | "จากยอด 0 เป็น 1 ล้าน…" |
| `contrarian` | พูดสวนกระแส | "เลิกทำ X ได้แล้ว" |
| `direct_address` | เรียกกลุ่มเป้าหมาย | "คนที่ทำร้านออนไลน์ ฟังทางนี้" |
| `demonstration` | สาธิตทันที | เริ่มทำให้ดูเลย |
| `other` | อื่น ๆ (ต้องระบุ `proposedLabel`) | |

**Body (โครงการเล่า)**
`listicle` ลิสต์ข้อ ๆ · `problem_solution` ปัญหา→ทางแก้ · `story_arc` เล่าเรื่องมีจุดพีค · `before_after` ก่อน/หลัง · `tutorial_steps` สอนทีละขั้น · `myth_busting` แก้ความเชื่อผิด · `comparison` เปรียบเทียบ · `opinion_rant` แสดงความเห็น · `qa` ถาม-ตอบ · `other`

**CTA**
`follow` กดติดตาม · `comment_prompt` ชวนคอมเมนต์ · `share_save` แชร์/เซฟ · `link_click` คลิกลิงก์ · `buy_product` ซื้อสินค้า · `watch_next` ดูคลิปต่อ · `soft_cta` ชวนแบบอ้อม · `none` ไม่มี CTA · `other`

**อารมณ์ (tone)** — เลือกได้หลายค่าต่อช่วง
`excited` ตื่นเต้น · `urgent` เร่งเร้า · `calm` สงบ · `humorous` ตลก · `empathetic` เข้าใจ/เห็นใจ · `authoritative` น่าเชื่อถือ/ผู้เชี่ยวชาญ · `inspirational` สร้างแรงบันดาลใจ · `controversial` ยั่วให้ถกเถียง · `sad` เศร้า

Taxonomy เก็บใน `taxonomy.json` พร้อม `version` — เพิ่ม/แก้ประเภทจะขึ้นเวอร์ชันใหม่ ผลวิเคราะห์ทุกตัวบันทึกว่าใช้ taxonomy เวอร์ชันไหน

### 7.2 Output schema (ClipAnalysis)

ส่งเป็น `responseSchema` ให้ Gemini (หรือ `response_format: json_object` + ตรวจเองสำหรับ DeepSeek/Qwen)

```json
{
  "language": "th",
  "summary": "สรุปคลิป 1-2 ประโยค",
  "hook": {
    "start": 0.0, "end": 3.2,
    "text": "ข้อความช่วง hook",
    "type": "question",
    "proposedLabel": null,
    "strength": 4,
    "why": "เหตุผลสั้น ๆ ว่าทำไมได้ผล/ไม่ได้ผล"
  },
  "body": {
    "start": 3.2, "end": 48.0,
    "structure": "listicle",
    "beats": [
      { "start": 3.2, "end": 12.0, "label": "ข้อ 1: …", "tone": ["authoritative"] }
    ],
    "storytellingNotes": "วิธีเล่า จังหวะ การเชื่อมแต่ละช่วง"
  },
  "cta": {
    "present": true,
    "start": 48.0, "end": 55.0,
    "text": "…",
    "type": "comment_prompt",
    "placement": "end",
    "strength": 3,
    "why": "…"
  },
  "tone": { "overall": ["excited", "humorous"], "consistency": "สม่ำเสมอ/เปลี่ยนตามช่วง" },
  "strengths": ["…"],
  "improvements": ["…"],
  "reusableTemplate": "โครงแบบนามธรรมที่เอาไปใช้กับหัวข้ออื่นได้ เช่น [คำถามจี้ปัญหา] → [3 ข้อ พร้อมตัวอย่าง] → [ชวนคอมเมนต์ประสบการณ์]"
}
```

กฎตรวจหลังได้ผล (ทำในโค้ด):
- `type` ต้องอยู่ใน taxonomy ปัจจุบัน — ถ้าเป็น `other` ต้องมี `proposedLabel`
- ช่วงเวลาต้องเรียงกันและอยู่ภายใน `duration`
- `strength` 1–5
- ผิดกฎ → ส่งกลับให้แก้ 1 ครั้ง แล้วถ้ายังผิดให้บันทึกเป็น `failed` พร้อมข้อความดิบ

### 7.3 Prompt
ประกอบด้วย
1. บทบาท + คำอธิบาย taxonomy (key, ชื่อ, คำนิยาม, ตัวอย่าง)
2. **ตัวอย่างที่ Approve แล้ว** สูงสุด 3 ตัว (few-shot) — เลือกจากแพลตฟอร์มเดียวกันก่อน แล้วค่อยเป็นตัวที่ engagement สูง
3. metadata (title, description, duration, platform) + transcript พร้อม timestamp ทีละประโยค
4. คำสั่งตอบเป็น JSON ตาม schema เท่านั้น

Prompt template เก็บเป็นไฟล์ (`prompts/analyze.md`, `prompts/script.md`) เพื่อแก้ได้โดยไม่ต้อง build ใหม่

## 8. การ Approve และ Playbook

### 8.1 สถานะของ ClipRecord
```
fetching → transcribing → analyzing → pendingReview ─┬─▶ approved
                                     └─▶ failed      └─▶ rejected
```

### 8.2 หน้าตรวจ (ClipDetailView)
- timeline แถบสี Hook / Body / CTA ทับบน transcript — คลิกที่ช่วงแล้วเห็นข้อความ
- แก้ได้ทุกช่อง: ประเภท, ช่วงเวลา, strength, เหตุผล
- ปุ่ม **Approve**, **Reject**, **วิเคราะห์ใหม่**
- ถ้า AI เสนอ `proposedLabel` ใหม่ จะมีการ์ด "เพิ่มประเภทใหม่: ___" ให้เลือก:
  เพิ่มเป็นประเภทใหม่ / รวมเข้ากับประเภทเดิม / ไม่เพิ่ม

### 8.3 ผลของการ Approve
| สิ่งที่เกิด | รายละเอียด |
|---|---|
| ใช้เป็น few-shot | คลิปที่ Approve เข้าคิวเป็นตัวอย่างอ้างอิงใน prompt ครั้งถัดไป |
| ปักหมุด "ตัวอย่างดีเด่น" | ผู้ใช้เลือกได้เองว่าตัวไหนต้องถูกใช้ก่อนเสมอ |
| เพิ่มประเภทใหม่ | taxonomy ขึ้นเวอร์ชัน → ใช้ทันทีในการวิเคราะห์ครั้งถัดไป |
| สถิติ | ค่าเริ่มต้นนับเฉพาะ `approved` — สลับดู "รวมที่ยังไม่ตรวจ" ได้ |
| แก้ไขจากคน | ถ้าผู้ใช้แก้ผล AI ก่อน Approve จะบันทึก diff ไว้ (`humanEdits`) เพื่อดูภายหลังว่า AI พลาดตรงไหนบ่อย |

### 8.4 หน้า Playbook
- รายการประเภททั้งหมด พร้อมคำนิยาม แก้ไข/รวม/ปิดใช้งานได้
- รายการตัวอย่างอ้างอิง (ปักหมุด/ถอดออก)
- "กฎเพิ่มเติม" แบบข้อความอิสระ เช่น "Hook ของ Shorts นับแค่ 3 วินาทีแรก" → แทรกเข้า prompt

## 9. สถิติ (Insights)

ตัวกรอง: แพลตฟอร์ม · ช่อง · ช่วงวันโพสต์ · อายุคลิปขั้นต่ำ (ค่าเริ่มต้น ≥ 7 วัน) · ความยาว · สถานะ

| การ์ด | แสดง |
|---|---|
| สัดส่วน Hook | % ของแต่ละประเภท + median engagement rate ของประเภทนั้น |
| สัดส่วนโครงเล่า | เหมือนกัน สำหรับ Body |
| CTA | % มี/ไม่มี CTA, ประเภท, ตำแหน่ง vs engagement |
| ความเร็วพูด | กระจายของ WPM vs engagement (scatter) |
| อารมณ์ | tone ที่พบบ่อยในคลิปกลุ่ม engagement สูงสุด 25% |
| สูตรที่ได้ผล | คู่ Hook + Body ที่ median ER สูงสุด (ต้องมีอย่างน้อย 5 คลิปจึงแสดง) |

- ใช้ **median** แทนค่าเฉลี่ย เพราะคลิปไวรัลตัวเดียวดึงค่าเฉลี่ยเพี้ยน
- ทุกการ์ดแสดง `n = จำนวนคลิป` และเตือนเมื่อ n < 10 ว่า "ข้อมูลน้อย ยังสรุปไม่ได้"
- ข้อความที่แสดงให้ชัดว่าเป็น "ในคลังของคุณ" ไม่ใช่ทั้งตลาด

## 10. Generate Script

### Input
| ช่อง | บังคับ | หมายเหตุ |
|---|---|---|
| หัวข้อ / สิ่งที่จะเล่า | ✅ | ข้อความอิสระ |
| ต้นแบบโครงสร้าง | ✅ | (ก) จากคลิปที่เลือก (ข) สูตรที่ได้ผลที่สุดในคลัง (ค) เลือก Hook/Body/CTA เอง |
| แพลตฟอร์ม + ความยาวเป้าหมาย | ✅ | เช่น Shorts 45 วินาที |
| โทน, กลุ่มเป้าหมาย, CTA ที่ต้องการ | — | |
| ภาษา | — | ค่าเริ่มต้น ไทย |

### Output
```json
{
  "title": "ชื่อคลิปที่แนะนำ",
  "hookVariants": ["3 แบบให้เลือก"],
  "sections": [
    { "part": "hook", "seconds": 3, "script": "…", "deliveryNote": "พูดเร็ว เน้นคำว่า…", "onScreenText": "…" },
    { "part": "body", "seconds": 35, "script": "…", "deliveryNote": "…" },
    { "part": "cta",  "seconds": 5, "script": "…" }
  ],
  "estimatedWords": 140,
  "targetWPM": 190
}
```
- จำนวนคำต่อช่วงคำนวณจาก `ความยาวเป้าหมาย × WPM ของต้นแบบ`
- ปุ่ม: สร้างใหม่ · สร้าง Hook ใหม่อย่างเดียว · คัดลอก · บันทึก .txt / .md
- สคริปต์ที่สร้างเก็บไว้ในคลัง (`scripts/`) ผูกกับต้นแบบที่ใช้

## 11. ผู้ให้บริการ AI

### 11.1 Protocol
```swift
public protocol LLMProvider {
    var id: String { get }                       // "gemini", "deepseek", "qwen"
    var model: String { get }
    func generateJSON(system: String, user: String, schema: JSONSchema?) async throws -> LLMResult
}
public struct LLMResult { let text: String; let inputTokens: Int; let outputTokens: Int }
```

### 11.2 ค่าเริ่มต้นและทางเลือก

| ผู้ให้บริการ | โมเดล (ตั้งค่าได้) | ราคา / 1M token (in / out) | จุดเด่น | ข้อควรระวัง |
|---|---|---|---|---|
| **Gemini** (ค่าเริ่มต้น) | `gemini-3.5-flash-lite` | $0.30 / $2.50 | ภาษาไทยดี, มี free tier, รองรับ JSON schema ตรง ๆ | free tier: Google อาจใช้ข้อมูลไปปรับปรุงบริการ |
| Gemini (งานยาก) | `gemini-3.8-flash` | $0.75 / $3.75 (ถึง 31 ธ.ค. 2026) | วิเคราะห์ละเอียดกว่า | ราคาขึ้นเป็น $1.50 / $7.50 ตั้งแต่ 1 ม.ค. 2027 |
| DeepSeek | `deepseek-flash` | ถูกกว่า Gemini (ตรวจราคาบนหน้าเว็บทางการก่อนใช้) | ราคาต่ำมาก, API แบบ OpenAI | ภาษาไทยด้อยกว่า, ข้อมูลประมวลผลที่จีน |
| Qwen (Alibaba) | `qwen3.8-flash` | ~$0.15 / $0.47 (Singapore) | ถูก, JSON mode ดี | ภาษาไทยด้อยกว่า Gemini, ชื่อโมเดลเปลี่ยนบ่อย |

ราคาตรวจเมื่อ 2026-10-20 — ราคาเปลี่ยนบ่อย ให้แอปเก็บราคาไว้ในไฟล์ตั้งค่า (`pricing.json`) ไม่ฝังในโค้ด

**ประมาณการค่าใช้จ่าย** (Shorts 60 วินาที ≈ prompt 4k token + output 1.5k token):
Gemini 3.5 Flash-Lite ≈ $0.005 ต่อคลิป (≈ 0.17 บาท) → 1,000 คลิป ≈ 170 บาท
ตัวเลขจริงแสดงในแอปจาก `inputTokens/outputTokens` ที่ API ส่งกลับ

### 11.3 การตั้งค่า
- เก็บ API key ใน **Keychain** (ไม่เก็บใน UserDefaults / ไฟล์)
- เลือกผู้ให้บริการแยกได้ระหว่าง "วิเคราะห์" กับ "สร้างสคริปต์"
- แสดงยอดใช้จ่ายสะสมรายเดือน (คำนวณจาก token × pricing.json)
- ปุ่ม "ทดสอบการเชื่อมต่อ"

## 12. การเก็บข้อมูล

```
~/Library/Application Support/Voice2Text/
├── (ของเดิม: โมเดล Whisper, bin/yt-dlp)
└── Analysis/
    ├── clips/<clipID>.json       # ClipRecord ครบชุด
    ├── scripts/<scriptID>.json
    ├── taxonomy.json             # Taxonomy + version history
    ├── playbook.json             # ตัวอย่างที่ปักหมุด + กฎเพิ่มเติม
    ├── pricing.json
    └── prompts/                  # override prompt (ถ้ามี)
```
- `clipID` = `<platform>_<videoId>` → วางลิงก์ซ้ำจะอัปเดตตัวเดิม ไม่สร้างซ้ำ
- ทุกไฟล์มี `schemaVersion` สำหรับ migrate ภายหลัง
- ปุ่ม Export คลังเป็น CSV (เปิดใน Google Sheets ได้)

## 13. CLI (สำหรับทดสอบโดยไม่เปิดแอป)
```bash
v2t meta <url>                       # พิมพ์ metadata + engagement
v2t analyze <url> [--provider gemini]  # ถอดเสียง + วิเคราะห์ → JSON
v2t analyze-channel <url> --limit 20
v2t script --topic "..." --from <clipID> --seconds 45
```

## 14. ข้อผิดพลาดที่ต้องรองรับ

| กรณี | การแสดงผล |
|---|---|
| ลิงก์ไม่ใช่ YouTube/Reels | "ยังรองรับเฉพาะ YouTube, Shorts, Reels" |
| Reels ต้องล็อกอิน | แนะนำให้เปิด "ใช้คุกกี้จากเบราว์เซอร์" ใน Settings |
| คลิปไม่มีเสียงพูด / เพลงล้วน | บันทึกเป็น `noSpeech` ไม่ส่งให้ LLM |
| ไม่มี API key / key ผิด | พาไปหน้า Settings |
| API ติด rate limit (429) | รอแล้วลองใหม่แบบ exponential backoff สูงสุด 3 ครั้ง |
| JSON จาก AI ผิด schema | retry 1 ครั้ง → `failed` พร้อมข้อความดิบให้ดู |
| วิเคราะห์ทั้งช่องแล้วบางคลิปพัง | ทำต่อทีละคลิป ไม่หยุดทั้งชุด สรุปท้าย "สำเร็จ x / พัง y" |

## 15. การทดสอบ

- Unit test (`Tests/ClipAnalysisCoreTests`): PlatformDetector, การคำนวณ engagement, SpeechMetrics (ใช้ transcript ปลอม), การตรวจ JSON schema, InsightsEngine
- Fixture: เก็บผล `yt-dlp -J` ตัวอย่างไว้ใน `Tests/Fixtures/` — test ไม่ต้องต่อเน็ต
- LLM: ใช้ `MockLLMProvider` ใน test; มี integration test แยกที่รันเมื่อมี env `GEMINI_API_KEY`
- ทดสอบมือ: Shorts ไทย 5 ตัว, YouTube ยาว 2 ตัว, Reels 3 ตัว

## 16. คำถามที่ยังเปิดอยู่

1. วิดีโอ YouTube ยาว (10+ นาที) — วิเคราะห์ Hook แค่ 30 วินาทีแรก + โครงทั้งคลิป หรือแบ่งเป็นตอน ๆ?
2. ต้องการวิเคราะห์คอมเมนต์ (ความรู้สึกคนดู) ตั้งแต่เฟสแรกไหม หรือเก็บไว้ก่อน?
3. ต้องการซิงก์คลังขึ้น Google Sheets อัตโนมัติไหม หรือ Export CSV ก็พอ?
