// เก็บตัวเล่นกับงานคืนทรัพยากร เพื่อไม่ให้ไฟล์ชั่วคราวหรือ Blob ค้างเมื่อเปลี่ยนหน้า
import 'package:video_player/video_player.dart';

/// เจ้าของตัวเล่นหนึ่งตัว เรียก dispose ซ้ำได้โดยไม่ลบทรัพยากรของตัวเล่นอื่น
class AuthenticatedVideo {
  AuthenticatedVideo(this.controller, this._cleanup);
  final VideoPlayerController controller;
  final Future<void> Function() _cleanup;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await controller.dispose();
    } finally {
      await _cleanup();
    }
  }
}
