// เลือกหน้าเข้าสู่ระบบหรือหน้าหลัก ซ่อมโปรไฟล์ และล้างข้อมูลเมื่อเปลี่ยนบัญชี
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/widgets/post_media.dart';
import '../../core/widgets/auth_session_boundary.dart';
import '../home/home.dart';
import '../login/login.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _service = AuthService();
  late final _authStates = _service.authStateChanges;
  Future<void>? _profileReady;
  String? _lastUid;
  bool _observedInitialState = false;

  /// เตรียมโปรไฟล์ครั้งเดียวต่อบัญชี โดยไม่เริ่มคำขอซ้ำทุกครั้งที่วาดหน้าจอ
  void _observeUser(User? user) {
    if (_observedInitialState && _lastUid == user?.uid) return;
    _observedInitialState = true;
    _lastUid = user?.uid;
    _profileReady = user == null ? null : _service.ensureProfile(user);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _authStates,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text('ตรวจสอบสถานะบัญชีไม่สำเร็จ กรุณาเปิดแอปอีกครั้ง'),
          ),
        );
      }
      final user = snapshot.data;
      _observeUser(user);
      return AuthSessionBoundary(
        sessionId: user?.uid,
        onSessionChanged: PostMedia.clearCache,
        child: user == null
            ? const LoginScreen()
            : FutureBuilder<void>(
                future: _profileReady,
                builder: (context, profile) {
                  if (profile.hasError) {
                    return Scaffold(
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'เตรียมโปรไฟล์ไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วลองอีกครั้ง',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => setState(() {
                                  _profileReady = _service.ensureProfile(user);
                                  // ป้องกัน error หลุดก่อน FutureBuilder แนบ listener ในเฟรมใหม่
                                  _profileReady!.ignore();
                                }),
                                child: const Text('ลองอีกครั้ง'),
                              ),
                              TextButton(
                                onPressed: _service.signOut,
                                child: const Text('ออกจากระบบ'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (profile.connectionState != ConnectionState.done) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return HomeScreen(user: user);
                },
              ),
      );
    },
  );
}
