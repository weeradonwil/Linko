// ค้นหาสมาชิก โพสต์ และแท็กจากข้อมูล Firestore ที่มีอยู่
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post.dart';
import '../utils/document_values.dart';

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
        .map((d) => _person(d.id, d.data()))
        .toList();
  }

  /// ใช้ displayNameLower สำหรับ prefix search และ fallback ไปชื่อเดิม
  /// เพื่อให้บัญชีเก่าที่ยังไม่มีฟิลด์นี้ค้นหาเจอ
  Future<List<Map<String, dynamic>>> searchUsers(String value) async {
    return (await searchUserPage(value)).users;
  }

  /// ค้นชื่อใหม่ด้วย index และไล่บัญชีเก่าทีละหน้า โดยไม่ตัดทิ้งหลัง 150 รายล่าสุด
  /// ใช้ document ID เป็น cursor เพื่อรวมบัญชีเก่าที่ไม่มี createdAt/displayNameLower ด้วย
  Future<UserSearchPage> searchUserPage(
    String value, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 100,
  }) async {
    final q = value.trim().toLowerCase();
    final uid = _auth.currentUser?.uid;
    final results = <String, Map<String, dynamic>>{};
    if (cursor == null && q.isNotEmpty) {
      final s = await _firestore
          .collection('users')
          .orderBy('displayNameLower')
          .startAt([q])
          .endAt([q + String.fromCharCode(0xf8ff)])
          .limit(30)
          .get();
      for (final d in s.docs) {
        if (d.id != uid) results[d.id] = _person(d.id, d.data());
      }
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final legacy = await query.get();
    for (final d in legacy.docs) {
      final name = readString(d.data()['displayName']).toLowerCase();
      if (d.id != uid && name.contains(q)) {
        results[d.id] = _person(d.id, d.data());
      }
    }
    return UserSearchPage(
      results.values.toList(),
      legacy.docs.isEmpty ? cursor : legacy.docs.last,
      legacy.docs.length == pageSize,
    );
  }

  Future<List<Post>> recentPosts({int limit = 80}) async {
    final s = await _firestore
        .collection('posts')
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return s.docs.map(Post.fromSnapshot).where((p) => !p.isDeleting).toList();
  }

  /// Each request scans a bounded page. Continue with the returned cursor
  /// even when this page contains no matching text.
  Future<PostSearchPage> searchPostPage(
    String value, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 80,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.get();
    final q = value.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
    final posts = snapshot.docs
        .map(Post.fromSnapshot)
        .where(
          (p) =>
              !p.isDeleting &&
              (q.isEmpty ||
                  p.content.toLowerCase().contains(q) ||
                  p.tags.any((tag) => tag.toLowerCase().contains(q))),
        )
        .toList();
    return PostSearchPage(
      posts,
      snapshot.docs.isEmpty ? cursor : snapshot.docs.last,
      snapshot.docs.length == pageSize,
    );
  }

  Map<String, dynamic> _person(String uid, Map<String, dynamic> data) {
    final name = readString(data['displayName']).trim();
    return {...data, 'uid': uid, 'displayName': name.isEmpty ? 'สมาชิก' : name};
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

/// ผลค้นหาสมาชิกหนึ่งหน้า พร้อมตำแหน่งสำหรับค้นต่อ แม้หน้านี้ไม่มีชื่อที่ตรงคำค้น
class UserSearchPage {
  const UserSearchPage(this.users, this.cursor, this.hasMore);
  final List<Map<String, dynamic>> users;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class PostSearchPage {
  const PostSearchPage(this.posts, this.cursor, this.hasMore);
  final List<Post> posts;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}
