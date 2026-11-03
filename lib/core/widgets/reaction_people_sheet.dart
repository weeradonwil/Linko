import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/reaction_summary.dart';
import '../models/social_reaction.dart';
import '../services/follow_service.dart';
import '../../screens/profile/profile.dart';
import 'member_avatar.dart';

/// กดที่ยอดเพื่อดูคนกด ปุ่ม Like ด้านล่างยังใช้เปลี่ยนอารมณ์เหมือนเดิม
class ReactionSummaryBar extends StatelessWidget {
  const ReactionSummaryBar({
    super.key,
    required this.counts,
    required this.path,
  });
  final Map<String, int> counts;
  final String path;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: ReactionSummary.visible(counts).entries
        .map(
          (entry) => TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 36),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => FractionallySizedBox(
                heightFactor: .8,
                child: ReactionPeopleSheet(path: path, initial: entry.key),
              ),
            ),
            child: Text(
              '${entry.key == 'other' ? 'อื่นๆ' : SocialReaction.byId(entry.key)?.emoji ?? ''} ${entry.value}',
            ),
          ),
        )
        .toList(),
  );
}

class ReactionPeopleSheet extends StatefulWidget {
  const ReactionPeopleSheet({super.key, required this.path, this.initial});
  final String path;
  final String? initial;
  @override
  State<ReactionPeopleSheet> createState() => _ReactionPeopleSheetState();
}

class _ReactionPeopleSheetState extends State<ReactionPeopleSheet> {
  String? _filter;
  final _docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _loading = false;
  bool _more = true;
  Object? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (reset) {
      _version++;
      _docs.clear();
      _more = true;
    }
    final version = _version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection(widget.path)
          .orderBy('updatedAt', descending: true);
      if (_filter == 'other') {
        query = query.where(
          'reaction',
          whereIn: const ['like', 'love', 'haha', 'wow', 'sad', 'angry'],
        );
      } else if (_filter != null) {
        query = query.where('reaction', isEqualTo: _filter);
      }
      if (_docs.isNotEmpty) query = query.startAfterDocument(_docs.last);
      final page = await query.limit(30).get();
      // กดเปลี่ยนแท็บเร็วๆ ผลของแท็บเก่าต้องไม่ไหลเข้ามาปนกัน
      if (!mounted || version != _version) return;
      setState(() {
        _docs.addAll(page.docs);
        _more = page.docs.length == 30;
      });
    } catch (error) {
      if (mounted && version == _version) setState(() => _error = error);
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 12),
      Row(
        children: [
          const SizedBox(width: 16),
          const Expanded(child: Text('คนที่แสดงความรู้สึก')),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final id in <String?>[
              null,
              'other',
              ...SocialReaction.options.map((item) => item.id),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    id == null
                        ? 'ทั้งหมด'
                        : id == 'other'
                        ? 'อื่นๆ'
                        : SocialReaction.byId(id)!.emoji,
                  ),
                  selected: _filter == id,
                  onSelected: (_) {
                    _filter = id;
                    _load(reset: true);
                  },
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: _error != null
            ? Center(
                child: TextButton(
                  onPressed: () => _load(),
                  child: const Text('โหลดไม่สำเร็จ แตะเพื่อลองใหม่'),
                ),
              )
            : _docs.isEmpty && !_loading
            ? const Center(child: Text('ยังไม่มีรายการในหมวดนี้'))
            : ListView.builder(
                itemCount: _docs.length + 1,
                itemBuilder: (context, index) {
                  if (index == _docs.length) {
                    return _loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _more
                        ? TextButton(
                            onPressed: () => _load(),
                            child: const Text('โหลดเพิ่ม'),
                          )
                        : const SizedBox(height: 20);
                  }
                  final doc = _docs[index];
                  final user = FirebaseAuth.instance.currentUser!;
                  final reaction = SocialReaction.byId(
                    doc.data()['reaction'] as String?,
                  );
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(doc.id)
                        .snapshots(),
                    builder: (context, profile) => ListTile(
                      leading: Stack(
                        children: [
                          MemberAvatar(uid: doc.id),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Text(reaction?.emoji ?? ''),
                          ),
                        ],
                      ),
                      title: Text(
                        profile.data?.data()?['displayName'] as String? ??
                            'สมาชิก',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProfileScreen(user: user, profileUid: doc.id),
                        ),
                      ),
                      trailing: doc.id == user.uid
                          ? null
                          : StreamBuilder<bool>(
                              stream: FollowService().watchIsFollowing(doc.id),
                              builder: (context, following) => TextButton(
                                onPressed: () async {
                                  try {
                                    if (following.data == true) {
                                      await FollowService().unfollow(doc.id);
                                    } else {
                                      await FollowService().requestFollow(
                                        doc.id,
                                      );
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'ติดตามไม่สำเร็จ บัญชีอาจเป็นส่วนตัวหรือบล็อกกันอยู่',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                                child: Text(
                                  following.data == true
                                      ? 'เลิกติดตาม'
                                      : 'ติดตาม',
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
