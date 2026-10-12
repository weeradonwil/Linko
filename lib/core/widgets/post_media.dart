import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// แสดงไฟล์ของโพสต์โดยอ่านผ่าน Storage SDK แทน download URL
/// ทุกการอ่านจึงถูกตรวจด้วย Firebase Storage Rules รวมถึงไฟล์ของโพสต์ส่วนตัว
class PostMedia extends StatelessWidget {
  const PostMedia({required this.path, required this.type, super.key});

  final String path;
  final String type;

  @override
  Widget build(BuildContext context) {
    return type == 'video'
        ? _StorageVideo(path: path)
        : _StorageImage(path: path);
  }
}

class _StorageImage extends StatefulWidget {
  const _StorageImage({required this.path});

  final String path;

  @override
  State<_StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<_StorageImage> {
  late Future<Uint8List?> _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _loadImage();
  }

  @override
  void didUpdateWidget(covariant _StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _imageBytes = _loadImage();
  }

  Future<Uint8List?> _loadImage() =>
      FirebaseStorage.instance.ref(widget.path).getData(10 * 1024 * 1024);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null) {
          return const _MediaMessage(icon: Icons.broken_image_outlined);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MediaLoading();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _StorageVideo extends StatefulWidget {
  const _StorageVideo({required this.path});

  final String path;

  @override
  State<_StorageVideo> createState() => _StorageVideoState();
}

class _StorageVideoState extends State<_StorageVideo> {
  VideoPlayerController? _controller;
  File? _temporaryFile;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _StorageVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _disposeVideo();
      _controller = null;
      _temporaryFile = null;
      _initialization = null;
    }
  }

  /// ดาวน์โหลดผ่าน Storage Rules แล้วเขียนไฟล์ชั่วคราวให้ video_player เล่นได้
  Future<void> _prepareVideo() async {
    final path = widget.path;
    final bytes = await FirebaseStorage.instance
        .ref(path)
        .getData(50 * 1024 * 1024);
    if (bytes == null) throw StateError('ไม่พบไฟล์วิดีโอ');
    if (!mounted || path != widget.path) return;

    final directory = await getTemporaryDirectory();
    final safeFileName = path
        .split('/')
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File(
      '${directory.path}/social_${DateTime.now().microsecondsSinceEpoch}_$safeFileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted || path != widget.path) {
      await file.delete();
      return;
    }

    _temporaryFile = file;
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    await controller.initialize();
    controller.addListener(_refreshControls);
  }

  void _refreshControls() {
    if (mounted) setState(() {});
  }

  /// ยังไม่ดาวน์โหลดวิดีโอขณะเลื่อนฟีด; เริ่มโหลดเมื่อผู้ใช้กดเล่นเท่านั้น
  Future<void> _startPlayback({bool retry = false}) async {
    if (retry || _initialization == null) {
      if (retry) {
        _disposeVideo();
        _controller = null;
        _temporaryFile = null;
      }
      setState(() => _initialization = _prepareVideo());
    }
    try {
      await _initialization;
      if (mounted) await _controller?.play();
    } catch (_) {
      // FutureBuilder จะแสดงปุ่มลองใหม่เมื่อไฟล์หรือการเชื่อมต่อมีปัญหา
    }
  }

  void _disposeVideo() {
    final controller = _controller;
    final file = _temporaryFile;
    if (controller != null) {
      unawaited(
        controller.dispose().whenComplete(() {
          if (file != null) unawaited(file.delete().catchError((_) => file));
        }),
      );
    } else if (file != null) {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MediaMessage(
            icon: Icons.videocam_off_outlined,
            onPressed: () => _startPlayback(retry: true),
          );
        }
        final controller = _controller;
        if (_initialization == null) {
          return _MediaMessage(
            icon: Icons.play_circle_outline,
            onPressed: _startPlayback,
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            controller == null) {
          return const _MediaLoading();
        }
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              IconButton.filledTonal(
                onPressed: () => controller.value.isPlaying
                    ? controller.pause()
                    : controller.play(),
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 200,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _MediaMessage extends StatelessWidget {
  const _MediaMessage({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 36),
      ),
    ),
  );
}
