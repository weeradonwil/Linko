import '../../core/widgets/shared_post_card.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/services/trusted_service.dart';
import '../../core/widgets/post_media.dart';
import '../../core/utils/firebase_error_message.dart';
import '../create_post/create_post.dart';

/// นี่คือหน้าคำเตือนของเจ้าของโพสต์ ไม่ใช่หน้าติดตามผลของคนรายงาน
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, this.groupId, this.caseId});
  final String? groupId;
  final String? caseId;
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  bool _busy = false;
  late final _uid = FirebaseAuth.instance.currentUser!.uid;
  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'moderation_cases',
    );
    if (widget.groupId != null) {
      query = query
          .where('groupOwnerId', isEqualTo: _uid)
          .where('groupId', isEqualTo: widget.groupId);
    } else {
      query = query.where('ownerId', isEqualTo: _uid);
    }
    return query.orderBy('updatedAt', descending: true).limit(100);
  }

  Future<void> _act(String caseId, String action, bool manager) async {
    setState(() => _busy = true);
    try {
      await TrustedService.call(
        manager ? 'reviewGroupReport' : 'respondToWarning',
        {
          'caseId': caseId,
          if (manager) 'decision': action else 'action': action,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกแล้ว')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firebaseErrorMessage(error, action: 'ทำรายการ')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.groupId == null
            ? 'คำเตือนและสิทธิ์โพสต์'
            : 'จัดการรายงานในกลุ่ม',
      ),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('โหลดไม่สำเร็จ ลองเปิดอีกครั้งนะ'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs
            .where((doc) => widget.caseId == null || doc.id == widget.caseId)
            .toList();
        if (docs.isEmpty) return const Center(child: Text('ยังไม่มีรายการ'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final old = Map<String, dynamic>.from(
              data['snapshot'] as Map? ?? {},
            );
            final evidence = Map<String, dynamic>.from(
              data['evidencePaths'] as Map? ?? {},
            );
            final status = data['status'] as String? ?? 'queued';
            final labels = {
              'queued': 'ได้รับรายงาน',
              'warned': 'รอแก้ไข',
              'contested': 'โต้แย้งแล้ว หยุดลงโทษอัตโนมัติ',
              'changed': 'มีการแก้ไขแล้ว',
              'resolved': 'ปิดเรื่องแล้ว',
              'dismissed': 'ไม่พบการละเมิด',
              'removed': 'นำโพสต์ออกแล้ว',
              'suspended': 'พักสิทธิ์โพสต์ 72 ชั่วโมง',
            };
            final groupId = data['groupId'] as String?;
            final owner = data['ownerId'] == _uid;
            final manager = widget.groupId != null && !owner;
            final active = ['queued', 'warned', 'contested'].contains(status);
            final deadline = data['deadline'] as Timestamp?;
            final until = data['suspensionUntil'] as Timestamp?;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[status] ?? status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('เหตุผล: ${data['reason'] ?? ''}'),
                    if (manager &&
                        (data['details'] as String? ?? '').isNotEmpty)
                      Text(data['details'] as String),
                    const SizedBox(height: 8),
                    Text(old['content'] as String? ?? ''),
                    if (old['sharedPostId'] is String)
                      SharedPostCard(postId: old['sharedPostId'] as String),
                    if (old['mediaPath'] is String)
                      SizedBox(
                        height: 180,
                        child: PostMedia(
                          path:
                              evidence['media'] as String? ??
                              old['mediaPath'] as String,
                          type: old['mediaType'] as String? ?? 'image',
                          thumbnailPath:
                              evidence['thumbnail'] as String? ??
                              old['thumbnailPath'] as String?,
                        ),
                      ),
                    if (deadline != null && status == 'warned')
                      Text('แก้ไขก่อน: ${deadline.toDate().toLocal()}'),
                    if (until != null)
                      Text(
                        'พักสิทธิ์${groupId == null ? 'ทั้งแอป' : 'ในกลุ่มนี้'}ถึง: ${until.toDate().toLocal()}',
                      ),
                    if (owner && active)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => _edit(data),
                            child: const Text('แก้ไขโพสต์'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(doc.id, 'edited', false),
                            child: const Text('แจ้งว่าแก้ไขแล้ว'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _confirm(doc.id, false),
                            child: const Text('ลบโพสต์นี้'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(doc.id, 'contest', false),
                            child: const Text('โพสต์นี้ไม่ผิด / ขอทบทวน'),
                          ),
                        ],
                      ),
                    if (manager && active)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(doc.id, 'dismiss', true),
                            child: const Text('ไม่พบการละเมิด'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(doc.id, 'warn', true),
                            child: const Text('เตือนให้แก้ไข'),
                          ),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _confirm(doc.id, true),
                            child: const Text('นำโพสต์ออก'),
                          ),
                        ],
                      ),
                    if (widget.groupId != null && owner)
                      const Text(
                        'รายงานโพสต์ของเจ้าของกลุ่มให้ระบบรับเรื่อง เจ้าของกลุ่มปิดเรื่องเองไม่ได้',
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _edit(Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      final fresh = await FirebaseFirestore.instance
          .doc(data['sourcePath'] as String)
          .get();
      if (!mounted) return;
      if (!fresh.exists) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('โพสต์ไม่พร้อมใช้งาน')));
        return;
      }
      final values = fresh.data()!;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CreatePostScreen(
            user: FirebaseAuth.instance.currentUser!,
            post: Post.fromData(fresh.id, {
              ...values,
              'userId': values['userId'] ?? values['authorId'],
            }),
            groupId: data['groupId'] as String?,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firebaseErrorMessage(error, action: 'เปิดโพสต์')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String caseId, bool manager) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('นำโพสต์นี้ออก?'),
        content: const Text('โพสต์จะหายจากหน้าปกติ ระบบเก็บหลักฐานไว้ชั่วคราว'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('นำออก'),
          ),
        ],
      ),
    );
    if (yes == true) await _act(caseId, manager ? 'remove' : 'delete', manager);
  }
}
