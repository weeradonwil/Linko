import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/block_service.dart';
import '../../core/widgets/member_avatar.dart';

/// ปลดบล็อกจากหน้านี้ได้ แม้จะซ่อนโพสต์และโปรไฟล์ของอีกฝ่ายไปแล้ว
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('บัญชีที่บล็อก')),
    body: StreamBuilder<Set<String>>(
      stream: BlockService().watchBlockedIds(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('โหลดรายชื่อไม่สำเร็จ ลองเปิดอีกครั้งนะ'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snapshot.data!.toList();
        if (ids.isEmpty) {
          return const Center(child: Text('ยังไม่มีบัญชีที่บล็อก'));
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, index) =>
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(ids[index])
                    .snapshots(),
                builder: (context, user) => ListTile(
                  leading: MemberAvatar(uid: ids[index]),
                  title: Text(
                    user.data?.data()?['displayName'] as String? ?? 'สมาชิก',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await BlockService().setBlocked(ids[index], false);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ปลดบล็อกไม่สำเร็จ ลองอีกครั้งนะ'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('ปลดบล็อก'),
                  ),
                ),
              ),
        );
      },
    ),
  );
}
