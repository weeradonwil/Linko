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
          return _MemberAvatarImage(
            key: ValueKey(path),
            path: path,
            radius: radius,
            fallback: fallback,
          );
        },
      );
}

/// Keeps one Storage request for each image path, so profile stream updates
/// replace the displayed image without restarting the same request on rebuild.
class _MemberAvatarImage extends StatefulWidget {
  const _MemberAvatarImage({
    super.key,
    required this.path,
    required this.radius,
    required this.fallback,
  });

  final String path;
  final double radius;
  final Widget fallback;

  @override
  State<_MemberAvatarImage> createState() => _MemberAvatarImageState();
}

class _MemberAvatarImageState extends State<_MemberAvatarImage> {
  late Future<String> _downloadUrl = _loadUrl();

  Future<String> _loadUrl() =>
      FirebaseStorage.instance.ref(widget.path).getDownloadURL();

  @override
  void didUpdateWidget(covariant _MemberAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _downloadUrl = _loadUrl();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _downloadUrl,
    builder: (context, image) => CircleAvatar(
      radius: widget.radius,
      child: image.hasData && !image.hasError
          ? ClipOval(
              child: Image.network(
                image.data!,
                width: widget.radius * 2,
                height: widget.radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => widget.fallback,
              ),
            )
          : widget.fallback,
    ),
  );
}
