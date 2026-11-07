import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../model.dart';
import '../palette.dart';
import 'island_game.dart';
import 'paper_art.dart';

final _rnd = math.Random(7);

/// Organic island outline: an ellipse with a gentle wobble.
Path blobPath(double rx, double ry, {double cx = 0, double cy = 0}) {
  final path = Path();
  const n = 72;
  for (var i = 0; i <= n; i++) {
    final a = i / n * math.pi * 2;
    final r = 1 + 0.045 * math.sin(3 * a + 0.6) + 0.03 * math.cos(5 * a + 1.3);
    final x = cx + math.cos(a) * rx * r;
    final y = cy + math.sin(a) * ry * r;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  return path..close();
}

/// Main path across the island; Yu wanders between points on it.
Offset pathPoint(double t) {
  const p0 = Offset(-140, 62), p1 = Offset(-60, 30);
  const p2 = Offset(60, 44), p3 = Offset(163, 6);
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

Paint _fill(Color c) => Paint()..color = c;

// --- Screen-space layers -----------------------------------------------------

class SeaGradient extends Component with HasGameReference<IslandGame> {
  SeaGradient() : super(priority: -10);

  @override
  void render(Canvas canvas) {
    final rect = Offset.zero & game.size.toSize();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(rect.topCenter, rect.bottomCenter, [
          Pal.sea,
          Pal.seaDeep,
        ]),
    );
  }
}

class WaterShimmer extends Component with HasGameReference<IslandGame> {
  WaterShimmer() : super(priority: -9);

  final _lines = List.generate(
    32,
    (_) => (
      _rnd.nextDouble(),
      _rnd.nextDouble(),
      8 + _rnd.nextDouble() * 16,
      _rnd.nextDouble() * 6.28,
    ),
  );
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final w = game.size.x, h = game.size.y;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (fx, fy, len, ph) in _lines) {
      final x = (fx * (w + 60) + _t * 5) % (w + 60) - 30;
      final y = fy * h + math.sin(_t * 0.8 + ph) * 2;
      final a = 0.05 + 0.07 * (0.5 + 0.5 * math.sin(_t * 1.4 + ph));
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: a);
      canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
    }
  }
}

class Cloud extends Component with HasGameReference<IslandGame> {
  Cloud(int i)
    : _x = _rnd.nextDouble() * 500,
      _yFrac = 0.12 + i * 0.17 + _rnd.nextDouble() * 0.05,
      _speed = 5 + _rnd.nextDouble() * 7,
      _s = 0.8 + _rnd.nextDouble() * 0.7,
      super(priority: 50);

  double _x;
  final double _yFrac, _speed, _s;

  @override
  void update(double dt) {
    _x += _speed * dt;
    if (_x > game.size.x + 120) _x = -140;
  }

  @override
  void render(Canvas canvas) {
    final paint = _fill(const Color(0xFFFFFFFF).withValues(alpha: 0.07));
    final y = _yFrac * game.size.y;
    canvas.save();
    canvas.translate(_x, y);
    canvas.scale(_s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-40, -8, 90, 22),
        const Radius.circular(11),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(-10, -8), 16, paint);
    canvas.drawCircle(const Offset(14, -12), 20, paint);
    canvas.restore();
  }
}

class NightOverlay extends Component with HasGameReference<IslandGame> {
  NightOverlay() : super(priority: 100);

  @override
  void render(Canvas canvas) {
    final n = game.night;
    if (n < 0.01) return;
    final rect = Offset.zero & game.size.toSize();
    final warm = 4 * n * (1 - n) * 0.16;
    final dark = math.pow(n, 1.4) * 0.5;
    canvas.drawRect(rect, _fill(Pal.duskTint.withValues(alpha: warm)));
    canvas.drawRect(
      rect,
      _fill(Pal.nightTint.withValues(alpha: dark.toDouble())),
    );
  }
}

/// Things that glow at night: windows, the lighthouse lamp, fireflies.
mixin Lit on PositionComponent {
  List<Offset> get lightPoints;

  Iterable<Offset> rootLights() sync* {
    for (final p in lightPoints) {
      yield Offset(
        position.x + (p.dx - size.x * anchor.x) * scale.x,
        position.y + (p.dy - size.y * anchor.y) * scale.y,
      );
    }
  }
}

