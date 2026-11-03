import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key, required this.user});

  final User user;

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _pendingEmail;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendVerification() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    final currentEmail = widget.user.email?.trim();
    final newEmail = _emailController.text.trim();
    if (currentEmail == null || currentEmail.isEmpty) {
      setState(() => _errorMessage = 'บัญชีนี้ไม่มีอีเมลที่ใช้เข้าสู่ระบบ');
      return;
    }
    if (currentEmail.toLowerCase() == newEmail.toLowerCase()) {
      setState(() => _errorMessage = 'อีเมลใหม่ต้องไม่ซ้ำกับอีเมลปัจจุบัน');
      return;
    }

    final canReauthenticateWithPassword = widget.user.providerData.any(
      (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
    );
    if (!canReauthenticateWithPassword) {
      setState(
        () => _errorMessage = 'บัญชีนี้ไม่ได้เข้าสู่ระบบด้วยอีเมลและรหัสผ่าน กรุณาเข้าสู่ระบบใหม่ก่อนเปลี่ยนอีเมล',
      );
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final credential = EmailAuthProvider.credential(
        email: currentEmail,
        password: _passwordController.text,
      );
      await widget.user.reauthenticateWithCredential(credential);

      // ส่งลิงก์ยืนยันก่อนเปลี่ยนอีเมลจริง เพื่อคงอีเมลเดิมไว้จนกว่าจะยืนยันสำเร็จ
      await FirebaseAuth.instance.setLanguageCode('th');
      await widget.user.verifyBeforeUpdateEmail(newEmail);

      if (!mounted) return;
      setState(() => _pendingEmail = newEmail);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _authError(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'ส่งลิงก์ยืนยันไม่สำเร็จ กรุณาลองอีกครั้ง',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkVerification() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (!mounted) return;

      if (refreshedUser?.email?.toLowerCase() == _pendingEmail?.toLowerCase()) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(
        () => _errorMessage =
            'ยังไม่พบการยืนยัน ลองกดลิงก์ในอีเมลแล้วตรวจสอบอีกครั้ง',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _authError(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'ตรวจสอบสถานะไม่สำเร็จ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authError(String code) => switch (code) {
    'wrong-password' || 'invalid-credential' => 'รหัสผ่านปัจจุบันไม่ถูกต้อง',
    'email-already-in-use' => 'อีเมลนี้มีบัญชีใช้อยู่แล้ว',
    'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
    'requires-recent-login' =>
      'กรุณาเข้าสู่ระบบใหม่ แล้วลองเปลี่ยนอีเมลอีกครั้ง',
    'too-many-requests' => 'ทำรายการบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่',
    'network-request-failed' => 'เชื่อมต่ออินเทอร์เน็ตไม่ได้',
    'user-disabled' => 'บัญชีนี้ถูกปิดใช้งาน',
    _ => 'เปลี่ยนอีเมลไม่สำเร็จ ($code)',
  };

  @override
  Widget build(BuildContext context) {
    final currentEmail = widget.user.email ?? 'ไม่มีอีเมล';
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('เปลี่ยนอีเมล')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'อีเมลปัจจุบัน',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(currentEmail),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _emailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'อีเมลใหม่',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'กรุณากรอกอีเมลใหม่';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(email)) {
                      return 'รูปแบบอีเมลไม่ถูกต้อง';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _sendVerification(),
                  decoration: const InputDecoration(
                    labelText: 'รหัสผ่านปัจจุบัน',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'กรุณากรอกรหัสผ่านปัจจุบัน'
                      : null,
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
          if (_pendingEmail != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ส่งลิงก์ยืนยันแล้ว'),
                    const SizedBox(height: 6),
                    SelectableText(_pendingEmail!),
                    const SizedBox(height: 8),
                    const Text(
                      'เปิดอีเมลใหม่แล้วกดลิงก์ยืนยัน อีเมลปัจจุบันจะยังใช้ได้จนกว่ายืนยันสำเร็จ',
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : _checkVerification,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('ตรวจสอบการยืนยัน'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _sendVerification,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              _busy
                  ? 'กำลังดำเนินการ'
                  : _pendingEmail == null
                  ? 'ส่งลิงก์ยืนยัน'
                  : 'ส่งลิงก์อีกครั้ง',
            ),
          ),
        ],
      ),
    );
  }
}
