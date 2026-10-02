import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Builds a DiceBear Notionists avatar URL from a seed string.
String dicebearUrl(String seed) {
  final encoded = Uri.encodeComponent(seed);
  return 'https://api.dicebear.com/7.x/notionists/svg?seed=$encoded';
}

/// Downloads and caches the avatar SVG for a given seed.
/// Returns the local file path, or null on failure.
Future<String?> cacheAvatarSvg(String seed) async {
  try {
    final url = dicebearUrl(seed);
    final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 10),
        );
    if (response.statusCode == 200) {
      final file = await _cacheFile(seed);
      await file.writeAsString(response.body);
      return file.path;
    }
  } catch (_) {}
  return null;
}

Future<File> _cacheFile(String seed) async {
  final dir = await getApplicationSupportDirectory();
  final hash = md5.convert(utf8.encode(seed)).toString();
  return File('${dir.path}/avatar_$hash.svg');
}

/// Returns the cached avatar SVG for [seed], downloading it first if needed.
/// Returns null when it is neither cached nor downloadable.
Future<File?> _resolveAvatarFile(String seed) async {
  try {
    final file = await _cacheFile(seed);
    if (await file.exists()) return file;
  } catch (_) {}
  final path = await cacheAvatarSvg(seed);
  return path == null ? null : File(path);
}

/// Displays a DiceBear Notionists avatar as a circle.
///
/// [seed] is used to generate the avatar. If null, shows a placeholder icon.
/// Loads from local cache first, then downloads into the cache. Only a
/// successful response is rendered, so an error page or an offline device shows
/// the placeholder instead of failing to parse as SVG.
class DiceBearAvatar extends StatefulWidget {
  const DiceBearAvatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.backgroundColor,
  });

  final String? seed;
  final double size;
  final Color? backgroundColor;

  @override
  State<DiceBearAvatar> createState() => _DiceBearAvatarState();
}

class _DiceBearAvatarState extends State<DiceBearAvatar> {
  Future<File?>? _file;

  double get size => widget.size;
  Color? get backgroundColor => widget.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(DiceBearAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) _loadFile();
  }

  void _loadFile() {
    final seed = widget.seed;
    _file = seed == null || seed.isEmpty ? null : _resolveAvatarFile(seed);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) {
      return _placeholder();
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundColor ?? const Color(0xFFE7E8D1),
        child: FutureBuilder<File?>(
          future: file,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _loadingIndicator();
            }
            final data = snapshot.data;
            if (data == null) return _placeholder();
            return SvgPicture.file(
              data,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFE7E8D1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: const Color(0xFF6E7541),
      ),
    );
  }

  Widget _loadingIndicator() {
    return Container(
      width: size,
      height: size,
      color: backgroundColor ?? const Color(0xFFE7E8D1),
      child: Center(
        child: SizedBox(
          width: size * 0.3,
          height: size * 0.3,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF6E7541),
          ),
        ),
      ),
    );
  }
}
