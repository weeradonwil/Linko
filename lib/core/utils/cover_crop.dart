import 'dart:typed_data';
import 'dart:ui' as ui;

/// ครอปเป็น 3:1 ตามตำแหน่ง preview และคืนทรัพยากรภาพทุกครั้ง แม้ไฟล์เสีย
Future<Uint8List> cropProfileCover(
  Uint8List bytes, {
  double x = 0,
  double y = 0,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  ui.Image? output;
  ui.Picture? picture;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 2400,
      allowUpscaling: false,
    );
    image = (await codec.getNextFrame()).image;
    final width = image.width / image.height > 3
        ? image.height * 3.0
        : image.width.toDouble();
    final height = width / 3;
    final left = (image.width - width) * ((x.clamp(-1, 1) + 1) / 2);
    final top = (image.height - height) * ((y.clamp(-1, 1) + 1) / 2);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(left, top, width, height),
      const ui.Rect.fromLTWH(0, 0, 1200, 400),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    output = await picture.toImage(1200, 400);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const FormatException('อ่านภาพไม่สำเร็จ');
    return data.buffer.asUint8List();
  } finally {
    output?.dispose();
    picture?.dispose();
    image?.dispose();
    codec?.dispose();
  }
}
