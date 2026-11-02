import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../core/models/post_policy.dart';
import '../../core/utils/document_values.dart';

enum ProfileImageKind { avatar, cover }

/// เปิดรูปจากโปรไฟล์จริง รูปปกอ่านได้เมื่อเข้าสู่ระบบ ส่วนรูปโปรไฟล์ขนาดใหญ่ยังดูตามสถานะบัญชี
class ProfileImageScreen extends StatefulWidget {
  const ProfileImageScreen({
    super.key,
    required this.ownerUid,
    required this.kind,
    this.profileStream,
    this.readViewerUid,
    this.loadImage,
  });

  final String ownerUid;
  final ProfileImageKind kind;

  // แยกแหล่งข้อมูลได้ตอนทดสอบ แต่การใช้งานปกติอ่าน Firebase จริงเหมือนเดิม
  final Stream<Map<String, dynamic>?>? profileStream;
  final String? Function()? readViewerUid;
  final Future<Uint8List?> Function(String path)? loadImage;

  @override
  State<ProfileImageScreen> createState() => _ProfileImageScreenState();
}

class _ProfileImageScreenState extends State<ProfileImageScreen> {
  late final _profile =
      widget.profileStream ??
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.ownerUid)
          .snapshots()
          .map((snapshot) => snapshot.data());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == ProfileImageKind.avatar ? 'รูปโปรไฟล์' : 'ภาพปก',
      ),
    ),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _ImageNotice(
            icon: Icons.cloud_off_outlined,
            message: 'เปิดรูปไม่สำเร็จ ลองเข้ามาใหม่นะ',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return const _ImageNotice(
            icon: Icons.person_off_outlined,
            message: 'ไม่พบบัญชีนี้',
          );
        }
        final viewerUid = widget.readViewerUid != null
            ? widget.readViewerUid!()
            : FirebaseAuth.instance.currentUser?.uid;
        // รูปปกแสดงให้สมาชิกที่เข้าสู่ระบบเห็นได้ แม้ยังไม่ได้ติดตามบัญชีส่วนตัว
        final allowed =
            viewerUid != null &&
            (widget.kind == ProfileImageKind.cover ||
                viewerUid == widget.ownerUid ||
                !PostPolicy.profileIsPrivate(data));
        if (!allowed) {
          return const _ImageNotice(
            icon: Icons.lock_outline_rounded,
            message: 'บัญชีส่วนตัว เปิดดูรูปใหญ่ไม่ได้',
          );
        }
        final path = readOptionalString(
          data[widget.kind == ProfileImageKind.avatar
              ? 'avatarPath'
              : 'coverPath'],
        );
        if (path == null || path.isEmpty) {
          return const _ImageNotice(
            icon: Icons.image_not_supported_outlined,
            message: 'ยังไม่มีรูปภาพ',
          );
        }
        // เปลี่ยนไฟล์แล้วโหลดใหม่ และไม่ส่ง download URL ที่ข้าม Rules ไปให้หน้าดูรูป
        return _FullProfileImage(
          key: ValueKey(path),
          path: path,
          loadImage: widget.loadImage,
        );
      },
    ),
  );
}

class _FullProfileImage extends StatefulWidget {
  const _FullProfileImage({super.key, required this.path, this.loadImage});

  final String path;
  final Future<Uint8List?> Function(String path)? loadImage;

  @override
  State<_FullProfileImage> createState() => _FullProfileImageState();
}

class _FullProfileImageState extends State<_FullProfileImage> {
  late Future<Uint8List?> _bytes = _load();

  // ใช้ SDK อ่านใหม่ทุกครั้งที่เปิด เพื่อให้ Storage ตรวจสิทธิ์ก่อนส่งไฟล์
  Future<Uint8List?> _load() => widget.loadImage != null
      ? widget.loadImage!(widget.path)
      : FirebaseStorage.instance.ref(widget.path).getData(5 * 1024 * 1024);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          snapshot.connectionState == ConnectionState.done &&
              snapshot.data == null) {
        return _ImageNotice(
          icon: Icons.broken_image_outlined,
          message: 'โหลดรูปไม่สำเร็จ',
          onRetry: () => setState(() {
            _bytes = _load();
          }),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return SizedBox.expand(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              semanticLabel: 'รูปภาพขนาดเต็ม ใช้สองนิ้วเพื่อซูม',
              errorBuilder: (_, _, _) => const _ImageNotice(
                icon: Icons.broken_image_outlined,
                message: 'เปิดไฟล์รูปนี้ไม่ได้',
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ImageNotice extends StatelessWidget {
  const _ImageNotice({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('ลองอีกครั้ง')),
        ],
      ),
    ),
  );
}
