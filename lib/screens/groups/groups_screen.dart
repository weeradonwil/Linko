// รายการกลุ่มที่ค้นพบได้ พร้อมสร้างกลุ่มและเปิดหน้าสนทนาในกลุ่ม
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/social_group.dart';
import '../../core/services/group_service.dart';

/// แสดงกลุ่มสาธารณะและเปิดทางสร้างกลุ่มใหม่
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.user});
  final User user;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _service = GroupService();

  Future<void> _createGroup() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('สร้างกลุ่ม'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม'),
            ),
            TextField(
              controller: description,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'คำอธิบาย'),
            ),
            const SizedBox(height: 8),
            const Text(
              'กลุ่มใหม่เป็นกลุ่มสาธารณะ สมาชิกทุกคนค้นหาและเข้าร่วมได้',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );
    if (create == true) {
      try {
        await _service.createGroup(
          name: name.text,
          description: description.text,
          visibility: 'public',
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    name.dispose();
    description.dispose();
  }

  void _openGroup(SocialGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(user: widget.user, group: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('กลุ่ม'),
      actions: [
        IconButton(
          tooltip: 'สร้างกลุ่ม',
          onPressed: _createGroup,
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
    ),
    body: StreamBuilder<List<SocialGroup>>(
      stream: _service.watchDiscoverableGroups(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('โหลดกลุ่มไม่สำเร็จ ตรวจ Rules และการเชื่อมต่อ'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data!;
        if (groups.isEmpty) return const _GroupsEmpty();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _GroupCard(
            group: groups[index],
            onTap: () => _openGroup(groups[index]),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createGroup,
      icon: const Icon(Icons.add),
      label: const Text('สร้างกลุ่ม'),
    ),
  );
}

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.user, required this.group});
  final User user;
  final SocialGroup group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _service = GroupService();
  final _postController = TextEditingController();
  late SocialGroup _group;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _sendPost() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _service.addPost(groupId: _group.id, content: _postController.text);
      _postController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editGroup() async {
    final name = TextEditingController(text: _group.name);
    final description = TextEditingController(text: _group.description);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขกลุ่ม'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม'),
            ),
            TextField(
              controller: description,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'คำอธิบาย'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await _service.updateGroup(
          groupId: _group.id,
          name: name.text,
          description: description.text,
        );
        final updated = await FirebaseFirestore.instance
            .collection('groups')
            .doc(_group.id)
            .get();
        if (mounted && updated.exists) {
          setState(() => _group = SocialGroup.fromSnapshot(updated));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    name.dispose();
    description.dispose();
  }

  Future<void> _membershipAction(bool isMember) async {
    try {
      if (isMember) {
        await _service.leaveGroup(_group);
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        await _service.joinGroup(_group);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  /// ขอคำยืนยันก่อนลบกลุ่ม รวมถึงสมาชิกและโพสต์ที่อยู่ภายในกลุ่ม
  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบกลุ่มนี้?'),
        content: const Text('สมาชิกและโพสต์ทั้งหมดในกลุ่มจะถูกลบถาวร'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบกลุ่ม'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteGroup(_group.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ลบกลุ่มไม่สำเร็จ: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final isOwner = group.ownerId == widget.user.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (isOwner)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _editGroup();
                if (action == 'delete') _deleteGroup();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('แก้ไขกลุ่ม')),
                PopupMenuItem(value: 'delete', child: Text('ลบกลุ่ม')),
              ],
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.watchMembers(group.id),
        builder: (context, memberSnapshot) {
          if (memberSnapshot.hasError) {
            return const Center(child: Text('โหลดสมาชิกกลุ่มไม่สำเร็จ'));
          }
          final members = memberSnapshot.data?.docs ?? const [];
          final isMember = members.any(
            (member) => member.id == widget.user.uid,
          );
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.description.isEmpty
                            ? 'กลุ่มสำหรับพูดคุยและแบ่งปันเรื่องราว'
                            : group.description,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${memberSnapshot.data?.docs.length ?? 0} สมาชิก',
                          ),
                          const Spacer(),
                          if (isOwner)
                            const Chip(label: Text('เจ้าของ'))
                          else if (isMember)
                            OutlinedButton(
                              onPressed: () => _membershipAction(true),
                              child: const Text('ออกจากกลุ่ม'),
                            )
                          else
                            FilledButton(
                              onPressed: () => _membershipAction(false),
                              child: const Text('เข้าร่วม'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMember)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _postController,
                          maxLength: 1000,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'เขียนโพสต์ในกลุ่ม',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _sendPost,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !isMember
                    ? const Center(
                        child: Text('เข้าร่วมกลุ่มเพื่อดูโพสต์และเขียนข้อความ'),
                      )
                    : StreamBuilder<List<GroupPost>>(
                        stream: _service.watchPosts(group.id),
                        builder: (context, postSnapshot) {
                          if (postSnapshot.hasError) {
                            return const Center(
                              child: Text('โหลดโพสต์กลุ่มไม่สำเร็จ'),
                            );
                          }
                          if (!postSnapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final posts = postSnapshot.data!;
                          if (posts.isEmpty) {
                            return const Center(
                              child: Text('กลุ่มยังไม่มีโพสต์'),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: posts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _GroupPostCard(post: posts[index]),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});
  final SocialGroup group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(
          Icons.groups_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        group.description.isEmpty ? 'กลุ่มสาธารณะ' : group.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _GroupPostCard extends StatelessWidget {
  const _GroupPostCard({required this.post});
  final GroupPost post;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.authorName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SelectableText(post.content),
        ],
      ),
    ),
  );
}

class _GroupsEmpty extends StatelessWidget {
  const _GroupsEmpty();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text('ยังไม่มีกลุ่มสาธารณะ'),
          const SizedBox(height: 5),
          const Text('สร้างกลุ่มแรกหรือกลับมาดูภายหลัง'),
        ],
      ),
    ),
  );
}
