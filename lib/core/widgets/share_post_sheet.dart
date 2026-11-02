import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/trusted_service.dart';
import '../services/chat_service.dart';
import '../utils/firebase_error_message.dart';
import 'member_avatar.dart';
import 'post_media.dart';
import 'share_destination_picker.dart';

/// เลือกปลายทางจากข้อมูลจริง กดซ้ำตอนรอจะใช้ requestId เดิม ไม่สร้างแชร์ซ้ำ
class SharePostSheet extends StatefulWidget {
  const SharePostSheet({super.key, required this.postId});
  final String postId;
  static Future<void> show(BuildContext context, String postId) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SharePostSheet(postId: postId),
      );
  @override
  State<SharePostSheet> createState() => _SharePostSheetState();
}

/// ตัวอย่างก่อนแชร์ แสดงรูปและชื่อจริงของเจ้าของโพสต์ ไม่เปิดหน้าอื่นระหว่างเลือกปลายทาง
class _SharePreview extends StatelessWidget {
  const _SharePreview({required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError || snapshot.hasData && !snapshot.data!.exists) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('เปิดโพสต์ต้นฉบับไม่ได้'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final post = Post.fromSnapshot(snapshot.data!);
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MemberAvatar(uid: post.userId, radius: 17),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const Icon(Icons.public_rounded, size: 16),
                    ],
                  ),
                  if (post.content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      post.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (post.mediaPath != null) ...[
                    const SizedBox(height: 8),
                    if (post.mediaType == 'image')
                      SizedBox(
                        height: 145,
                        width: double.infinity,
                        child: PostMedia(
                          path: post.mediaPath!,
                          type: post.mediaType,
                          imageFit: BoxFit.cover,
                        ),
                      )
                    else
                      const Row(
                        children: [
                          Icon(Icons.play_circle_outline_rounded),
                          SizedBox(width: 8),
                          Text('วิดีโอ'),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

class _SharePostSheetState extends State<SharePostSheet> {
  final _caption = TextEditingController();
  late final _requestId = FirebaseFirestore.instance
      .collection('posts')
      .doc()
      .id;
  String _destination = 'feed';
  String? _target;
  String? _peerName;
  bool _chooseFollowing = false;
  bool _busy = false;
  String? _error;
  late final _uid = FirebaseAuth.instance.currentUser!.uid;
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_busy || _destination != 'feed' && _target == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // ใช้การสร้างห้องเดิมของแอป จึงยังตรวจการติดตามและไม่เปิดห้องซ้ำ
      final target = _destination == 'chat' && _chooseFollowing
          ? await ChatService().openConversation(
              peerId: _target!,
              peerName: _peerName ?? 'สมาชิก',
            )
          : _target;
      await TrustedService.call('sharePost', {
        'postId': widget.postId,
        'destination': _destination,
        'targetId': target,
        'caption': _caption.text,
        'requestId': _requestId,
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('แชร์แล้ว')));
    } catch (error) {
      if (mounted) {
        // Snackbar ของหน้าหลักอยู่หลังแผ่นแชร์ ผู้ใช้จึงไม่เห็นสาเหตุที่กดไม่ผ่าน
        final message = firebaseErrorMessage(error, action: 'แชร์');
        setState(
          () => _error = error is FirebaseFunctionsException
              ? '$message (${error.code})'
              : message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height - keyboard) * .82,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.share_outlined, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'แชร์โพสต์',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    tooltip: 'ปิด',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'เลือกที่แชร์ แล้วเขียนข้อความเพิ่มได้',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _destinationChip(
                    'feed',
                    'ฟีดของฉัน',
                    Icons.dynamic_feed_outlined,
                  ),
                  _destinationChip('group', 'กลุ่ม', Icons.groups_outlined),
                  _destinationChip(
                    'chat',
                    'แชท',
                    Icons.chat_bubble_outline_rounded,
                  ),
                ],
              ),
              if (_destination == 'chat')
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('แชทเดิม'),
                      selected: !_chooseFollowing,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _chooseFollowing = false;
                              _target = null;
                              _peerName = null;
                            }),
                    ),
                    ChoiceChip(
                      label: const Text('คนที่ติดตาม'),
                      selected: _chooseFollowing,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _chooseFollowing = true;
                              _target = null;
                              _peerName = null;
                            }),
                    ),
                  ],
                ),
              if (_destination != 'feed') ...[
                const SizedBox(height: 12),
                Text(
                  _destination == 'group'
                      ? 'เลือกกลุ่มที่เป็นสมาชิก'
                      : 'เลือกผู้รับ',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(
                  height: 170,
                  child: ShareDestinationPicker(
                    key: ValueKey('$_destination-$_chooseFollowing'),
                    kind: _destination == 'group'
                        ? 'group'
                        : _chooseFollowing
                        ? 'following'
                        : 'chat',
                    uid: _uid,
                    selected: _target,
                    busy: _busy,
                    onSelected: (id, name) => setState(() {
                      _target = id;
                      _peerName = name;
                      _error = null;
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _caption,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'เขียนข้อความเพิ่มได้…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              Text(
                'โพสต์ต้นฉบับ',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              _SharePreview(postId: widget.postId),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || _destination != 'feed' && _target == null
                    ? null
                    : _share,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: Text(_busy ? 'กำลังแชร์…' : 'แชร์'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destinationChip(String value, String label, IconData icon) =>
      ChoiceChip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
        selected: _destination == value,
        onSelected: _busy
            ? null
            : (_) => setState(() {
                _destination = value;
                _target = null;
                _peerName = null;
                _error = null;
              }),
      );
}
