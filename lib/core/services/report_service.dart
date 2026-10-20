import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reads and closes the moderation queue; Firestore Rules restrict this to admins.
class ReportService {
  ReportService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOpenReports() => _firestore
      .collection('post_reports')
      .where('status', isEqualTo: 'open')
      .orderBy('createdAt', descending: true)
      .snapshots();

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
