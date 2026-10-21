// อ่านคิวรายงานโพสต์และบันทึกผลการตรวจของผู้ดูแลลง Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// จัดการรายงานค้างตรวจ; สิทธิ์ผู้ดูแลบังคับอีกชั้นด้วย admin claim ใน Firestore Rules
class ReportService {
  ReportService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// ฟังเฉพาะรายงานที่ยังเปิดอยู่ โดยให้รายการใหม่แสดงก่อน
  Stream<QuerySnapshot<Map<String, dynamic>>> watchOpenReports() => _firestore
      .collection('post_reports')
      .where('status', isEqualTo: 'open')
      .orderBy('createdAt', descending: true)
      .snapshots();

  /// ปิดรายงานด้วยสถานะที่รองรับ พร้อมผู้ตรวจและเวลาจาก server สำหรับตรวจสอบย้อนหลัง
  Future<void> closeReport({
    required String reportId,
    required String status,
  }) async {
    if (!{'resolved', 'dismissed', 'removed'}.contains(status)) {
      throw const ReportServiceException('Unsupported report status.');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const ReportServiceException('Sign in first.');
    await _firestore.collection('post_reports').doc(reportId).update({
      'status': status,
      'reviewedBy': uid,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }
}

class ReportServiceException implements Exception {
  const ReportServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
