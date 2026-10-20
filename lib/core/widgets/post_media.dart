// วิดเจ็ตกลางสำหรับโหลดภาพและเตรียมวิดีโอจาก Firebase Storage ในฟีดและแชท
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// แสดงไฟล์ของโพสต์โดยอ่านผ่าน Storage SDK แทน download URL
/// ทุกการอ่านจึงถูกตรวจด้วย Firebase Storage Rules รวมถึงไฟล์ของโพสต์ส่วนตัว
class PostMedia extends StatelessWidget {
  const PostMedia({
    required this.path,
    required this.type,
    this.thumbnailPath,
    super.key,
  });

  final String path;
  final String type;
  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) {
    return type == 'video'
        ? _StorageVideo(path: path, thumbnailPath: thumbnailPath)
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
  // ใช้ไบต์ภาพซ้ำเมื่อวิดเจ็ตสร้างใหม่ และจำกัดหน่วยความจำแคชไว้ที่ 24 MiB
  static const _imageCacheLimit = 24 * 1024 * 1024;
  static final LinkedHashMap<String, Uint8List> _imageCache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _imageLoads = {};

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

  Future<Uint8List?> _loadImage() async {
    final cached = _imageCache.remove(widget.path);
    if (cached != null) {
      _imageCache[widget.path] = cached;
      return cached;
    }

    final path = widget.path;
    final pending = _imageLoads.putIfAbsent(
      path,
      () => FirebaseStorage.instance.ref(path).getData(10 * 1024 * 1024),
    );
    try {
      final bytes = await pending;
      if (bytes != null) {
        _imageCache[path] = bytes;
        var totalBytes = _imageCache.values.fold<int>(
          0,
          (total, image) => total + image.length,
        );
        while (totalBytes > _imageCacheLimit && _imageCache.length > 1) {
          final oldestPath = _imageCache.keys.first;
          totalBytes -= _imageCache.remove(oldestPath)!.length;
        }
      }
      return bytes;
    } finally {
      if (identical(_imageLoads[path], pending)) _imageLoads.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null) {
          return _MediaMessage(
            icon: Icons.broken_image_outlined,
            onPressed: () => setState(() => _imageBytes = _loadImage()),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MediaLoading();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!,
            width: double.infinity,
            cacheWidth: 780,
            cacheHeight: 570,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _StorageVideo extends StatefulWidget {
  const _StorageVideo({required this.path, this.thumbnailPath});

  final String path;
  final String? thumbnailPath;

  @override
  State<_StorageVideo> createState() => _StorageVideoState();
}

class _StorageVideoState extends State<_StorageVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;

  @override
  void didUpdateWidget(covariant _StorageVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _disposeVideo();
      _controller = null;
      _initialization = null;
    }
  }

  /// Resolve Storage's protected object URL and prepare the first video frame.
  Future<void> _prepareVideo() async {
    final path = widget.path;
    final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
    if (!mounted || path != widget.path) return;

    // Streaming displays the preview frame without downloading the entire clip first.
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    await controller.initialize();
    if (!mounted || path != widget.path) return;
    // Keep scrolling previews silent; sound starts when the user plays the clip.
    await controller.setVolume(0);
    controller.addListener(_refreshControls);
  }

  void _refreshControls() {
    if (mounted) setState(() {});
  }

  Future<void> _startPlayback({bool retry = false}) async {
    if (retry || _initialization == null) {
      if (retry) {
        _disposeVideo();
        _controller = null;
      }
      setState(() => _initialization = _prepareVideo());
    }
    try {
      await _initialization;
      if (mounted) {
        await _controller?.setVolume(1);
        await _controller?.play();
      }
    } catch (_) {
      // FutureBuilder shows a retry control when initialization or playback fails.
    }
  }

  void _disposeVideo() {
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
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
          return _videoPoster(failed: true);
        }
        final controller = _controller;
        if (_initialization == null) {
          return _videoPoster();
        }
        if (snapshot.connectionState != ConnectionState.done ||
            controller == null) {
          return _videoPoster(isLoading: true);
        }
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              IconButton.filledTonal(
                onPressed: () async {
                  if (controller.value.isPlaying) {
                    await controller.pause();
                  } else {
                    await controller.setVolume(1);
                    await controller.play();
                  }
                },
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Watch full screen',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => _FullScreenVideo(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows the small cached cover while the video player waits for its first frame.
  Widget _videoPoster({bool isLoading = false, bool failed = false}) {
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            ColoredBox(color: colors.surfaceContainerHighest),
            if (widget.thumbnailPath != null)
              _StorageImage(path: widget.thumbnailPath!),
            const ColoredBox(color: Color(0x26000000)),
            Center(
              child: IconButton.filledTonal(
                tooltip: isLoading
                    ? 'กำลังเตรียมวิดีโอ'
                    : failed
                    ? 'ลองโหลดวิดีโออีกครั้ง'
                    : 'เล่นวิดีโอ',
                onPressed: isLoading
                    ? null
                    : () => _startPlayback(retry: failed),
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        failed
                            ? Icons.refresh_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reuses the loaded player so opening the full-screen view does not fetch the
/// same video again or interrupt playback.
class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  @override
  void initState() {
    super.initState();
    // Hide system bars while expanded, then restore the app's normal layout.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () async {
                if (controller.value.isPlaying) {
                  await controller.pause();
                } else {
                  await controller.setVolume(1);
                  await controller.play();
                }
                if (mounted) setState(() {});
              },
              iconSize: 40,
              icon: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton.filledTonal(
                tooltip: 'Close full screen',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 8,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFFF4D6D),
                  bufferedColor: Colors.white54,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
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
