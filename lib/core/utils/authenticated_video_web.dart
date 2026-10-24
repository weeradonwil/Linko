// อ่านวิดีโอด้วยสิทธิ์ Firebase แล้วสร้าง Blob URL ที่ใช้ได้เฉพาะในเบราว์เซอร์นี้
import 'dart:js_interop';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'authenticated_video_handle.dart';

Future<AuthenticatedVideo> loadVideo(Reference reference) async {
  final bytes = await reference.getData(50 * 1024 * 1024);
  if (bytes == null) throw StateError('ไม่พบข้อมูลวิดีโอ');
  final mime = reference.name.toLowerCase().endsWith('.webm')
      ? 'video/webm'
      : 'video/mp4';
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  return AuthenticatedVideo(
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async {
      web.URL.revokeObjectURL(url);
    },
  );
}
