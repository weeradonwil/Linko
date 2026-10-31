import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/block_service.dart';

/// ซ่อนบนหน้าจอเป็นเรื่องของความสบายใจ ส่วนสิทธิ์ติดต่อกันตรวจซ้ำใน Rules
class ContentVisibility extends StatelessWidget {
  const ContentVisibility({
    super.key,
    required this.authorId,
    required this.child,
    this.postKey,
  });
  final String authorId;
  final String? postKey;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: BlockService().watchRestrictedIds(),
    builder: (context, blocks) {
      if (blocks.hasError) return const SizedBox.shrink();
      if (!blocks.hasData) return const SizedBox(height: 32);
      if (blocks.data!.contains(authorId)) return const SizedBox.shrink();
      if (postKey == null) return child;
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection('hidden_posts')
            .doc(postKey)
            .snapshots(),
        builder: (context, hidden) =>
            hidden.hasError || !hidden.hasData || hidden.data!.exists
            ? const SizedBox.shrink()
            : child,
      );
    },
  );
}

/// ปุ่มนี้อยู่ใกล้โปรไฟล์และแชท ใช้บริการเดียวกันเพื่อให้สถานะตรงกันทุกหน้า
class BlockUserButton extends StatelessWidget {
  const BlockUserButton({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: BlockService().watchBlocked(uid),
    builder: (context, snapshot) => OutlinedButton.icon(
      icon: const Icon(Icons.block, size: 18),
      label: Text(snapshot.data == true ? 'ปลดบล็อก' : 'บล็อกผู้ใช้'),
      onPressed: !snapshot.hasData
          ? null
          : () async {
              final blocked = snapshot.data == true;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(blocked ? 'ปลดบล็อกบัญชีนี้?' : 'บล็อกบัญชีนี้?'),
                  content: Text(
                    blocked
                        ? 'จะติดต่อกันได้อีกครั้งตามสิทธิ์ของบัญชี'
                        : 'จะซ่อนเนื้อหาและติดต่อกันไม่ได้ แต่แชทเก่ายังอยู่',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('ยกเลิก'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('ยืนยัน'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await BlockService().setBlocked(uid, !blocked);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ทำรายการไม่สำเร็จ ลองอีกครั้งนะ'),
                    ),
                  );
                }
              }
            },
    ),
  );
}
