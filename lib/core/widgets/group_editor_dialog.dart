import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// The dialog owns its controllers until the route animation has finished.
class GroupDraft {
  const GroupDraft(this.name, this.description, this.visibility, this.avatar);
  final String name;
  final String description;
  final String visibility;
  final XFile? avatar;
}

class GroupEditorDialog extends StatefulWidget {
  const GroupEditorDialog({
    super.key,
    this.initialName = '',
    this.initialDescription = '',
    this.initialVisibility = 'public',
    this.existingAvatar,
    this.editing = false,
  });
  final String initialName;
  final String initialDescription;
  final String initialVisibility;
  final Widget? existingAvatar;
  final bool editing;

  @override
  State<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<GroupEditorDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );
  late String _visibility = widget.initialVisibility;
  XFile? _avatar;
  Uint8List? _preview;
  bool _picking = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 900,
        maxHeight: 900,
      );
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw StateError('กรุณาเลือกรูปขนาดไม่เกิน 5 MB');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatar = file;
        _preview = bytes;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'เลือกรูปไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'กรุณาระบุชื่อกลุ่ม');
      return;
    }
    Navigator.pop(
      context,
      GroupDraft(
        _name.text.trim(),
        _description.text.trim(),
        _visibility,
        _avatar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.editing ? 'แก้ไขกลุ่ม' : 'สร้างกลุ่ม'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_preview != null)
            CircleAvatar(radius: 38, backgroundImage: MemoryImage(_preview!))
          else
            widget.existingAvatar ??
                const CircleAvatar(
                  radius: 38,
                  child: Icon(Icons.groups_2_outlined, size: 28),
                ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _picking ? null : _pickAvatar,
            icon: const Icon(Icons.photo_outlined, size: 18),
            label: Text(_picking ? 'กำลังเลือกรูป' : 'เลือกรูปประจำกลุ่ม'),
          ),
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม'),
          ),
          TextField(
            controller: _description,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'คำอธิบาย'),
          ),
          if (!widget.editing) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _visibility,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ประเภทกลุ่ม'),
              items: const [
                DropdownMenuItem(value: 'public', child: Text('สาธารณะ')),
                DropdownMenuItem(value: 'private', child: Text('ส่วนตัว')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _visibility = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _visibility == 'public'
                  ? 'ค้นหาและเข้าร่วมได้ทันที'
                  : 'ดูเนื้อหาได้หลังเจ้าของอนุมัติคำขอเข้าร่วม',
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: _picking ? null : _submit,
        child: Text(widget.editing ? 'บันทึก' : 'สร้าง'),
      ),
    ],
  );
}
