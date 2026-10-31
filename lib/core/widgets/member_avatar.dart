import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// โหลดจากโปรไฟล์จริง มีตัวอักษรสำรองเวลาไม่มีรูปหรือเปิดไฟล์ไม่ได้
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.uid, this.radius = 22});
  final String uid;
  final double radius;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final name =
              (data?['displayName'] is String
                      ? data!['displayName'] as String
                      : 'สมาชิก')
                  .trim();
          final path = data?['avatarPath'];
          final fallback = Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          );
          if (path is! String || path.isEmpty) {
            return CircleAvatar(radius: radius, child: fallback);
          }
          return FutureBuilder<String>(
            future: FirebaseStorage.instance.ref(path).getDownloadURL(),
            builder: (context, image) => CircleAvatar(
              radius: radius,
              backgroundImage: image.hasData ? NetworkImage(image.data!) : null,
              child: image.hasData ? null : fallback,
            ),
          );
        },
      );
}
