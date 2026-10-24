// ดาวน์โหลดวิดีโอผ่าน SDK ลงพื้นที่ชั่วคราวของแอป และลบเมื่อปิดตัวเล่น
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'authenticated_video_handle.dart';

Future<AuthenticatedVideo> loadVideo(Reference reference) async {
  final metadata = await reference.getMetadata();
  if ((metadata.size ?? 0) > 50 * 1024 * 1024) {
    throw const FormatException('วิดีโอต้องไม่เกิน 50 MB');
  }
  final temporary = await getTemporaryDirectory();
  final directory = await Directory(temporary.path).createTemp('linko_video_');
  final extension = reference.name
      .split('.')
      .last
      .replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  final file = File(
    '${directory.path}${Platform.pathSeparator}video.$extension',
  );
  // ลบเฉพาะไฟล์และโฟลเดอร์ที่ฟังก์ชันนี้สร้าง จึงไม่กระทบ cache อื่นของแอป
  Future<void> cleanup() async {
    if (await file.exists()) await file.delete();
    if (await directory.exists()) await directory.delete();
  }

  try {
    await reference.writeToFile(file);
    return AuthenticatedVideo(VideoPlayerController.file(file), cleanup);
  } catch (_) {
    await cleanup();
    rethrow;
  }
}
