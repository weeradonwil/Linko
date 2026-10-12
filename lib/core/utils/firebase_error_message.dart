import 'package:firebase_core/firebase_core.dart';

/// แปลง Firebase error code เป็นข้อความสั้นพร้อมแนวทางตรวจสาเหตุเบื้องต้น
/// permission-denied มักเกิดเมื่อ Firestore Rules ยังไม่ได้ Publish
String firebaseErrorMessage(Object? error, {required String action}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '$actionไม่สำเร็จ: Firestore ปฏิเสธสิทธิ์ กรุณา Deploy firestore.rules ของโปรเจกต์นี้';
      case 'failed-precondition':
        return '$actionไม่สำเร็จ: เงื่อนไข Firestore ยังไม่พร้อม (ตรวจสอบ index ที่ต้องใช้)';
      case 'unavailable':
        return '$actionไม่สำเร็จ: เชื่อมต่อ Firebase ไม่ได้ กรุณาตรวจอินเทอร์เน็ต';
      case 'unauthenticated':
        return '$actionไม่สำเร็จ: กรุณาเข้าสู่ระบบใหม่';
      default:
        return '$actionไม่สำเร็จ (${error.code})';
    }
  }
  return '$actionไม่สำเร็จ';
}
