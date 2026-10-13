// รวมฟอร์ม Login และ Register พร้อมตรวจข้อมูลก่อนส่งให้ AuthService
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import 'forgot_password.dart';

/// หน้าเดียวสำหรับเข้าสู่ระบบและสมัครสมาชิกด้วยอีเมล
class LoginScreen extends StatefulWidget {
  const LoginScreen({this.isDarkMode = false, this.onToggleTheme, super.key});

  /// บอกหน้าจอว่า Theme ที่กำลังแสดงเป็นแบบมืดหรือไม่ เพื่อเลือกไอคอนให้ถูก
  final bool isDarkMode;

  /// คำสั่งจาก SocialApp; เป็น null ได้ใน Widget test หรือกรณีไม่ต้องการปุ่ม
  final VoidCallback? onToggleTheme;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // key ใช้เรียกตรวจทุก validator ใน Form พร้อมกันก่อนสมัคร/เข้าสู่ระบบ
  final _formKey = GlobalKey<FormState>();

  // Controller เก็บข้อความที่ผู้ใช้พิมพ์ เพื่อส่งค่าไปยัง AuthService
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  // สร้างบริการ Firebase เมื่อส่งแบบฟอร์มจริง เพื่อให้แสดงและตรวจฟอร์มได้
  // โดยไม่ต้องเชื่อม Firebase ก่อน
  late final _authService = AuthService();

  // ตัวแปรเหล่านี้ควบคุมส่วนที่เปลี่ยนบนหน้าจอ จึงต้องเรียก setState เมื่อเปลี่ยนค่า
  bool _isRegistering = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    // ปิด Controller เมื่อออกจากหน้านี้เพื่อคืนทรัพยากรที่ใช้เก็บข้อความ
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// ตรวจแบบฟอร์มก่อนส่งข้อมูลให้ Firebase และกันการกดซ้ำระหว่างรอผล
  Future<void> _submit() async {
    // ถ้ามีช่องใดไม่ผ่าน validator จะหยุดที่นี่และแสดงข้อความใต้ช่องนั้น
    if (!_formKey.currentState!.validate()) return;

    // ปิดปุ่มชั่วคราวและแสดงตัวหมุนระหว่างรอคำตอบจากเครือข่าย
    setState(() => _isLoading = true);
    try {
      // ใช้โหมดปัจจุบันเลือกว่าจะสร้างบัญชีใหม่หรือเข้าสู่บัญชีเดิม
      if (_isRegistering) {
        await _authService.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await _authService.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      // AuthGate รับฟังสถานะ Auth และเปิดหน้า Home ให้อัตโนมัติเมื่อสำเร็จ
    } on FirebaseAuthException catch (error) {
      // แปลงรหัสผิดพลาดของ Firebase เป็นข้อความภาษาไทยที่ผู้ใช้แก้ตามได้
      _showMessage(_authErrorMessage(error.code));
    } on AuthServiceException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('เกิดข้อผิดพลาด กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง');
    } finally {
      // ปิดสถานะโหลดแม้สำเร็จหรือเกิด error; mounted กัน setState หลังปิดหน้า
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// เปลี่ยนรหัสข้อผิดพลาดจาก Firebase ให้เป็นคำแนะนำภาษาไทย
  String _authErrorMessage(String code) {
    // Firebase ส่ง code สำหรับแต่ละสาเหตุ; switch เลือกคำแนะนำให้ตรงกับ code
    return switch (code) {
      'email-already-in-use' => 'อีเมลนี้มีบัญชีอยู่แล้ว กรุณาเข้าสู่ระบบ',
      'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
      'weak-password' => 'รหัสผ่านไม่ปลอดภัยพอ กรุณาตั้งรหัสผ่านใหม่',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
      'too-many-requests' => 'ลองหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่',
      'network-request-failed' => 'เชื่อมต่อไม่ได้ กรุณาตรวจอินเทอร์เน็ต',
      'operation-not-allowed' =>
        'โปรเจกต์ Firebase ยังไม่ได้เปิดใช้การเข้าสู่ระบบด้วยอีเมล',
      _ => 'ทำรายการไม่สำเร็จ กรุณาตรวจข้อมูลแล้วลองอีกครั้ง',
    };
  }

  void _showMessage(String message) {
    if (!mounted) return;
    // SnackBar แสดงข้อความชั่วคราวด้านล่าง โดยซ่อนข้อความเก่าก่อน
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final compact = viewport.maxHeight < 920;
            final veryCompact = viewport.maxHeight < 680;
            final horizontalPadding = viewport.maxWidth < 380 ? 16.0 : 24.0;
            final availableHeight = (viewport.maxHeight - 16)
                .clamp(0.0, viewport.maxHeight)
                .toDouble();
            final iconSize = veryCompact
                ? 70.0
                : compact
                ? 86.0
                : 104.0;
            final fieldVerticalPadding = veryCompact
                ? 13.0
                : compact
                ? 17.0
                : 22.0;
            final fieldGap = veryCompact
                ? 8.0
                : compact
                ? 11.0
                : 16.0;

            InputDecoration fieldDecoration(String label, IconData icon) {
              final outline = OutlineInputBorder(
                borderRadius: BorderRadius.circular(compact ? 20 : 24),
                borderSide: BorderSide(
                  color: colors.outline.withValues(alpha: 0.34),
                ),
              );
              return InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, size: compact ? 22 : 26),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 22,
                  vertical: fieldVerticalPadding,
                ),
                border: outline,
                enabledBorder: outline,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(compact ? 20 : 24),
                  borderSide: BorderSide(color: colors.primary, width: 1.7),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(compact ? 20 : 24),
                  borderSide: BorderSide(color: colors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(compact ? 20 : 24),
                  borderSide: BorderSide(color: colors.error, width: 1.7),
                ),
              );
            }

