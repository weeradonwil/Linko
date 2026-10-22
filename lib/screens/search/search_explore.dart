// หน้า Explore รวมคำค้น ตัวกรอง ผู้ใช้แนะนำ แท็กยอดนิยม และโพสต์ที่ค้นพบ
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/post.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/latest_request.dart';
import '../../core/services/search_service.dart';
import '../../core/widgets/post_media.dart';
import '../../core/widgets/social_navigation.dart';
import '../chat/chat_list.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile.dart';
import '../groups/groups_screen.dart';

class SearchExploreScreen extends StatefulWidget {
  const SearchExploreScreen({
    super.key,
    required this.user,
    this.isDarkMode = false,
    this.onToggleTheme,
  });
  final User user;
  final bool isDarkMode;
  final VoidCallback? onToggleTheme;
  @override
  State<SearchExploreScreen> createState() => _SearchExploreScreenState();
}

// เก็บคำค้น ตัวกรอง และผล Explore; ยกเลิก timer เดิมก่อนเริ่มค้นหาใหม่
class _SearchExploreScreenState extends State<SearchExploreScreen> {
  final _controller = TextEditingController();
  final _service = SearchService();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  final _requests = LatestRequest();
  DocumentSnapshot<Map<String, dynamic>>? _postCursor;
  bool _hasMorePosts = false;
  bool _loadingMore = false;
  int _filter = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Post> _posts = [];
  List<({String tag, int count})> _tags = [];
  static const _filters = ['ทั้งหมด', 'ผู้ใช้', 'แท็ก', 'โพสต์'];
  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _requests.next();
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // โหลดผู้ใช้ โพสต์ และแท็กพร้อมกันสำหรับหน้า Explore เริ่มต้น
  Future<void> _loadExplore() async {
    final request = _requests.next();
    setState(() {
      _loading = true;
      _loadingMore = false;
    });
    try {
      final results = await Future.wait([
        _service.recentUsers(),
        _service.searchPostPage('', pageSize: 30),
        _service.popularTags(),
      ]);
      if (!mounted || !_requests.accepts(request)) return;
      final page = results[1] as PostSearchPage;
      setState(() {
        _users = results[0] as List<Map<String, dynamic>>;
        _posts = page.posts;
        _postCursor = page.cursor;
        _hasMorePosts = page.hasMore;
        _tags = results[2] as List<({String tag, int count})>;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      _searchFailed(request, 'โหลดข้อมูลสำรวจไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  void _queueSearch() {
    _debounce?.cancel();
    _requests.next();
    setState(() {
      _loading = true;
      _loadingMore = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    _debounce?.cancel();
    final query = _controller.text.trim();
    final filter = _filter;
    if (query.isEmpty) {
      await _loadExplore();
      return;
    }
    final request = _requests.next();
    setState(() {
      _loading = true;
      _loadingMore = false;
    });
    try {
      final jobs = <Future<dynamic>>[];
      if (filter == 0 || filter == 1) jobs.add(_service.searchUsers(query));
      if (filter != 1) jobs.add(_service.searchPostPage(query));
      final values = await Future.wait(jobs);
      if (!mounted || !_requests.accepts(request)) return;
      var i = 0;
      final users = filter == 0 || filter == 1
          ? values[i++] as List<Map<String, dynamic>>
          : <Map<String, dynamic>>[];
      final page = filter != 1 ? values[i] as PostSearchPage : null;
      setState(() {
        _users = users;
        _posts = page?.posts ?? [];
        _postCursor = page?.cursor;
        _hasMorePosts = page?.hasMore ?? false;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      _searchFailed(request, 'ค้นหาไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  void _searchFailed(int request, String message) {
    if (!mounted || !_requests.accepts(request)) return;
    setState(() {
      _error = message;
      _loading = false;
      _loadingMore = false;
    });
  }

  Future<void> _loadMorePosts() async {
    if (_loading || _loadingMore || !_hasMorePosts) return;
    final request = _requests.version;
    final query = _controller.text.trim();
    setState(() => _loadingMore = true);
    try {
      final page = await _service.searchPostPage(query, cursor: _postCursor);
      if (!mounted || !_requests.accepts(request)) return;
      setState(() {
        _posts = {
          for (final post in [..._posts, ...page.posts]) post.id: post,
        }.values.toList();
        _postCursor = page.cursor;
        _hasMorePosts = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || !_requests.accepts(request)) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหลดโพสต์เพิ่มไม่สำเร็จ ลองอีกครั้งได้')),
      );
    }
  }

  Widget _loadMoreButton() => !_hasMorePosts || _filter == 1
      ? const SizedBox.shrink()
      : TextButton(
          onPressed: _loadingMore ? null : _loadMorePosts,
          child: Text(_loadingMore ? 'กำลังโหลด' : 'ค้นต่อในโพสต์เก่า'),
        );

  void _selectFilter(int index) {
    setState(() => _filter = index);
    _runSearch();
  }

  void _setTag(String tag) {
    _controller.text = '#$tag';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _filter = 2);
    _runSearch();
  }

  void _go(int i) {
    if (i == 0) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (i == 2) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatListScreen(
            user: widget.user,
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
          ),
        ),
      );
    } else if (i == 3) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsScreen(
            user: widget.user,
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
          ),
        ),
      );
    } else if (i == 1) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupsScreen(user: widget.user),
        ),
      );
    } else if (i == 4) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(user: widget.user),
        ),
      );
    }
  }

  void _openPerson(Map<String, dynamic> person) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          user: widget.user,
          profileUid: person['uid'] as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final query = _controller.text.trim();
    return ScrollNavigationVisibility(
      child: Scaffold(
        appBar: LinkoAppBar(
          onSearch: () => FocusScope.of(context).requestFocus(_searchFocus),
          onNotifications: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationsScreen(
                user: widget.user,
                isDarkMode: widget.isDarkMode,
                onToggleTheme: widget.onToggleTheme,
              ),
            ),
          ),
          isDarkMode: widget.isDarkMode,
          onToggleTheme: widget.onToggleTheme,
          onSignOut: () => AuthService().signOut(),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _searchFocus,
                onChanged: (_) => _queueSearch(),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'ค้นหาผู้ใช้ แท็ก หรือโพสต์ที่คุณสนใจ...',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            _loadExplore();
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text(_filters[i]),
                  selected: _filter == i,
                  onSelected: (_) => _selectFilter(i),
                  avatar: Icon(
                    [
                      Icons.people_outline,
                      Icons.person_outline,
                      Icons.tag,
                      Icons.article_outlined,
                    ][i],
                    size: 18,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Expanded(
                child: _Empty(
                  icon: Icons.cloud_off_outlined,
                  title: 'มีปัญหาในการโหลด',
                  detail: _error!,
                ),
              )
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: query.isEmpty && _filter == 0
                    ? _explore(context, c)
                    : _results(context, c, query),
              ),
          ],
        ),
        bottomNavigationBar: ScrollHidingNavigationBar(
          child: SocialBottomNavigation(selectedIndex: null, onTap: _go),
        ),
      ),
    );
  }

  Widget _explore(BuildContext context, ColorScheme c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: [
        _sectionTitle(
          context,
          Icons.local_fire_department_rounded,
          'แท็กจากโพสต์ล่าสุด',
        ),
        if (_tags.isEmpty)
          const _Hint(text: 'ยังไม่มีแท็กให้แสดง')
        else
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = _tags[i];
                return ActionChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${t.tag}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${t.count} โพสต์',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  onPressed: () => _setTag(t.tag),
                );
              },
            ),
          ),
        const SizedBox(height: 18),
        _sectionTitle(context, Icons.people_alt_outlined, 'สมาชิก'),
        if (_users.isEmpty)
          const _Hint(text: 'ยังไม่มีสมาชิกอื่นให้แนะนำ')
        else
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _users.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _personCard(context, _users[i]),
            ),
          ),
        const SizedBox(height: 18),
        _sectionTitle(context, Icons.explore_outlined, 'สำรวจโพสต์'),
        if (_posts.isEmpty)
          const _Hint(text: 'ยังไม่มีโพสต์สาธารณะให้สำรวจ')
        else
          ..._posts.map((p) => _postCard(context, p)),
        _loadMoreButton(),
      ],
    );
  }

  Widget _results(BuildContext context, ColorScheme c, String query) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      children: [
        if ((_filter == 0 || _filter == 1) && _users.isNotEmpty) ...[
          _sectionTitle(context, Icons.people_outline, 'ผู้ใช้'),
          ..._users.map((p) => _personRow(context, p)),
        ],
        if ((_filter == 0 || _filter == 2 || _filter == 3) &&
            _posts.isNotEmpty) ...[
          _sectionTitle(
            context,
            Icons.article_outlined,
            _filter == 2 ? 'โพสต์ที่มีแท็กหรือคำนี้' : 'โพสต์',
          ),
          ..._posts.map((p) => _postCard(context, p)),
        ],
        _loadMoreButton(),
        if (_users.isEmpty && _posts.isEmpty)
          _Empty(
            icon: Icons.search_off_rounded,
            title: 'ไม่พบผลการค้นหา',
            detail: _hasMorePosts
                ? 'ยังมีโพสต์เก่าให้ค้นต่อ กดปุ่มด้านบน'
                : 'ลองค้นหาด้วยคำหรือแท็กอื่น',
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 9),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
  Widget _personCard(BuildContext context, Map<String, dynamic> person) {
    final c = Theme.of(context).colorScheme;
    final name = person['displayName'] as String? ?? 'สมาชิก';
    return SizedBox(
      width: 122,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: c.primary.withValues(alpha: .16),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: TextStyle(color: c.primary, fontSize: 21),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: FilledButton(
                  onPressed: () => _openPerson(person),
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text(
                    'ดูโปรไฟล์',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personRow(BuildContext context, Map<String, dynamic> person) {
    final name = person['displayName'] as String? ?? 'สมาชิก';
    final c = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.primary.withValues(alpha: .16),
          child: Text(
            name.characters.first.toUpperCase(),
            style: TextStyle(color: c.primary),
          ),
        ),
        title: Text(name),
        subtitle: Text(
          person['isPrivate'] == true ? 'โปรไฟล์ส่วนตัว' : 'สมาชิก Linko',
        ),
        trailing: IconButton(
          tooltip: 'ดูโปรไฟล์และติดตาม',
          onPressed: () => _openPerson(person),
          icon: const Icon(Icons.person_outline_rounded),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileScreen(
              user: widget.user,
              profileUid: person['uid'] as String? ?? '',
            ),
          ),
        ),
      ),
    );
  }

  Widget _postCard(BuildContext context, Post post) {
    final c = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.mediaPath != null)
            SizedBox(
              height: 190,
              child: PostMedia(
                path: post.mediaPath!,
                type: post.mediaType,
                thumbnailPath: post.thumbnailPath,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: c.primary.withValues(alpha: .16),
                      child: Text(
                        (post.authorName.isEmpty
                                ? '?'
                                : post.authorName.characters.first)
                            .toUpperCase(),
                        style: TextStyle(color: c.primary),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      post.editedAt == null
                          ? _date(post.createdAt)
                          : '${_date(post.createdAt)} · แก้ไขแล้ว',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (post.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text(
                      post.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 5,
                      children: post.tags
                          .map(
                            (t) => ActionChip(
                              label: Text('#$t'),
                              onPressed: () => _setTag(t),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