/// Drawn above [NightOverlay] so lights stay bright while the world darkens.
class LightsLayer extends Component with HasGameReference<IslandGame> {
  LightsLayer() : super(priority: 101);

  final _flies = List.generate(
    14,
    (_) => (
      Offset(_rnd.nextDouble() * 280 - 140, _rnd.nextDouble() * 150 - 75),
      _rnd.nextDouble() * 10,
    ),
  );
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final n = game.night;
    if (n < 0.03) return;
    final root = game.root;
    canvas.save();
    canvas.translate(root.position.x, root.position.y);
    canvas.scale(root.scale.x);

    for (final c in root.children.whereType<Lit>()) {
      for (final p in c.rootLights()) {
        const r = 18.0;
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..shader = Gradient.radial(p, r, [
              Pal.window.withValues(alpha: 0.45 * n),
              Pal.window.withValues(alpha: 0),
            ]),
        );
      }
    }

    if (n > 0.4) {
      final fade = (n - 0.4) / 0.6;
      for (final (base, ph) in _flies) {
        final p =
            base +
            Offset(
              math.sin(_t * 0.6 + ph) * 14,
              math.cos(_t * 0.8 + ph * 1.3) * 8,
            );
        final a = fade * (0.5 + 0.5 * math.sin(_t * 3 + ph * 2));
        canvas.drawCircle(p, 5, _fill(Pal.spark.withValues(alpha: 0.18 * a)));
        canvas.drawCircle(p, 1.4, _fill(Pal.spark.withValues(alpha: a)));
      }
    }
    canvas.restore();
  }
}

// --- Island ------------------------------------------------------------------

class Foam extends Component with HasGameReference<IslandGame> {
  Foam() : super(priority: -1001);

  static final _outline = blobPath(165, 105);
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    for (var k = 0; k < 2; k++) {
      final s = 1.04 + k * 0.055 + math.sin(_t * 1.1 + k * 1.7) * 0.012;
      canvas.save();
      canvas.translate(0, 18);
      canvas.scale(s);
      canvas.drawPath(
        _outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 / s
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.2 - k * 0.09),
      );
      canvas.restore();
    }
  }
}

class Ground extends Component with HasGameReference<IslandGame> {
  Ground() : super(priority: -1000);

  @override
  void render(Canvas canvas) => game.art.draw(
    canvas,
    PaperAsset.island,
    const Rect.fromLTWH(-178, -140, 356, 250),
  );
}

class Tree extends PositionComponent with HasGameReference<IslandGame> {
  Tree(Vector2 pos, this.s)
    : _phase = _rnd.nextDouble() * 6.28,
      super(
        position: pos,
        size: Vector2(44, 58),
        anchor: Anchor.bottomCenter,
        priority: pos.y.round(),
      );

  final double s, _phase;
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(size.x / 2, size.y);
    canvas.scale(s);
    canvas.rotate(math.sin(_t * 1.3 + _phase) * 0.025);
    game.art.draw(
      canvas,
      PaperAsset.tree,
      const Rect.fromLTWH(-22, -58, 44, 58),
    );
    canvas.restore();
  }
}

/// The far islet behind fog; the bridge reveals it and its old lighthouse.
class Islet extends PositionComponent with Lit, HasGameReference<IslandGame> {
  Islet()
    : super(
        position: Vector2(240, -12),
        size: Vector2(100, 100),
        anchor: Anchor.bottomCenter,
        priority: -20,
      );

  double fog = 1;
  bool _revealing = false;
  double _t = 0;

  void reveal() => _revealing = true;

  @override
  List<Offset> get lightPoints => fog < 0.5 ? const [Offset(50, 25)] : const [];

  @override
  void update(double dt) {
    _t += dt;
    if (_revealing) fog = math.max(0, fog - dt * 0.45);
  }

