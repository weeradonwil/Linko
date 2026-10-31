import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/trusted_service.dart';
import '../services/chat_service.dart';
import '../utils/firebase_error_message.dart';
import 'share_destination_picker.dart';
import 'shared_post_card.dart';

/// เลือกปลายทางจากข้อมูลจริง กดซ้ำตอนรอจะใช้ requestId เดิม ไม่สร้างแชร์ซ้ำ
class SharePostSheet extends StatefulWidget {
  const SharePostSheet({super.key, required this.postId});
  final String postId;
  static Future<void> show(BuildContext context, String postId) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: .85,
          child: SharePostSheet(postId: postId),
        ),
      );
  @override
  State<SharePostSheet> createState() => _SharePostSheetState();
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
  late final _uid = FirebaseAuth.instance.currentUser!.uid;
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('แชร์แล้ว')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firebaseErrorMessage(error, action: 'แชร์'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(child: Text('แชร์โพสต์')),
            IconButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _destination,
          items: const [
            DropdownMenuItem(value: 'feed', child: Text('Feed ของฉัน')),
            DropdownMenuItem(value: 'group', child: Text('แชร์ลงกลุ่ม')),
            DropdownMenuItem(value: 'chat', child: Text('ส่งในแชท')),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _destination = value!;
                  _target = null;
                  _peerName = null;
                }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _caption,
          enabled: !_busy,
          maxLength: 1000,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'เขียนข้อความเพิ่มได้'),
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
        if (_destination != 'feed')
          Expanded(
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
              }),
            ),
          ),
        if (_destination == 'feed')
          Expanded(
            child: SingleChildScrollView(
              child: SharedPostCard(postId: widget.postId),
            ),
          ),
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
  );
}
