import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// แสดงชื่อจากโปรไฟล์ล่าสุด และใช้ชื่อที่บันทึกมากับโพสต์เป็นค่ารอง
class LiveProfileName extends StatelessWidget {
  const LiveProfileName({
    super.key,
    required this.uid,
    required this.fallbackName,
    this.prefix = '',
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String uid;
  final String fallbackName;
  final String prefix;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    // โพสต์เก่าเก็บชื่อไว้เป็น snapshot จึงอ่าน users/{uid} เพื่อให้ชื่อใหม่
    // ปรากฏกับโพสต์เดิมโดยไม่ต้องแก้เอกสารโพสต์ทีละรายการ
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, snapshot) {
      final currentName = snapshot.data?.data()?['displayName'];
      final name = currentName is String && currentName.trim().isNotEmpty
          ? currentName.trim()
          : fallbackName.trim();
      return Text(
        '$prefix${name.isEmpty ? 'สมาชิก' : name}',
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      );
    },
  );
}
