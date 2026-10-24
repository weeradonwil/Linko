// โหลดวิดีโอด้วย Firebase SDK ให้ Rules ตรวจบัญชีปัจจุบันก่อนส่งข้อมูลให้ตัวเล่น
import 'package:firebase_storage/firebase_storage.dart';

import 'authenticated_video_handle.dart';
import 'authenticated_video_io.dart'
    if (dart.library.js_interop) 'authenticated_video_web.dart'
    as platform;
export 'authenticated_video_handle.dart';

/// ใช้ไฟล์ชั่วคราวบนมือถือและ Blob เฉพาะหน้าเว็บ แทนการแจก download URL อายุยาว
Future<AuthenticatedVideo> loadAuthenticatedVideo(Reference reference) =>
    platform.loadVideo(reference);
