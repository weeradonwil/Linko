import 'package:cloud_functions/cloud_functions.dart';
// แปลง error code จาก Firebase ให้เป็นข้อความอ่านง่ายสำหรับแสดงในแอป
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// แปลง Firebase error code เป็นข้อความสั้นพร้อมแนวทางตรวจสาเหตุเบื้องต้น
/// แยกปัญหาสิทธิ์ เครือข่าย และเซสชัน โดยไม่คาดเดาว่าต้อง deploy เสมอ
String firebaseErrorMessage(Object? error, {required String action}) {
  // แอปที่ Hot Reload หลังเพิ่มปลั๊กอินยังใช้ native ตัวเก่า ต้องติดตั้ง build ใหม่
  if (error is MissingPluginException) {
    return '$actionไม่สำเร็จ: ส่วนประกอบแอปยังไม่พร้อม กรุณาอัปเดตแอปแล้วเปิดใหม่';
  }
  // ข้อความจาก callable เป็นกติกาของแอป เช่น บล็อกกันหรือยังอยู่ในช่วงพักโพสต์
  if (error is FirebaseFunctionsException &&
      error.message?.isNotEmpty == true) {
    return error.message!;
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
        if (error.plugin == 'firebase_storage') {
          return '$actionไม่สำเร็จ: Firebase Storage ปฏิเสธการอัปโหลดไฟล์ (ตรวจ Storage Rules, ชนิดไฟล์ และขนาดไฟล์)';
        }
        if (error.plugin == 'cloud_firestore') {
          return '$actionไม่สำเร็จ: Firestore ปฏิเสธข้อมูลนี้ กรุณาตรวจสิทธิ์บัญชีและเงื่อนไขโพสต์ หากยังเกิดซ้ำให้แจ้งผู้ดูแล (permission-denied)';
        }
        // Firestore และ Storage ใช้รหัสสิทธิ์ต่างกัน; รหัสนี้ยังบอกไม่ได้ว่า deploy ขาด
        return '$actionไม่สำเร็จ: ไม่มีสิทธิ์เข้าถึงข้อมูลนี้';
      case 'failed-precondition':
        return '$actionไม่สำเร็จ: เงื่อนไข Firestore ยังไม่พร้อม (ตรวจสอบ index ที่ต้องใช้)';
      case 'unavailable':
      case 'retry-limit-exceeded':
        // รวมกรณี Storage ลองเชื่อมต่อซ้ำจนครบกำหนดไว้ในกลุ่มปัญหาเครือข่าย
        return '$actionไม่สำเร็จ: เชื่อมต่อ Firebase ไม่ได้ กรุณาตรวจอินเทอร์เน็ต';
      case 'unauthenticated':
        return '$actionไม่สำเร็จ: กรุณาเข้าสู่ระบบใหม่';
      default:
        return '$actionไม่สำเร็จ (${error.code})';
    }
  }
  return '$actionไม่สำเร็จ';
}
