// หน้าต้นแบบกู้คืนรหัสผ่าน; ปุ่มยังไม่เรียก Firebase Auth เพื่อส่งอีเมล
import 'package:flutter/material.dart';

/// หน้าจอ UI สำหรับการกู้คืนรหัสผ่าน (ยังไม่เชื่อมต่อ Firebase)
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({this.initialEmail = '', super.key});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showNotReadyMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ฟังก์ชันรีเซ็ตรหัสผ่านยังไม่พร้อมใช้งาน')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลืมรหัสผ่าน')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_reset_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'รีเซ็ตรหัสผ่าน',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'กรอกอีเมลที่ใช้สมัครสมาชิก ฟังก์ชันส่งลิงก์จะเปิดใช้งานในภายหลัง',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'อีเมล',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _showNotReadyMessage,
                    child: const Text('ส่งลิงก์รีเซ็ตรหัสผ่าน'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
