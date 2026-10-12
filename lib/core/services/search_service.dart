import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post.dart';

/// ค้นหาจากข้อมูล Firestore ที่มีอยู่ โดยไม่สร้างดัชนีค้นหาแยก
class SearchService {
  SearchService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<List<Map<String, dynamic>>> recentUsers({int limit = 20}) async {
    final uid = _auth.currentUser?.uid;
    final s = await _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit + 1)
        .get();
    return s.docs
        .where((d) => d.id != uid)
        .map((d) => {'uid': d.id, ...d.data()})
        .toList();
  }

  /// ใช้ displayNameLower สำหรับ prefix search และ fallback ไปชื่อเดิม
  /// เพื่อให้บัญชีเก่าที่ยังไม่มีฟิลด์นี้ค้นหาเจอ
  Future<List<Map<String, dynamic>>> searchUsers(String value) async {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) return recentUsers();
    final uid = _auth.currentUser?.uid;
    final results = <String, Map<String, dynamic>>{};
    try {
      final s = await _firestore
          .collection('users')
          .orderBy('displayNameLower')
          .startAt([q])
          .endAt([q + String.fromCharCode(0xf8ff)])
          .limit(30)
          .get();
      for (final d in s.docs) {
        if (d.id != uid) results[d.id] = {'uid': d.id, ...d.data()};
      }
    } on FirebaseException {}
    // Include older accounts that do not have displayNameLower yet.
    final legacy = await _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    for (final d in legacy.docs) {
      final name = (d.data()['displayName'] as String? ?? '').toLowerCase();
      if (d.id != uid && name.contains(q))
        results[d.id] = {'uid': d.id, ...d.data()};
    }
    return results.values.take(30).toList();
  }

  Future<List<Post>> recentPosts({int limit = 80}) async {
    final s = await _firestore
        .collection('posts')
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return s.docs.map(Post.fromSnapshot).toList();
  }

  /// กรองข้อความและแท็กจากโพสต์สาธารณะชุดล่าสุดที่โหลดมา
  Future<List<Post>> searchPosts(String value) async {
    final q = value.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
    if (q.isEmpty) return recentPosts(limit: 30);
    final posts = await recentPosts();
    return posts
        .where(
          (p) =>
              p.content.toLowerCase().contains(q) ||
              p.tags.any((t) => t.toLowerCase().contains(q)),
        )
        .toList();
  }

  // นับแท็กจากโพสต์สาธารณะล่าสุด แล้วคืนแท็กที่พบมากที่สุด
  Future<List<({String tag, int count})>> popularTags() async {
    final posts = await recentPosts(limit: 100);
    final counts = <String, int>{};
    for (final p in posts) {
      for (final t in p.tags) {
        counts.update(t, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final items = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return items.take(8).map((e) => (tag: e.key, count: e.value)).toList();
  }
}
