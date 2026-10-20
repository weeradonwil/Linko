// ฟอร์มสร้างหรือแก้ไขโพสต์ พร้อมจัดการข้อความ แท็ก การมองเห็น และไฟล์แนบ
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/post.dart';
import '../../core/services/post_service.dart';
import '../../core/widgets/post_media.dart';

/// หน้าสร้างและแก้ไขโพสต์ข้อความ พร้อมแท็ก ระดับการมองเห็น และสื่อหนึ่งไฟล์
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({required this.user, this.post, super.key});

  /// บัญชีที่ล็อกอินอยู่ ใช้ระบุเจ้าของโพสต์ใหม่
  final User user;

  /// เมื่อมีค่า หน้านี้จะเปิดในโหมดแก้ไขโพสต์เดิม
  final Post? post;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();
  final _postService = PostService();
  final _picker = ImagePicker();

  XFile? _attachment;
  Uint8List? _attachmentPreview;
  bool _removeExistingMedia = false;
  bool _isSaving = false;
  late String _visibility;

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
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _attachment = file;
      _attachmentPreview = bytes;
      _removeExistingMedia = false;
    });
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _attachment = file;
      _attachmentPreview = null;
      _removeExistingMedia = false;
    });
  }

  Future<void> _savePost() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    try {
      if (_isEditing) {
        await _postService.updatePost(
          postId: widget.post!.id,
          content: _contentController.text,
          tags: tags,
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
          visibility: _visibility,
          attachment: _attachment,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostServiceException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError(
        'บันทึกโพสต์ไม่สำเร็จ ตรวจอินเทอร์เน็ต, Firebase Storage และ Firestore Rules',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
                  CircleAvatar(child: Text(authorName.characters.first)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      authorName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  DropdownButton<String>(
                    value: _visibility,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _visibility = value);
                            }
                          },
                    items: const [
                      DropdownMenuItem(value: 'public', child: Text('สาธารณะ')),
                      DropdownMenuItem(
                        value: 'private',
                        child: Text('ส่วนตัว'),
                      ),
                    ],
                  ),
                ],
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
                  helperText: 'ใส่แท็กได้สูงสุด 5 รายการ คั่นด้วยจุลภาค',
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
              const SizedBox(height: 8),
              Text(
                'แนบได้ครั้งละ 1 ไฟล์: ภาพไม่เกิน 10 MB หรือวิดีโอไม่เกิน 50 MB',
                style: Theme.of(context).textTheme.bodySmall,
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
