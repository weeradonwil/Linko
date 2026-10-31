import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// อ่านทีละหน้า เก็บ cursor จากข้อมูลจริง แม้หน้านั้นจะไม่มีกลุ่มที่เราเป็นสมาชิก
class ShareDestinationPicker extends StatefulWidget {
  const ShareDestinationPicker({
    super.key,
    required this.kind,
    required this.uid,
    required this.selected,
    required this.busy,
    required this.onSelected,
  });
  final String kind;
  final String uid;
  final String? selected;
  final bool busy;
  final void Function(String id, String name) onSelected;

  @override
  State<ShareDestinationPicker> createState() => _ShareDestinationPickerState();
}

class _ShareDestinationPickerState extends State<ShareDestinationPicker> {
  final _items = <({String id, String name})>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _more = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final db = FirebaseFirestore.instance;
      Query<Map<String, dynamic>> query = switch (widget.kind) {
        'group' => db.collection('groups'),
        'following' =>
          db.collection('users').doc(widget.uid).collection('following'),
        _ =>
          db
              .collection('conversations')
              .where('participantIds', arrayContains: widget.uid),
      };
      query = query.orderBy(FieldPath.documentId).limit(30);
      if (_cursor != null) query = query.startAfterDocument(_cursor!);
      final page = await query.get();
      final rows = await Future.wait(
        page.docs.map((doc) async {
          if (widget.kind == 'group') {
            if (doc.data()['isDeleting'] == true) return null;
            final membership = await doc.reference
                .collection('members')
                .doc(widget.uid)
                .get();
            if (!membership.exists) return null;
            return (id: doc.id, name: doc.data()['name'] as String? ?? 'กลุ่ม');
          }
          if (widget.kind == 'following') {
            final profile = await db.collection('users').doc(doc.id).get();
            if (!profile.exists) return null;
            return (
              id: doc.id,
              name: profile.data()?['displayName'] as String? ?? 'สมาชิก',
            );
          }
          final peers = List<String>.from(
            doc.data()['participantIds'] as List? ?? [],
          );
          final peer = peers.where((id) => id != widget.uid).firstOrNull;
          if (peer == null) return null;
          final names = doc.data()['participantNames'] as Map? ?? {};
          return (id: doc.id, name: names[peer] as String? ?? 'สมาชิก');
        }),
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(rows.whereType<({String id, String name})>());
        if (page.docs.isNotEmpty) _cursor = page.docs.last;
        _more = page.docs.length == 30;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (_items.isEmpty && !_loading && !_failed)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _more
                ? 'ยังไม่พบในหน้านี้ ลองโหลดเพิ่มได้'
                : 'ยังไม่มีรายการให้เลือก',
            textAlign: TextAlign.center,
          ),
        ),
      for (final item in _items)
        CheckboxListTile(
          value: widget.selected == item.id,
          title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          onChanged: widget.busy
              ? null
              : (_) => widget.onSelected(item.id, item.name),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_failed) const Center(child: Text('โหลดรายชื่อไม่สำเร็จ')),
      if (!_loading && (_more || _failed))
        TextButton(
          onPressed: widget.busy ? null : _load,
          child: Text(_failed ? 'ลองอีกครั้ง' : 'โหลดเพิ่มเติม'),
        ),
    ],
  );
}
