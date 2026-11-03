import 'dart:typed_data';
import 'dart:ui' as ui;

// Public profile previews use a small copy; the full avatar has separate access rules.
Future<Uint8List> makeAvatarThumbnail(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('สร้างรูปโปรไฟล์ขนาดเล็กไม่สำเร็จ');
      return data.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

String? visibleAvatarPath(Map<String, dynamic>? profile) {
  final thumb = profile?['avatarThumbPath'];
  if (thumb is String && thumb.isNotEmpty) return thumb;
  // Old public profiles still work until their owner updates the avatar.
  if (profile?['isPrivate'] == true ||
      profile?['privacyMigrationTarget'] == true ||
      profile?['privacyTarget'] == true) {
    return null;
  }
  final full = profile?['avatarPath'];
  return full is String && full.isNotEmpty ? full : null;
}
