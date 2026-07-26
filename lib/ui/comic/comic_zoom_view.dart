import 'package:flutter/material.dart';

/// Full-screen pinch/double-tap/pan zoom viewer for a single comic page.
///
/// Kept as a separate route on purpose: doing zoom inline inside the scrolling
/// reader fights the scroll gesture. Here the image owns the whole screen, so
/// pinch + drag + double-tap never collide with page navigation.
class ComicZoomView extends StatefulWidget {
  final String? assetPath;
  final String? networkUrl;
  final Map<String, String>? headers;

  const ComicZoomView({
    super.key,
    this.assetPath,
    this.networkUrl,
    this.headers,
  });

  @override
  State<ComicZoomView> createState() => _ComicZoomViewState();
}

class _ComicZoomViewState extends State<ComicZoomView> {
  final TransformationController _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isZoomed => _ctrl.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    // Double-tap toggles between fit and a 2.5x zoom centred on the view.
    setState(() {
      _ctrl.value = _isZoomed
          ? Matrix4.identity()
          : (Matrix4.identity()..scale(2.5));
    });
  }

  Widget _buildImage() {
    if (widget.assetPath != null) {
      return Image.asset(widget.assetPath!, fit: BoxFit.contain);
    }
    return Image.network(
      widget.networkUrl!,
      headers: widget.headers,
      fit: BoxFit.contain,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      },
      errorBuilder: (_, e, __) => Center(
        child: Text('图片加载失败\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('放大查看'),
      ),
      body: GestureDetector(
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _ctrl,
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: Center(child: _buildImage()),
        ),
      ),
    );
  }
}