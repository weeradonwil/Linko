// หน้าเดียวสำหรับแก้ชื่อ รูปโปรไฟล์ และคำแนะนำตัว
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.user,
    required this.initialName,
    required this.initialBio,
    this.initialAvatarPath,
  });

  final User user;
  final String initialName;
  final String initialBio;
  final String? initialAvatarPath;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _picker = ImagePicker();
  XFile? _selectedAvatar;
  Uint8List? _selectedAvatarBytes;
  late final Future<String?> _initialAvatarUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _bioController.text = widget.initialBio;
    _initialAvatarUrl = _loadInitialAvatarUrl();
  }

  Future<String?> _loadInitialAvatarUrl() async {
    final path = widget.initialAvatarPath;
    if (path == null || path.isEmpty) return null;
    try {
      return await FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 900,
      maxHeight: 900,
    );
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB');
      }
      setState(() {
        _selectedAvatar = file;
        _selectedAvatarBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เปิดรูปไม่สำเร็จ: $error')));
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    if (name.isEmpty || name.length > 60 || bio.length > 160) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาตรวจสอบชื่อและคำแนะนำตัว')),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    String? uploadedPath;
    try {
      if (_selectedAvatar != null && _selectedAvatarBytes != null) {
        uploadedPath =
            'profile_images/${widget.user.uid}/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await FirebaseStorage.instance
            .ref(uploadedPath)
            .putData(
              _selectedAvatarBytes!,
              SettableMetadata(contentType: 'image/jpeg'),
            );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
            'displayName': name,
            'displayNameLower': name.toLowerCase(),
            'bio': bio,
            'avatarPath': ?uploadedPath,
          });

      var authNameSynced = true;
      try {
        await widget.user.updateDisplayName(name);
      } catch (_) {
        // Firestore is the profile source of truth; keep it saved even if the
        // authentication display name cannot be refreshed on this device.
        authNameSynced = false;
      }

      if (uploadedPath != null) {
        final oldPath = widget.initialAvatarPath;
        if (oldPath != null &&
            oldPath.startsWith('profile_images/${widget.user.uid}/')) {
          try {
            await FirebaseStorage.instance.ref(oldPath).delete();
          } catch (_) {
            // Keep the updated profile if old-file cleanup fails.
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(authNameSynced);
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await FirebaseStorage.instance.ref(uploadedPath).delete();
        } catch (_) {
          // Ignore cleanup errors and show the original save error.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกโปรไฟล์ไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _avatar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_selectedAvatarBytes != null) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: MemoryImage(_selectedAvatarBytes!),
      );
    }
    return FutureBuilder<String?>(
      future: _initialAvatarUrl,
      builder: (context, snapshot) => CircleAvatar(
        radius: 48,
        backgroundColor: colors.primaryContainer,
        backgroundImage: snapshot.data == null
            ? null
            : NetworkImage(snapshot.data!),
        child: snapshot.data == null
            ? Text(
                widget.initialName.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 34,
                  color: colors.onPrimaryContainer,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('แก้ไขโปรไฟล์')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              child: Column(
                children: [
                  _avatar(context),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseAvatar,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      _selectedAvatar == null
                          ? 'เปลี่ยนรูปโปรไฟล์'
                          : 'เลือกรูปอื่น',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            enabled: !_saving,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'ชื่อที่แสดง',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            enabled: !_saving,
            maxLength: 160,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'คำแนะนำตัว',
              hintText: 'เล่าเกี่ยวกับตัวคุณสั้น ๆ',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _saveProfile,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'กำลังบันทึก' : 'บันทึกโปรไฟล์'),
          ),
          const SizedBox(height: 10),
          Text(
            'ชื่อไม่เกิน 60 ตัวอักษร และคำแนะนำตัวไม่เกิน 160 ตัวอักษร',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
