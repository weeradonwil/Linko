// รวมการเรียก Authentication และการบันทึกข้อมูลสมาชิก เพื่อให้หน้าจอไม่เรียก Firebase โดยตรง
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// รวมการเรียก Firebase Authentication และการสร้างเอกสารสมาชิกใน Firestore
/// ไว้ที่เดียว เพื่อไม่ให้หน้าจอต้องจัดการรายละเอียดของ Firebase เอง
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// สตรีมแจ้งสถานะผู้ใช้ปัจจุบัน ใช้ให้ AuthGate สลับหน้าตามการเข้าสู่ระบบ
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// สร้างบัญชีด้วยอีเมลและรหัสผ่าน แล้วสร้างโปรไฟล์เริ่มต้นที่ users/{uid}
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;

    if (user == null) {
      throw const AuthServiceException('สร้างบัญชีไม่สำเร็จ กรุณาลองใหม่');
    }

    //บัญชีผู้ใช้ ใช้ Firebase Authentication สมัครและเข้าสู่ระบบ
    //ส่วนข้อมูลโปรไฟล์เริ่มต้นบันทึกใน users/{uid}
    final cleanName = name.trim();
    await user.updateDisplayName(cleanName);

    try {
      // Schema ของ users/{uid}:
      // - uid ใช้ระบุบัญชีและตรวจสิทธิ์ใน Firestore Rules
      // - displayName เป็นชื่อที่แสดงในแอป ไม่ใช่อีเมลสำหรับล็อกอิน
      // - isPrivate เก็บค่าการมองเห็นโปรไฟล์
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'displayName': cleanName,
        'displayNameLower': cleanName.toLowerCase(),
        'isPrivate': false,
        //คือเวลาที่สร้างโพสต์ ใช้เรียงฟีดและแสดงวัน/เวลา
        'createdAt': FieldValue.serverTimestamp(),
        //คือเวลาแก้ไขโพสต์ล่าสุด ตอนสร้างจะตั้งค่าไว้พร้อมกัน แต่เมื่อแก้โพสต์จะเปลี่ยนเฉพาะ updatedAt
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // บัญชี Auth ถูกสร้างก่อนแล้ว แต่การเขียน Firestore อาจถูกปฏิเสธ เช่น Rules
      // ไม่อนุญาตให้ uid ปัจจุบันสร้าง users/{uid}; แยกข้อความนี้จาก Auth error
      // เพื่อให้รู้ว่าบัญชีอาจมีอยู่ แม้เอกสารโปรไฟล์จะยังบันทึกไม่สำเร็จ
      throw const AuthServiceException(
        'สร้างบัญชีแล้ว แต่บันทึกโปรไฟล์ไม่สำเร็จ กรุณาตรวจ Firestore Rules และลองเข้าสู่ระบบอีกครั้ง',
      );
    }
  }

  /// เข้าสู่ระบบด้วยอีเมลและรหัสผ่านที่ Firebase Authentication ตรวจสอบให้
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// ออกจากระบบ; AuthGate จะตรวจพบสถานะใหม่และกลับไปหน้าเข้าสู่ระบบ
  Future<void> signOut() => _auth.signOut();
}

/// ข้อผิดพลาดที่แปลงเป็นข้อความภาษาไทยและแสดงให้ผู้ใช้เข้าใจได้
class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