  @override
  void render(Canvas canvas) {
    game.art.draw(canvas, PaperAsset.lighthouse, Offset.zero & size.toSize());
    if (fog <= 0) return;
    final mist = Paint()
      ..color = const Color(0xFFE5EDE5).withValues(alpha: 0.82 * fog)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    for (var i = 0; i < 7; i++) {
      final dx = math.sin(_t * 0.5 + i) * 4;
      canvas.drawCircle(
        Offset(8 + i * 14 + dx, 45 + (i.isEven ? 12 : 0)),
        32,
        mist,
      );
    }
  }
}

// --- Buildings ---------------------------------------------------------------

abstract class Building extends PositionComponent
    with Lit, HasGameReference<IslandGame> {
  Building(Vector2 pos, Vector2 size)
    : super(
        position: pos,
        size: size,
        anchor: Anchor.bottomCenter,
        priority: pos.y.round(),
      );

  PaperAsset get illustration;
  List<Rect> get windows => const [];

  @override
  List<Offset> get lightPoints => [for (final w in windows) w.center];

  @override
  void render(Canvas canvas) =>
      game.art.draw(canvas, illustration, Offset.zero & size.toSize());
}

class YuHouse extends Building {
  YuHouse(Vector2 pos) : super(pos, Vector2(72, 76));

  double _smoke = 0;

  @override
  PaperAsset get illustration => PaperAsset.cottage;

  @override
  List<Rect> get windows => const [
    Rect.fromLTWH(11, 45, 10, 10),
    Rect.fromLTWH(51, 42, 10, 10),
  ];

  @override
  void update(double dt) {
    _smoke -= dt;
    if (_smoke <= 0) {
      _smoke = 0.8;
      game.smoke(position + Vector2(-size.x / 2 + 18, -size.y + 6));
    }
  }
}

class Library extends Building {
  Library(Vector2 pos) : super(pos, Vector2(84, 80));

  @override
  PaperAsset get illustration => PaperAsset.library;

  @override
  List<Rect> get windows => const [
    Rect.fromLTWH(13, 46, 13, 15),
    Rect.fromLTWH(57, 46, 13, 15),
  ];
}

class Workshop extends Building {
  Workshop(Vector2 pos) : super(pos, Vector2(84, 66));

  @override
  PaperAsset get illustration => PaperAsset.workshop;

  @override
  List<Rect> get windows => const [Rect.fromLTWH(12, 29, 9, 9)];
}

class Garden extends Building {
  Garden(Vector2 pos) : super(pos, Vector2(78, 50));

  @override
  PaperAsset get illustration => PaperAsset.garden;
}

class Bridge extends Building {
  Bridge(Vector2 pos) : super(pos, Vector2(64, 28));

  @override
  PaperAsset get illustration => PaperAsset.bridge;
}

class Scaffolding extends PositionComponent {
  Scaffolding(Vector2 pos, Vector2 size)
    : super(
        position: pos,
        size: size,
        anchor: Anchor.bottomCenter,
        priority: pos.y.round(),
      );

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    angle = math.sin(_t * 38) * 0.015;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x, h = size.y;
    final pole = Paint()
      ..color = Pal.wood
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final x in [2.0, w / 2, w - 2]) {
      canvas.drawLine(Offset(x, h), Offset(x, 4), pole);
    }
    for (final y in [h * 0.35, h * 0.7]) {
      canvas.drawLine(Offset(0, y), Offset(w, y), pole);
    }
    canvas.drawLine(
      Offset(2, h),
      Offset(w - 2, h * 0.35),
      pole..strokeWidth = 1.2,
    );
    canvas.drawLine(Offset(w - 2, h), Offset(2, h * 0.35), pole);
  }
}

/// A small keepsake left by a finished goal.
class Trace extends PositionComponent {
  Trace(this.category, Vector2 pos)
    : super(
        position: pos,
        size: Vector2(16, 16),
        anchor: Anchor.bottomCenter,
        priority: pos.y.round(),
      );

