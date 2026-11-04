import '../../core/widgets/shared_post_card.dart';

// ฟอร์มสร้างหรือแก้ไขโพสต์ พร้อมจัดการข้อความ แท็ก การมองเห็น และไฟล์แนบ
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/post.dart';
import '../../core/services/post_service.dart';
import '../../core/services/group_service.dart';
import '../../core/utils/firebase_error_message.dart';
import '../../core/widgets/post_media.dart';
import '../../core/widgets/member_avatar.dart';

/// หน้าสร้างและแก้ไขโพสต์ข้อความ พร้อมแท็ก ระดับการมองเห็น และสื่อหนึ่งไฟล์
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    required this.user,
    this.post,
    this.groupId,
    this.postService,
    this.groupService,
    this.imagePicker,
    this.authorAvatar,
    super.key,
  });

  /// บัญชีที่ล็อกอินอยู่ ใช้ระบุเจ้าของโพสต์ใหม่
  final User user;

  /// เมื่อมีค่า หน้านี้จะเปิดในโหมดแก้ไขโพสต์เดิม
  final Post? post;

  /// เมื่อระบุกลุ่ม ฟอร์มใช้สิทธิ์และพื้นที่จัดเก็บของกลุ่มแทนโพสต์สาธารณะ
  final String? groupId;

  // ส่งบริการแยกเข้ามาได้ เพื่อทดสอบฟอร์มจริงโดยไม่ส่งโพสต์ไป production
  final PostService? postService;
  final GroupService? groupService;
  final ImagePicker? imagePicker;
  // เปิดทางให้ widget test ใส่ avatar ปลอมได้โดยไม่ต้องต่อ Firebase
  final Widget? authorAvatar;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();
  late final _postService = widget.postService ?? PostService();
  late final _groupService = widget.groupService ?? GroupService();
  late final _picker = widget.imagePicker ?? ImagePicker();

  XFile? _attachment;
  Uint8List? _attachmentPreview;
  bool _removeExistingMedia = false;
  bool _isSaving = false;
  late String _visibility;
  late List<String> _taggedUserIds;
  final Map<String, String> _taggedUserNames = {};

  bool get _isEditing => widget.post != null;

  @override
  void initState() {
    super.initState();
    final post = widget.post;
    _contentController.text = post?.content ?? '';
    _tagsController.text = post?.tags.map((tag) => '#$tag').join(', ') ?? '';
    _visibility = post?.visibility == 'followers'
        ? 'public'
        : post?.visibility ?? 'public';
    _taggedUserIds = [...?post?.taggedUserIds];
    if (_taggedUserIds.isNotEmpty) _loadTaggedUserNames();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('กรุณาเลือกรูปขนาดไม่เกิน 10 MB');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachment = file;
        _attachmentPreview = bytes;
        _removeExistingMedia = false;
      });
    } catch (error) {
      _showError('เลือกรูปไม่สำเร็จ: $error');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      if (await file.length() > 50 * 1024 * 1024) {
        throw const FormatException('กรุณาเลือกวิดีโอขนาดไม่เกิน 50 MB');
      }
      if (!mounted) return;
      setState(() {
        _attachment = file;
        _attachmentPreview = null;
        _removeExistingMedia = false;
      });
    } catch (error) {
      _showError('เลือกวิดีโอไม่สำเร็จ: $error');
    }
  }

  Future<void> _savePost() async {
    // กันกดจากปุ่มบนกับปุ่มล่างติดกันก่อนหน้าจอวาดสถานะกำลังบันทึก
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.groupId == null &&
        _visibility == 'private' &&
        _taggedUserIds.isNotEmpty) {
      _showError('เอาแท็กเพื่อนออกก่อน เพราะโพสต์ส่วนตัวเห็นได้เฉพาะคุณ');
      return;
    }
    setState(() => _isSaving = true);

    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    try {
      if (_taggedUserIds.any((uid) => !_taggedUserNames.containsKey(uid))) {
        await _loadTaggedUserNames();
      }
      if (widget.groupId != null) {
        final groups = _groupService;
        if (_isEditing) {
          await groups.updatePost(
            groupId: widget.groupId!,
            postId: widget.post!.id,
            content: _contentController.text,
            tags: tags,
            taggedUserIds: _taggedUserIds,
            newAttachment: _attachment,
            removeMedia: _removeExistingMedia,
          );
        } else {
          await groups.addPost(
            groupId: widget.groupId!,
            content: _contentController.text,
            tags: tags,
            taggedUserIds: _taggedUserIds,
            attachment: _attachment,
          );
        }
      } else if (_isEditing) {
        await _postService.updatePost(
          postId: widget.post!.id,
          content: _contentController.text,
          tags: tags,
          taggedUserIds: _taggedUserIds,
          visibility: _visibility,
          oldMediaPath: widget.post!.mediaPath,
          oldThumbnailPath: widget.post!.thumbnailPath,
          newAttachment: _attachment,
          removeMedia: _removeExistingMedia,
        );
      } else {
        await _postService.createPost(
          content: _contentController.text,
          tags: tags,
          taggedUserIds: _taggedUserIds,
          visibility: _visibility,
          attachment: _attachment,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostServiceException catch (error) {
      _showError(error.message);
    } on GroupServiceException catch (error) {
      _showError(error.message);
    } catch (error) {
      // แยกสาเหตุจริง เช่น สิทธิ์ เครือข่าย หรือปลั๊กอินขาด แทนข้อความรวมที่เดาไม่ได้
      debugPrint('Save post failed (${error.runtimeType}): $error');
      _showError(firebaseErrorMessage(error, action: 'บันทึกโพสต์'));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // เลือกได้เฉพาะคนที่ติดตามกันหรือสมาชิกกลุ่ม และ backend จะตรวจซ้ำก่อนบันทึก
  Future<void> _pickTaggedPeople() async {
    if (_visibility == 'private' && widget.groupId == null) {
      if (_taggedUserIds.isNotEmpty) {
        setState(() {
          _taggedUserIds.clear();
          _taggedUserNames.clear();
        });
        _showError('เอาแท็กเพื่อนออกแล้ว เพราะโพสต์ส่วนตัวเห็นได้เฉพาะคุณ');
        return;
      }
      _showError('โพสต์ส่วนตัวเห็นได้เฉพาะคุณ จึงแท็กเพื่อนไม่ได้');
      return;
    }
    try {
      final db = FirebaseFirestore.instance;
      final candidates = <String>{};
      if (widget.groupId != null) {
        final members = await db
            .collection('groups')
            .doc(widget.groupId)
            .collection('members')
            .limit(100)
            .get();
        candidates.addAll(members.docs.map((doc) => doc.id));
      } else {
        final results = await Future.wait([
          db
              .collection('users')
              .doc(widget.user.uid)
              .collection('followers')
              .limit(100)
              .get(),
          db
              .collection('users')
              .doc(widget.user.uid)
              .collection('following')
              .limit(100)
              .get(),
        ]);
        for (final result in results) {
          candidates.addAll(result.docs.map((doc) => doc.id));
        }
      }
      candidates.remove(widget.user.uid);
      final people = <({String uid, String name})>[];
      final checked = await Future.wait(
        candidates.map((uid) async {
          final results = await Future.wait([
            db.collection('users').doc(uid).get(),
            db.collection('block_edges').doc('${widget.user.uid}_$uid').get(),
            db.collection('block_edges').doc('${uid}_${widget.user.uid}').get(),
          ]);
          final user = results[0].data();
          if (user == null || results[1].exists || results[2].exists) {
            return null;
          }
          final name = user['displayName'] is String
              ? (user['displayName'] as String).trim()
              : '';
          return (uid: uid, name: name.isEmpty ? 'สมาชิก' : name);
        }),
      );
      people.addAll(checked.whereType<({String uid, String name})>());
      people.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      final selected = Set<String>.of(_taggedUserIds);
      final unavailable = selected
          .where((uid) => !people.any((person) => person.uid == uid))
          .toList();
      final result = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'แท็กเพื่อน (${selected.length}/10)',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, selected),
                          child: const Text('เสร็จ'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: people.isEmpty && unavailable.isEmpty
                        ? const Center(
                            child: Text('ยังไม่มีเพื่อนหรือสมาชิกที่แท็กได้'),
                          )
                        : ListView.builder(
                            itemCount: people.length + unavailable.length,
                            itemBuilder: (context, index) {
                              if (index >= unavailable.length) {
                                final person =
                                    people[index - unavailable.length];
                                final checked = selected.contains(person.uid);
                                return CheckboxListTile(
                                  secondary: MemberAvatar(
                                    uid: person.uid,
                                    radius: 21,
                                  ),
                                  title: Text(person.name),
                                  value: checked,
                                  onChanged: (value) {
                                    setSheetState(() {
                                      if (value == true &&
                                          selected.length < 10) {
                                        selected.add(person.uid);
                                      }
                                      if (value != true) {
                                        selected.remove(person.uid);
                                      }
                                    });
                                  },
                                );
                              }
                              final uid = unavailable[index];
                              return CheckboxListTile(
                                secondary: MemberAvatar(uid: uid, radius: 21),
                                title: const Text('บัญชีที่เลือกไว้ก่อนหน้า'),
                                subtitle: Text(uid),
                                value: true,
                                onChanged: (_) =>
                                    setSheetState(() => selected.remove(uid)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (result != null && mounted) {
        final nextIds = result.toList();
        final names = {for (final person in people) person.uid: person.name};
        for (final uid in nextIds) {
          if (!names.containsKey(uid)) {
            final profile = await db.collection('users').doc(uid).get();
            final name = profile.data()?['displayName'];
            names[uid] = name is String && name.trim().isNotEmpty
                ? name.trim()
                : 'สมาชิก';
          }
        }
        setState(() {
          _taggedUserIds = nextIds;
          _taggedUserNames
            ..clear()
            ..addAll(names);
        });
        // Keep names out of the editable body. The post renderer adds @names
        // from the selected IDs, so removing a chip never deletes typed text.
      }
    } catch (error) {
      _showError(firebaseErrorMessage(error, action: 'โหลดรายชื่อสำหรับแท็ก'));
    }
  }

  Future<void> _loadTaggedUserNames() async {
    final db = FirebaseFirestore.instance;
    final selectedIds = List<String>.of(_taggedUserIds);
    try {
      final profiles = await Future.wait(
        selectedIds.map((uid) => db.collection('users').doc(uid).get()),
      );
      if (!mounted) return;
      setState(() {
        for (var index = 0; index < profiles.length; index++) {
          final value = profiles[index].data()?['displayName'];
          _taggedUserNames[selectedIds[index]] =
              value is String && value.trim().isNotEmpty
              ? value.trim()
              : 'สมาชิก';
        }
      });
    } catch (_) {
      // Keep existing tags removable even if profile names cannot be fetched.
    }
  }

  void _removeTaggedUser(String uid) {
    setState(() {
      _taggedUserIds.remove(uid);
      _taggedUserNames.remove(uid);
    });
  }

  void _clearAttachment() {
    final hadReplacement = _attachment != null;
    setState(() {
      _attachment = null;
      _attachmentPreview = null;
      // ปิดไฟล์ใหม่แล้วคืนสื่อเดิม; ถ้าปิดสื่อเดิมจึงค่อยทำเครื่องหมายลบ
      if (!hadReplacement && widget.post?.mediaPath != null) {
        _removeExistingMedia = true;
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.displayName?.trim();
    final authorName = displayName == null || displayName.isEmpty
        ? 'สมาชิก'
        : displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'แก้ไขโพสต์' : 'สร้างโพสต์'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _savePost,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'บันทึก' : 'โพสต์'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  widget.authorAvatar ??
                      MemberAvatar(uid: widget.user.uid, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      authorName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (widget.groupId != null)
                    const Chip(label: Text('สมาชิกกลุ่ม')),
                ],
              ),
              if (widget.groupId == null) ...[
                const SizedBox(height: 12),
                // แยกช่องสิทธิ์จากชื่อผู้เขียนให้ข้อความครบและไม่ล้นจอโทรศัพท์เล็ก
                DropdownButtonFormField<String>(
                  initialValue: _visibility,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ผู้ที่เห็นโพสต์',
                  ),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _visibility = value);
                          }
                        },
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('สาธารณะ')),
                    DropdownMenuItem(value: 'private', child: Text('เฉพาะฉัน')),
                  ],
                ),
              ],
              // แสดงคำอธิบายเฉพาะตัวเลือกส่วนตัว ให้ตัวเลือกสาธารณะกระชับ
              if (widget.groupId == null && _visibility == 'private')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'โพสต์นี้เห็นได้เฉพาะคุณ แม้จะเปลี่ยนโปรไฟล์เป็นสาธารณะ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                minLines: 4,
                maxLines: 10,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                // ไม่ตั้ง input formatter จึงพิมพ์ได้ทั้งตัวพิมพ์ใหญ่และอิโมจิ
                decoration: const InputDecoration(
                  hintText: 'คุณกำลังคิดอะไรอยู่?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsController,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: 'แท็ก',
                  hintText: '#ท่องเที่ยว, #อาหาร',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final tags = (value ?? '')
                      .split(',')
                      .map((tag) => tag.trim())
                      .where((tag) => tag.isNotEmpty)
                      .toSet();
                  return tags.length > 5 ? 'ใส่แท็กได้ไม่เกิน 5 รายการ' : null;
                },
              ),
              if (widget.groupId != null ||
                  _visibility != 'private' ||
                  _taggedUserIds.isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickTaggedPeople,
                    icon: Icon(
                      _visibility == 'private' && widget.groupId == null
                          ? Icons.person_remove_alt_1_outlined
                          : Icons.person_add_alt_1_outlined,
                    ),
                    label: Text(
                      _visibility == 'private' &&
                              widget.groupId == null &&
                              _taggedUserIds.isNotEmpty
                          ? 'เอาแท็กเพื่อนออก'
                          : _taggedUserIds.isEmpty
                          ? 'แท็กเพื่อน'
                          : 'แท็กเพื่อน (${_taggedUserIds.length})',
                    ),
                  ),
                ),
              ],
              if (_taggedUserIds.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: _taggedUserIds
                      .map(
                        (uid) => InputChip(
                          avatar: MemberAvatar(uid: uid, radius: 11),
                          label: Text('@${_taggedUserNames[uid] ?? 'สมาชิก'}'),
                          onDeleted: _isSaving
                              ? null
                              : () => _removeTaggedUser(uid),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (widget.post?.sharedPostId != null)
                SharedPostCard(postId: widget.post!.sharedPostId!),
              const SizedBox(height: 8),
              if (_attachment != null ||
                  (widget.post?.mediaPath != null && !_removeExistingMedia))
                _buildAttachmentPreview(context),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('เพิ่มภาพ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('เพิ่มวิดีโอ'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSaving ? null : _savePost,
                icon: const Icon(Icons.send_rounded),
                label: Text(_isEditing ? 'บันทึกการแก้ไข' : 'โพสต์'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(BuildContext context) {
    final file = _attachment;
    final existingPost = widget.post;
    final isVideo = file != null
        ? (file.mimeType?.startsWith('video/') ??
              RegExp(
                r'\.(mp4|mov|webm|mkv)$',
                caseSensitive: false,
              ).hasMatch(file.name))
        : existingPost?.mediaType == 'video';

    return Card(
      child: Column(
        children: [
          if (_attachmentPreview != null)
            Image.memory(
              _attachmentPreview!,
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          else if (file == null && !isVideo)
            PostMedia(
              path: existingPost!.mediaPath!,
              type: existingPost.mediaType,
              thumbnailPath: existingPost.thumbnailPath,
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Icon(
                isVideo ? Icons.video_file_outlined : Icons.image_outlined,
                size: 48,
              ),
            ),
          ListTile(
            leading: Icon(isVideo ? Icons.videocam_outlined : Icons.image),
            title: Text(
              file?.name ?? (isVideo ? 'วิดีโอที่แนบอยู่' : 'ภาพที่แนบอยู่'),
            ),
            trailing: IconButton(
              tooltip: 'เอาสื่อออก',
              onPressed: _isSaving ? null : _clearAttachment,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}
