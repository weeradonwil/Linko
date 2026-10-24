# Linko app identity

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
