import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/sprite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PaperAsset {
  island,
  cottage,
  library,
  workshop,
  garden,
  bridge,
  lighthouse,
  tree,
  yu;

  String get path => 'assets/images/paper/$name.png';
}

/// Original transparent illustrations stay intact on disk. Smaller textures
/// are decoded once for the scene, so mobile memory usage stays predictable.
class PaperArt {
  PaperArt._(this._sprites);

  static Future<PaperArt>? _cached;
  static PaperArt? _ready;
  static PaperArt? get ready => _ready;
  final Map<PaperAsset, Sprite> _sprites;

  static Future<PaperArt> load() => _cached ??= _load();

  /// A missing or broken file must not keep the scene from loading; that
  /// asset is drawn as a sketch placeholder instead.
  static Future<PaperArt> _load() async {
    final sprites = await Future.wait(PaperAsset.values.map(_decode));
    return _ready = PaperArt._({
      for (final entry in sprites.nonNulls) entry.key: entry.value,
    });
  }

  static Future<MapEntry<PaperAsset, Sprite>?> _decode(PaperAsset asset) async {
    try {
      final data = await rootBundle.load(asset.path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: asset == PaperAsset.island ? 1024 : 384,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return MapEntry(asset, Sprite(frame.image));
    } on Object catch (e) {
      debugPrint('Brak ilustracji ${asset.path}, rysuję zastępnik ($e)');
      return null;
    }
  }

  bool has(PaperAsset asset) => _sprites.containsKey(asset);

  void draw(ui.Canvas canvas, PaperAsset asset, ui.Rect bounds) {
    final sprite = _sprites[asset];
    if (sprite == null) {
      _drawPlaceholder(canvas, asset, bounds);
      return;
    }
    final scale = math.min(
      bounds.width / sprite.src.width,
      bounds.height / sprite.src.height,
    );
    final width = sprite.src.width * scale;
    final height = sprite.src.height * scale;
    sprite.renderRect(
      canvas,
      ui.Rect.fromLTWH(
        bounds.center.dx - width / 2,
        bounds.bottom - height,
        width,
        height,
      ),
      overridePaint: ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  /// A pencil-like outline in the asset's footprint, so a bought building
  /// stays visible until its illustration exists.
  static void _drawPlaceholder(ui.Canvas canvas, PaperAsset asset, ui.Rect b) {
    final fill = ui.Paint()..color = const ui.Color(0xFFF3EBDA);
    final line = ui.Paint()
      ..color = const ui.Color(0xFF8A7B62)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = ui.StrokeJoin.round;
    final ui.Path shape;
    switch (asset) {
      case PaperAsset.tree:
      case PaperAsset.yu:
        shape = ui.Path()..addOval(b.deflate(b.shortestSide * 0.12));
      case PaperAsset.island:
      case PaperAsset.garden:
      case PaperAsset.bridge:
        shape = ui.Path()
          ..addRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTRB(
                b.left,
                b.top + b.height * 0.35,
                b.right,
                b.bottom,
              ),
              ui.Radius.circular(b.height * 0.2),
            ),
          );
      case PaperAsset.cottage:
      case PaperAsset.library:
      case PaperAsset.workshop:
      case PaperAsset.lighthouse:
        final roofY = b.top + b.height * 0.4;
        shape = ui.Path()
          ..moveTo(b.left + b.width * 0.1, b.bottom)
          ..lineTo(b.left + b.width * 0.1, roofY)
          ..lineTo(b.center.dx, b.top + b.height * 0.05)
          ..lineTo(b.right - b.width * 0.1, roofY)
          ..lineTo(b.right - b.width * 0.1, b.bottom)
          ..close();
    }
    canvas.drawPath(shape, fill);
    canvas.drawPath(shape, line);
  }
}
