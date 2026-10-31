import 'package:flutter/material.dart';

class PostReportDraft {
  const PostReportDraft(this.reason, this.details, {this.hidePost = true});
  final String reason;
  final String details;
  final bool hidePost;
}

class PostReportDialog extends StatefulWidget {
  const PostReportDialog({super.key});
  @override
  State<PostReportDialog> createState() => _PostReportDialogState();
}

class _PostReportDialogState extends State<PostReportDialog> {
  static const _reasons = [
    'สแปม',
    'คุกคามหรือกลั่นแกล้ง',
    'เนื้อหารุนแรง',
    'เนื้อหาทางเพศ',
    'ข้อมูลเท็จ',
    'อื่น ๆ',
  ];
  final _details = TextEditingController();
  String _reason = _reasons.first;
  bool _hide = true;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('รายงานโพสต์'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'เหตุผล'),
            items: _reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (r) {
              if (r != null) setState(() => _reason = r);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ซ่อนโพสต์นี้จากหน้าของฉันด้วย'),
            value: _hide,
            onChanged: (value) => setState(() => _hide = value ?? true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
            ),
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
        onPressed: () => Navigator.pop(
          context,
          PostReportDraft(_reason, _details.text.trim(), hidePost: _hide),
        ),
        child: const Text('ส่งรายงาน'),
      ),
    ],
  );
}