  final Category category;
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(1, 13, 14, 4), _fill(Pal.shadow));
    switch (category) {
      case Category.ruch:
        canvas.drawCircle(const Offset(8, 10), 5, _fill(Pal.text));
        canvas.drawArc(
          const Rect.fromLTWH(4.5, 1.5, 7, 7),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = Pal.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(const Offset(6.5, 9), 1.2, _fill(Pal.wallLight));
      case Category.nauka:
        const colors = [Pal.roof, Pal.door, Pal.roofBlue];
        for (var i = 0; i < 3; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(2.0 + (i.isOdd ? 1.5 : 0), 11.0 - i * 4, 12, 3.5),
              const Radius.circular(1),
            ),
            _fill(colors[i]),
          );
        }
      case Category.dom:
        final pot = Path()
          ..moveTo(4, 9)
          ..lineTo(12, 9)
          ..lineTo(10.5, 15)
          ..lineTo(5.5, 15)
          ..close();
        canvas.drawPath(pot, _fill(Pal.roof));
        canvas.save();
        canvas.translate(8, 9);
        canvas.rotate(math.sin(_t * 2) * 0.12);
        canvas.drawLine(
          Offset.zero,
          const Offset(0, -6),
          Paint()
            ..color = Pal.leafLight
            ..strokeWidth = 1.4,
        );
        for (var i = 0; i < 5; i++) {
          final a = i / 5 * math.pi * 2;
          canvas.drawCircle(
            Offset(math.cos(a) * 2.2, -7 + math.sin(a) * 2.2),
            1.6,
            _fill(const Color(0xFFF2B8B0)),
          );
        }
        canvas.drawCircle(const Offset(0, -7), 1.2, _fill(Pal.spark));
        canvas.restore();
    }
  }
}

// --- Yu ----------------------------------------------------------------------

class Yu extends PositionComponent
    with HasGameReference<IslandGame>, TapCallbacks {
  Yu()
    : super(
        position: Vector2(0, 40),
        size: Vector2(36, 44),
        anchor: Anchor.bottomCenter,
      );

  static final _waypoints = [
    for (final t in [0.05, 0.22, 0.4, 0.58, 0.75, 0.9])
      Vector2(pathPoint(t).dx, pathPoint(t).dy),
    Vector2(-46, -12),
    Vector2(10, 0),
  ];

  Vector2? _target;
  void Function()? _onArrive;
  double _wait = 1.2, _t = 0, _jump = -1;
  bool _right = true;

  /// While busy (watching a build), Yu does not wander off.
  bool busy = false;

  void goTo(Vector2 p, {void Function()? onArrive}) {
    _target = p.clone();
    _onArrive = onArrive;
  }

  void hop() => _jump = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_jump >= 0) {
      _jump += dt;
      if (_jump > 0.45) _jump = -1;
    }
    final target = _target;
    if (target != null) {
      final d = target - position;
      final dist = d.length;
      final step = 28 * dt;
      if (dist <= step) {
        position.setFrom(target);
        _target = null;
        _wait = 1.5 + game.rnd.nextDouble() * 3;
        final cb = _onArrive;
        _onArrive = null;
        cb?.call();
      } else {
        if (d.x.abs() > 0.5) _right = d.x > 0;
        position.add(d..scale(step / dist));
      }
    } else if (!busy) {
      _wait -= dt;
      if (_wait <= 0) goTo(_waypoints[game.rnd.nextInt(_waypoints.length)]);
    }
    priority = position.y.round();
  }

  @override
  void render(Canvas canvas) {
    final walking = _target != null;
    final bob = walking ? -math.sin(_t * 13).abs() * 2.2 : 0.0;
    final jump = _jump >= 0 ? -math.sin(_jump / 0.45 * math.pi) * 12 : 0.0;
    final breathe = walking ? 1.0 : 1 + math.sin(_t * 2.2) * 0.025;
    final cx = size.x / 2, by = size.y;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, by),
        width: 24 + jump * 0.5,
        height: 4,
      ),
      _fill(Pal.shadow),
    );
    canvas.save();
    canvas.translate(cx, by + bob + jump);
    canvas.scale(1, breathe);

    canvas.scale(_right ? 1 : -1, 1);
    game.art.draw(canvas, PaperAsset.yu, const Rect.fromLTWH(-18, -44, 36, 44));
    canvas.restore();
  }

  @override
  void onTapDown(TapDownEvent event) {
    hop();
    game.hearts(position - Vector2(0, 30));
  }
}
