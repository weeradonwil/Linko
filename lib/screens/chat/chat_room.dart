import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/chat_models.dart';
import '../../core/services/chat_service.dart';
import '../../core/widgets/post_media.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.user,
    required this.conversationId,
    required this.peerId,
    required this.peerName,
  });
  final User user;
  final String conversationId;
  final String peerId;
  final String peerName;
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

// ฟังข้อความของห้องนี้ และอัปเดตสถานะอ่านเมื่อมีข้อความเข้ามา
class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _service = ChatService();
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  XFile? _attachment;
  bool _sending = false;
  late Stream<List<ChatMessage>> _messages;
  StreamSubscription<List<ChatMessage>>? _readSubscription;
  @override
  void initState() {
    super.initState();
    _messages = _service.watchMessages(widget.conversationId);
    unawaited(_markRead());
    _readSubscription = _messages.listen((_) => unawaited(_markRead()));
  }

  Future<void> _markRead() async {
    try {
      await _service.markRead(widget.conversationId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _readSubscription?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // เลือกภาพหรือวิดีโอจากคลัง; การตรวจชนิดและขนาดไฟล์อยู่ใน ChatService
  Future<void> _chooseMedia() async {
    final image = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('เลือกรูปภาพ'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('เลือกวิดีโอ'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (image == null || !mounted) return;
    final file = image
        ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null && mounted) setState(() => _attachment = file);
  }

  // กันการกดส่งซ้ำระหว่างรอ Firebase และล้างข้อมูลแนบเมื่อส่งสำเร็จ
  Future<void> _send() async {
    if (_sending || (_controller.text.trim().isEmpty && _attachment == null))
      return;
    final body = _controller.text;
    final file = _attachment;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(
        conversationId: widget.conversationId,
        peerId: widget.peerId,
        text: body,
        attachment: file,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() => _attachment = null);
      if (_scroll.hasClients)
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ChatServiceException
                  ? error.message
                  : 'ส่งข้อความไม่สำเร็จ ตรวจการเชื่อมต่อและ Firebase Rules',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'ย้อนกลับ',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: colors.primary.withValues(alpha: .2),
              child: Text(
                widget.peerName.characters.first.toUpperCase(),
                style: TextStyle(color: colors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'แชทส่วนตัว',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(
                    child: Text(
                      'โหลดข้อความไม่สำเร็จ กรุณาตรวจ Firestore Rules',
                    ),
                  );
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                final items = snapshot.data ?? [];
                if (items.isEmpty)
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.waving_hand_outlined,
                          size: 48,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'เริ่มทักทาย ' + widget.peerName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final message = items[items.length - 1 - i];
                    return _MessageBubble(
                      message: message,
                      isMine: message.senderId == widget.user.uid,
                      peerInitial: widget.peerName.characters.first
                          .toUpperCase(),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .45),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_attachment != null)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        _attachment!.mimeType?.startsWith('video/') == true
                            ? Icons.videocam_outlined
                            : Icons.image_outlined,
                      ),
                      title: Text(
                        _attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        onPressed: () => setState(() => _attachment = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'แนบรูปหรือวิดีโอ',
                        onPressed: _sending ? null : _chooseMedia,
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'พิมพ์ข้อความ...',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(24),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'ส่ง',
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.peerInitial,
  });
  final ChatMessage message;
  final bool isMine;
  final String peerInitial;
  String _time(DateTime? d) => d == null
      ? ''
      : d.hour.toString().padLeft(2, '0') +
            ':' +
            d.minute.toString().padLeft(2, '0');
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bubbleColor = isMine ? colors.primary : colors.surfaceContainerHigh;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.primary.withValues(alpha: .2),
                child: Text(
                  peerInitial,
                  style: TextStyle(color: colors.primary, fontSize: 12),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .76,
                ),
                child: Container(
                  padding: message.mediaPath == null
                      ? const EdgeInsets.symmetric(horizontal: 15, vertical: 11)
                      : const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMine ? 20 : 5),
                      bottomRight: Radius.circular(isMine ? 5 : 20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.mediaPath != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: SizedBox(
                            width: 260,
                            height: 190,
                            child: PostMedia(
                              path: message.mediaPath!,
                              type: message.type,
                            ),
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        Padding(
                          padding: message.mediaPath == null
                              ? EdgeInsets.zero
                              : const EdgeInsets.fromLTRB(8, 7, 8, 4),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: isMine ? Colors.white : colors.onSurface,
                              fontSize: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                _time(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
