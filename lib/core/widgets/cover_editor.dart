import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/cover_crop.dart';
import 'post_media.dart';

/// ใช้ภาพ 3:1 จริงทั้งตอน preview และตอนส่งออก จึงไม่ตัดรูปคนละตำแหน่งหลังบันทึก
class CoverEditor extends StatefulWidget {
  const CoverEditor({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends State<CoverEditor> {
  double _x = 0;
  double _y = 0;
  bool _saving = false;
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await cropProfileCover(widget.bytes, x: _x, y: _y);
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดภาพนี้ไม่ได้ ลองเลือกไฟล์อื่นนะ')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('จัดรูปปก')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              widget.bytes,
              fit: BoxFit.cover,
              alignment: Alignment(_x, _y),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('เลื่อนแนวนอน'),
        Slider(
          value: _x,
          min: -1,
          max: 1,
          onChanged: _saving ? null : (value) => setState(() => _x = value),
        ),
        const Text('เลื่อนแนวตั้ง'),
        Slider(
          value: _y,
          min: -1,
          max: 1,
          onChanged: _saving ? null : (value) => setState(() => _y = value),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'กำลังจัดรูป…' : 'ใช้รูปนี้'),
        ),
      ],
    ),
  );
}

class ProfileCover extends StatelessWidget {
  const ProfileCover({
    super.key,
    required this.path,
    this.ownerUid,
    this.isPrivate = false,
  });
  final String? path;
  final String? ownerUid;
  final bool isPrivate;
  Widget _image(BuildContext context, bool allowed) => AspectRatio(
    aspectRatio: 3,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: path == null || !allowed
          ? ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Center(
                child: Icon(Icons.landscape_outlined, size: 40),
              ),
            )
          : PostMedia(path: path!, type: 'image', imageFit: BoxFit.cover),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final isOwner = ownerUid != null &&
        ownerUid == FirebaseAuth.instance.currentUser?.uid;
    return _image(context, !isPrivate || isOwner);
  }
}
