import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// งานที่ผู้ใช้ห้ามปลอมผลเองจะเรียก backend เช่น นับรายงานและออกใบอนุญาตโพสต์
class TrustedService {
  static FirebaseFunctions functionsFor([FirebaseApp? app]) {
    final value = FirebaseFunctions.instanceFor(
      app: app,
      region: 'asia-southeast1',
    );
    const host = String.fromEnvironment('FUNCTIONS_EMULATOR_HOST');
    if (host.isNotEmpty) value.useFunctionsEmulator(host, 5001);
    return value;
  }

  static Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data, {
    FirebaseApp? app,
  }) async {
    final result = await functionsFor(app)
        .httpsCallable(name)
        .call<Map<String, dynamic>>(data);
    return result.data;
  }

  /// เปิดหลังย้ายข้อมูลเก่าเสร็จแล้ว Rules ใช้ flag เดียวกันและผู้ใช้เปลี่ยนไม่ได้
  static Future<DocumentReference<Map<String, dynamic>>?> reserve(
    FirebaseFirestore db,
    String path,
  ) async {
    final config = await db.doc('app_config/security').get();
    if (config.data()?['writeTicketsRequired'] != true) return null;
    final result = await call('reserveWrite', {'path': path}, app: db.app);
    return db.collection('write_tickets').doc(result['ticketId'] as String);
  }
}
