# Linko app identity

## 27 ตุลาคม 2026 — ไอคอนเต็มพื้นที่แบบ Settings

รุ่น `1.0.2+3` เพิ่ม Android Adaptive Icon เพื่อให้พื้นแดงเต็มวงหรือทรงที่ launcher เลือก ไม่ย่อรูปเป็นสี่เหลี่ยมเล็กบนแผ่นวงกลมสีขาว

- `linko-adaptive-source.png`: ภาพเต็มพื้นแดงที่เลือกจาก built-in `imagegen` สำหรับรอบนี้ เก็บต้นฉบับเดิม `linko-icon-source.png` ไว้ด้วย
- Android 8 ขึ้นไปใช้ `mipmap-anydpi-v26/ic_launcher.xml` แยกพื้นหลังสี `#C92847` กับชั้นภาพ สัญลักษณ์มี inset 6dp เพื่ออยู่ในพื้นที่ปลอดภัยของกรอบ 108dp
- `drawable-nodpi/ic_launcher_artwork.png` เป็นภาพ 432px ที่ส่งออกจากต้นฉบับ โดยคงขอบและรูปทรงของโลโก้
- `android:icon` และ `android:roundIcon` อ้างอิง adaptive resource เดียวกัน ส่วน Android รุ่นเก่ายังมี PNG ใน `mipmap-*` เป็น fallback
- สคริปต์ส่งออกใช้ต้นฉบับรอบนี้กับทุกขนาดเดิม เพื่อให้ภาพแบรนด์ของ Android, iOS/macOS, Windows และเว็บสอดคล้องกัน

แนวทางเรื่องขนาดชั้นภาพและ viewport อ้างอิง [Android Adaptive Icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)

### Prompt ของต้นฉบับรอบนี้

ใช้ built-in `imagegen` แบบ edit อ้างอิงภาพแบรนด์เดิม ไม่ใช้ API/CLI fallback:

```text
Use case: logo-brand. Create one clean final square Linko app icon master based closely on the reference. Full-bleed perfectly flat SOLID raspberry red #C92847 covering the entire square, including all four corners, NO circular plate, NO surrounding white margin. At center, the same recognizable interlocking rounded white chain-link L symbol as the reference: tall upright rounded link upper-left interlocked with a horizontal rounded link lower-right, distinctive separated open ends. Redraw with smooth exact geometric curves, consistent warm-white #FFF9FA solid strokes and impeccably clean negative spaces. All holes/gaps show exactly the solid red background. Absolutely no speckles, grain, texture, gradients, shadows, glow, ragged edges, border, frame, words, letters, mockup or phone. Composition for Android adaptive icons: the complete symbol fits within the central 52 percent of canvas width and 56 percent of canvas height, centered optically; leave remaining canvas entirely solid red. The Android system crops the outer red area to a circle, so do not bake a circular boundary into this square image. This is an OPAQUE full-color production icon, not a transparent cutout. Return a single clean square production icon only.
```

หมายเหตุ: ทดลองแยกภาพโปร่งใสแล้วมี noise ในช่องโลโก้ จึงไม่ใช้ผลเหล่านั้น ภาพที่นำเข้าโปรเจกต์เป็นต้นฉบับพื้นแดงคมชัดและกำหนดพื้นที่ตัดด้วย Android resource

---

ไอคอนสื่อถึงการเชื่อมต่อของสมาชิก ใช้ห่วงสีขาวที่ประกอบเป็นรูปทรงคล้ายตัว L บนพื้นสีแดงราสป์เบอร์รีที่เข้ากับธีม Linko

- `linko-icon-source.png`: ต้นฉบับที่สร้างด้วยเครื่องมือ imagegen แบบ built-in เมื่อ 24 ตุลาคม 2026
- `linko-icon.png`: ไฟล์พร้อมใช้ขนาด 1024 × 1024 พิกเซล RGB ไม่มี alpha
- ไฟล์ขนาดย่อย: Android `mipmap-*`, iOS/macOS `AppIcon.appiconset`, เว็บ `web/icons` และ Windows `app_icon.ico`

ส่งออกทุกขนาดซ้ำบน Windows ด้วยคำสั่งนี้ โดยไม่ต้องเรียกบริการสร้างภาพใหม่:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/generate_app_icons.ps1
```

สคริปต์ย่อขนาดและแปลงรูปแบบไฟล์จากต้นฉบับเดียวกัน ไม่เปลี่ยนรูปทรงของสัญลักษณ์ ไฟล์ต้นฉบับอยู่ใน Git และไม่ได้เพิ่มเข้า Flutter asset bundle เพราะแต่ละแพลตฟอร์มอ่านไฟล์ไอคอนจากโฟลเดอร์ของตนเอง

เปลี่ยนเฉพาะชื่อที่ผู้ใช้เห็นเป็น **Linko** และเพิ่มเวอร์ชันเป็น `1.0.1+2`; รหัสแอป Android `com.example.social_app`, Bundle IDs, ชื่อ Dart package และคีย์บันทึกการตั้งค่ายังคงเดิมเพื่อรองรับการอัปเดต

## Prompt ของภาพที่เลือกใช้

```text
Use case: logo-brand.
Asset type: final launcher icon master for Linko, a friendly social network app. Create ONE square 1024x1024 production icon, not a mockup or presentation sheet.
Primary request: a confident, memorable white connection mark built from two thick interlocking rounded links arranged into an abstract L: one upright link at upper left and one horizontal link at lower right, visually joined into one balanced compact symbol. Friendly rounded geometry, generous simple negative space, strong readability at 24 pixels.
Scene/backdrop: solid full-bleed rich raspberry crimson #C92847, matching Linko's existing interface accent. Flat opaque color all the way to all four square edges.
Subject color: warm white #FFF9FA, perfectly crisp edges and consistent thick strokes.
Composition: centered; the entire symbol fits within the central 60 percent of the square, with generous equal surrounding space so circular and rounded-square operating-system masks never clip the mark. Fill the complete canvas with the background; no pre-rounded exterior corners.
Style: polished minimal geometric brand symbol, flat vector-like finish rendered as PNG. A fresh recognizable mark conveying people connecting, with a clear abstract L silhouette.
Constraints: no wordmark, no text, no letters written separately, no watermark, no phone frame, no grid, no alternative designs, no outer border, no gradients, no shadows, no 3D, no texture, no existing brand logo.
```
