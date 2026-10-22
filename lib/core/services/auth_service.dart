// รวมการเรียก Authentication และการบันทึกข้อมูลสมาชิก เพื่อให้หน้าจอไม่เรียก Firebase โดยตรง
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/document_values.dart';

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
      await ensureProfile(user, displayName: cleanName);
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
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (credential.user != null) await ensureProfile(credential.user!);
  }

  /// Repairs missing/legacy profiles transactionally. It is safe for AuthGate
  /// and registration to call this concurrently without resetting privacy.
  Future<void> ensureProfile(User user, {String? displayName}) async {
    final reference = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final storedName = readString(data['displayName']).trim();
      final candidate =
          displayName ??
          (storedName.isNotEmpty ? storedName : user.displayName ?? 'สมาชิก');
      final name = boundedString(
        candidate.trim().isEmpty ? 'สมาชิก' : candidate.trim(),
        60,
      );
      final desired = <String, dynamic>{
        'uid': user.uid,
        'displayName': name,
        'displayNameLower': boundedString(name.toLowerCase(), 60),
        'bio': boundedString(readString(data['bio']), 160),
        'isPrivate': data['isPrivate'] == true,
        if (data['createdAt'] is! Timestamp)
          'createdAt': FieldValue.serverTimestamp(),
      };
      final updates = <String, dynamic>{
        for (final entry in desired.entries)
          if (data[entry.key] != entry.value) entry.key: entry.value,
      };
      if (data.containsKey('avatarPath') &&
          (data['avatarPath'] is! String ||
              !RegExp('^profile_images/${RegExp.escape(user.uid)}/[^/]+\$')
                  .hasMatch(data['avatarPath'] as String))) {
        updates['avatarPath'] = FieldValue.delete();
      }
      if (data.containsKey('privacyTarget') && data['privacyTarget'] is! bool) {
        updates['privacyTarget'] = FieldValue.delete();
      }
      if (updates.isEmpty) return;
      updates['updatedAt'] = FieldValue.serverTimestamp();
      transaction.set(reference, updates, SetOptions(merge: true));
    });
  }

  /// ขอให้ Firebase Auth ส่งลิงก์รีเซ็ตรหัสผ่านไปยังอีเมลที่ระบุ
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

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
