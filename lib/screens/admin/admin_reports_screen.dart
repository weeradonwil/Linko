// หน้าผู้ดูแลสำหรับตรวจรายงานโพสต์ ปิดรายงาน หรือนำโพสต์ที่ละเมิดออก
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/post_service.dart';
import '../../core/services/report_service.dart';
import '../../core/services/group_service.dart';
import '../../core/utils/document_values.dart';

/// เปิดคิวรายงานให้บัญชีที่มี Firebase custom claim admin=true
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({required this.user, super.key});

  final User user;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  late final _reports = ReportService();
  late final _posts = PostService();
  late Future<bool> _hasAdminClaim;

  @override
  void initState() {
    super.initState();
    _hasAdminClaim = _readAdminClaim();
  }

  // รีเฟรช token เพื่ออ่านสิทธิ์ล่าสุด; Firestore Rules ยังเป็นผู้บังคับสิทธิ์การอ่าน/เขียนจริง
  Future<bool> _readAdminClaim() async {
    final token = await widget.user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  /// จับ error ระหว่างรอเฟรมใหม่ โดย FutureBuilder ยังแสดงผลล้มเหลวตามจริง
  void _retryAdminClaim() {
    final request = _readAdminClaim();
    request.ignore();
    setState(() {
      _hasAdminClaim = request;
    });
  }

  Future<void> _closeReport(String reportId, String status) async {
    try {
      await _reports.closeReport(reportId: reportId, status: status);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปเดตรายงานไม่สำเร็จ: $error')));
    }
  }

  // ขอคำยืนยันก่อนลบ และปิดรายงานเป็น removed หลังลบโพสต์สำเร็จเท่านั้น
  Future<void> _removePost(
    String reportId,
    String postId,
    String? groupId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('นำโพสต์ออกหรือไม่'),
        content: const Text(
          'โพสต์ ไฟล์แนบ ความคิดเห็น และปฏิกิริยาจะถูกลบอย่างถาวร',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('นำออก'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (groupId == null) {
        await _posts.removeReportedPost(postId);
      } else {
        await GroupService().deletePost(groupId: groupId, postId: postId);
      }
      await _reports.closeReport(reportId: reportId, status: 'removed');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('นำโพสต์ออกไม่สำเร็จ: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('จัดการรายงานโพสต์')),
    body: FutureBuilder<bool>(
      future: _hasAdminClaim,
      builder: (context, claim) {
        // แสดงข้อผิดพลาดและลองใหม่ได้เมื่ออ่าน token ล้มเหลว แทนการค้างที่ตัวโหลด
        if (claim.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ตรวจสิทธิ์ผู้ดูแลไม่สำเร็จ กรุณาลองอีกครั้ง'),
                TextButton(
                  onPressed: _retryAdminClaim,
                  child: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
          );
        }
        if (!claim.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (claim.data != true) {
          return const Center(child: Text('บัญชีนี้ไม่มีสิทธิ์ผู้ดูแลระบบ'));
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reports.watchOpenReports(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('โหลดรายงานไม่สำเร็จ'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final reports = snapshot.data!.docs;
            if (reports.isEmpty) {
              return const Center(child: Text('ไม่มีรายงานค้างตรวจ'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final report = reports[index];
                final data = report.data();
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                final dateLabel = createdAt == null
                    ? ''
                    : '${createdAt.toLocal()}';
                final postId = data['postId'] as String? ?? '';
                final groupId = readOptionalString(data['groupId']);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['reason'] as String? ?? 'ไม่ระบุเหตุผล',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if ((data['details'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(data['details'] as String),
                        ],
                        const SizedBox(height: 8),
                        SelectableText(
                          '${groupId == null ? 'Post' : 'Group $groupId'}: $postId\n'
                          'ผู้รายงาน: ${data['reporterUid']}\n'
                          'เจ้าของ: ${data['postOwnerId']}\n'
                          '$dateLabel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _closeReport(report.id, 'dismissed'),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('ไม่พบการละเมิด'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _closeReport(report.id, 'resolved'),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('ทำเครื่องหมายตรวจแล้ว'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: postId.isEmpty
                                  ? null
                                  : () =>
                                        _removePost(report.id, postId, groupId),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('นำโพสต์ออก'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}