            Widget content = ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            RichText(
                              text: TextSpan(
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontSize: compact ? 34 : 38,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Link',
                                    style: TextStyle(color: colors.onSurface),
                                  ),
                                  TextSpan(
                                    text: 'o',
                                    style: TextStyle(color: colors.primary),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (widget.onToggleTheme != null)
                              IconButton(
                                tooltip: widget.isDarkMode
                                    ? 'เปลี่ยนเป็นโหมดสว่าง'
                                    : 'เปลี่ยนเป็นโหมดมืด',
                                onPressed: widget.onToggleTheme,
                                iconSize: compact ? 26 : 30,
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : VisualDensity.standard,
                                icon: Icon(
                                  widget.isDarkMode
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(
                          height: veryCompact
                              ? 6
                              : compact
                              ? 14
                              : 34,
                        ),
                        Center(
                          child: Container(
                            width: iconSize,
                            height: iconSize,
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(
                                iconSize * 0.28,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.translate(
                                  offset: Offset(
                                    iconSize * 0.09,
                                    iconSize * 0.07,
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_rounded,
                                    size: iconSize * 0.55,
                                    color: colors.primary,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(
                                    -iconSize * 0.07,
                                    -iconSize * 0.05,
                                  ),
                                  child: Icon(
                                    Icons.chat_rounded,
                                    size: iconSize * 0.55,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Positioned(
                                  left: iconSize * 0.37,
                                  top: iconSize * 0.41,
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: iconSize * 0.25,
                                    color: colors.surface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: veryCompact
                              ? 8
                              : compact
                              ? 16
                              : 22,
                        ),
                        Text(
                          _isRegistering ? 'สร้างบัญชีใหม่' : 'ยินดีต้อนรับ',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: veryCompact
                                ? 27
                                : compact
                                ? 31
                                : 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: compact ? 3 : 8),
                        Text(
                          _isRegistering
                              ? 'เข้าร่วมชุมชนเพื่อพูดคุยและแชร์กับเพื่อน'
                              : 'เข้าสู่ชุมชนเพื่อพูดคุยและแชร์กับเพื่อน',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: compact ? 13 : 16,
                            height: 1.35,
                          ),
                        ),
                        SizedBox(
                          height: veryCompact
                              ? 8
                              : compact
                              ? 18
                              : 28,
                        ),
                        Container(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 18 : 22,
                            veryCompact
                                ? 12
                                : compact
                                ? 17
                                : 24,
                            compact ? 18 : 22,
                            veryCompact
                                ? 10
                                : compact
                                ? 14
                                : 22,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(
                              compact ? 26 : 30,
                            ),
                            border: Border.all(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_isRegistering) ...[
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  style: TextStyle(fontSize: compact ? 14 : 16),
                                  decoration: fieldDecoration(
                                    'ชื่อที่แสดง',
                                    Icons.person_outline_rounded,
                                  ),
                                  validator: (value) {
                                    if (value?.trim().isEmpty ?? true) {
                                      return 'กรุณากรอกชื่อที่แสดง';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: fieldGap),
                              ],
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                style: TextStyle(fontSize: compact ? 14 : 16),
                                decoration: fieldDecoration(
                                  'อีเมล',
                                  Icons.mail_outline_rounded,
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) return 'กรุณากรอกอีเมล';
                                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(email)) {
                                    return 'กรุณากรอกอีเมลให้ถูกต้อง';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: fieldGap),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: _isRegistering
                                    ? const [AutofillHints.newPassword]
                                    : const [AutofillHints.password],
                                style: TextStyle(fontSize: compact ? 14 : 16),
                                decoration:
                                    fieldDecoration(
                                      'รหัสผ่าน',
                                      Icons.lock_outline_rounded,
                                    ).copyWith(
                                      helperText: _isRegistering
                                          ? 'อย่างน้อย 8 ตัว: ตัวพิมพ์ใหญ่ ตัวพิมพ์เล็ก ตัวเลข และอักขระพิเศษ'
                                          : null,
                                      helperMaxLines: 2,
                                      helperStyle: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: compact ? 10 : 12,
                                        height: 1.25,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'แสดงรหัสผ่าน'
                                            : 'ซ่อนรหัสผ่าน',
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: compact ? 21 : 24,
                                        ),
                                      ),
                                    ),
                                validator: (value) {
                                  final password = value ?? '';
                                  if (password.isEmpty) {
                                    return 'กรุณากรอกรหัสผ่าน';
                                  }
                                  if (!_isRegistering) return null;
                                  if (password.length < 8) {
                                    return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
                                  }
                                  final hasUppercase = RegExp(r'[A-Z]')
                                      .hasMatch(password);
                                  final hasLowercase = RegExp(r'[a-z]')
                                      .hasMatch(password);
                                  final hasNumber = RegExp(r'[0-9]')
                                      .hasMatch(password);
                                  const allowedSymbols =
                                      r'''^$*.[ ]{}()?"!@#%&/\,><':;|_~''';
                                  final hasSymbol = password
                                      .split('')
                                      .any(allowedSymbols.contains);
                                  if (!hasUppercase ||
                                      !hasLowercase ||
                                      !hasNumber ||
                                      !hasSymbol) {
                                    return 'ต้องมีตัวพิมพ์ใหญ่ ตัวพิมพ์เล็ก ตัวเลข และอักขระพิเศษ';
                                  }
                                  return null;
                                },
                              ),
                              if (!_isRegistering)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ForgotPasswordScreen(
                                          initialEmail: _emailController.text
                                              .trim(),
                                        ),
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      minimumSize: Size(0, compact ? 34 : 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('ลืมรหัสผ่าน?'),
                                  ),
                                )
                              else ...[
                                SizedBox(height: fieldGap),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  style: TextStyle(fontSize: compact ? 14 : 16),
                                  decoration: fieldDecoration(
                                    'ยืนยันรหัสผ่าน',
                                    Icons.lock_reset_outlined,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณายืนยันรหัสผ่าน';
                                    }
                                    if (value != _passwordController.text) {
                                      return 'รหัสผ่านไม่ตรงกัน';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              SizedBox(
                                height: veryCompact
                                    ? 8
                                    : compact
                                    ? 14
                                    : 20,
                              ),
                              SizedBox(
                                height: compact ? 54 : 66,
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        compact ? 19 : 24,
                                      ),
                                    ),
                                    textStyle: theme.textTheme.titleLarge
                                        ?.copyWith(
                                          fontSize: compact ? 17 : 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _isRegistering
                                              ? 'สมัครสมาชิก'
                                              : 'เข้าสู่ระบบ',
                                        ),
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 14),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _isRegistering
                                        ? 'มีบัญชีแล้ว? '
                                        : 'ยังไม่มีบัญชี? ',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                          fontSize: compact ? 13 : 16,
                                        ),
                                  ),
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => setState(() {
                                            _isRegistering = !_isRegistering;
                                            _formKey.currentState?.reset();
                                          }),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      minimumSize: Size(0, compact ? 30 : 40),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: colors.primary,
                                      textStyle: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontSize: compact ? 13 : 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    child: Text(
                                      _isRegistering
                                          ? 'เข้าสู่ระบบ'
                                          : 'สมัครสมาชิก',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );

            final page = keyboardOpen
                ? SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 8,
                    ),
                    child: content,
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 8,
                    ),
                    child: content,
                  );
            return page;
          },
        ),
      ),
    );
  }
}
