import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// หน้านี้รอให้ผู้ใช้กดลิงก์จริง ไม่เชื่อแค่การกดปุ่มว่า "ยืนยันแล้ว"
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.user,
    required this.onVerified,
    this.sendVerification,
    this.checkVerification,
  });
  final User user;
  final VoidCallback onVerified;
  // แยก callback ไว้เพื่อทดสอบปุ่มกับเวลา โดยไม่ต้องส่งอีเมลจริงทุกครั้ง
  final Future<void> Function()? sendVerification;
  final Future<bool> Function()? checkVerification;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _message;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _perform(bool resend) async {
    setState(() => _busy = true);
    try {
      if (resend) {
        if (widget.sendVerification != null) {
          await widget.sendVerification!();
        } else {
          await FirebaseAuth.instance.setLanguageCode('th');
          await widget.user.sendEmailVerification();
        }
        if (!mounted) return;
        setState(() {
          _cooldown = 60;
          _message = 'ส่งลิงก์แล้ว ลองดูในกล่องจดหมายและโฟลเดอร์สแปมด้วยนะ';
        });
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return timer.cancel();
          setState(() => _cooldown--);
          if (_cooldown <= 0) timer.cancel();
        });
      } else {
        bool verified;
        if (widget.checkVerification != null) {
          verified = await widget.checkVerification!();
        } else {
          await widget.user.reload();
          final fresh = FirebaseAuth.instance.currentUser;
          // รีเฟรชทั้งข้อมูลผู้ใช้และ token ให้ Rules เห็นผลยืนยันรอบใหม่
          await fresh?.getIdToken(true);
          verified = fresh?.emailVerified == true;
        }
        if (!mounted) return;
        if (verified) {
          widget.onVerified();
        } else {
          setState(
            () => _message =
                'ยังไม่พบการยืนยัน ลองเปิดลิงก์ในอีเมลแล้วกดตรวจอีกครั้ง',
          );
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.code == 'too-many-requests'
              ? 'ส่งหลายครั้งแล้ว รอสักครู่แล้วลองใหม่นะ'
              : 'ทำรายการไม่สำเร็จ ลองตรวจอินเทอร์เน็ตแล้วทำอีกครั้ง',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ยืนยันอีเมล')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_email_unread_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'เปิดลิงก์ยืนยันในอีเมลของคุณ',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(widget.user.email ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'ยืนยันก่อนเริ่มโพสต์และพูดคุยกัน เพื่อช่วยลดบัญชีปลอมใน Linko',
              textAlign: TextAlign.center,
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _perform(false),
              child: Text(_busy ? 'กำลังตรวจสอบ…' : 'ฉันยืนยันอีเมลแล้ว'),
            ),
            TextButton(
              onPressed: _busy || _cooldown > 0 ? null : () => _perform(true),
              child: Text(
                _cooldown > 0
                    ? 'ส่งอีกครั้งใน $_cooldown วินาที'
                    : 'ส่งลิงก์ยืนยันอีกครั้ง',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => FirebaseAuth.instance.signOut(),
              child: const Text('ใช้อีเมลอื่น / ออกจากระบบ'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// บัญชีเก่าที่ backend ให้ช่วงผ่อนผันยังเข้าได้ แต่สิทธิ์นี้ผู้ใช้แก้เองไม่ได้
class VerifiedAccountGate extends StatefulWidget {
  const VerifiedAccountGate({
    super.key,
    required this.user,
    required this.child,
  });
  final User user;
  final Widget child;
  @override
  State<VerifiedAccountGate> createState() => _VerifiedAccountGateState();
}

class _VerifiedAccountGateState extends State<VerifiedAccountGate> {
  late final _state = FirebaseFirestore.instance
      .collection('account_state')
      .doc(widget.user.uid)
      .snapshots();
  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
      return widget.child;
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _state,
      builder: (context, snapshot) {
        final grace = snapshot.data?.data()?['verificationGraceUntil'];
        final inGrace =
            grace is Timestamp && grace.toDate().isAfter(DateTime.now());
        if (inGrace) {
          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: MaterialBanner(
                  content: const Text('อย่าลืมยืนยันอีเมลก่อนหมดช่วงผ่อนผัน'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VerifyEmailScreen(
                            user: widget.user,
                            onVerified: () {
                              Navigator.of(context).pop();
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                      child: const Text('ยืนยันอีเมล'),
                    ),
                  ],
                ),
              ),
              Expanded(child: widget.child),
            ],
          );
        }
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return VerifyEmailScreen(
          user: widget.user,
          onVerified: () => setState(() {}),
        );
      },
    );
  }
}
