// แปลง error code จาก Firebase ให้เป็นข้อความอ่านง่ายสำหรับแสดงในแอป
import 'package:firebase_core/firebase_core.dart';

/// แปลง Firebase error code เป็นข้อความสั้นพร้อมแนวทางตรวจสาเหตุเบื้องต้น
/// แยกปัญหาสิทธิ์ เครือข่าย และเซสชัน โดยไม่คาดเดาว่าต้อง deploy เสมอ
String firebaseErrorMessage(Object? error, {required String action}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
        return '$actionไม่สำเร็จ: ไม่มีสิทธิ์เข้าถึงข้อมูลนี้';
      case 'failed-precondition':
        return '$actionไม่สำเร็จ: เงื่อนไข Firestore ยังไม่พร้อม (ตรวจสอบ index ที่ต้องใช้)';
      case 'unavailable':
      case 'retry-limit-exceeded':
        return '$actionไม่สำเร็จ: เชื่อมต่อ Firebase ไม่ได้ กรุณาตรวจอินเทอร์เน็ต';
      case 'unauthenticated':
        return '$actionไม่สำเร็จ: กรุณาเข้าสู่ระบบใหม่';
      default:
        return '$actionไม่สำเร็จ (${error.code})';
    }
  }
  return '$actionไม่สำเร็จ';
}
