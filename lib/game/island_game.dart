import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/particles.dart';
import 'package:flutter/animation.dart' show Curves;

import '../model.dart';
import '../palette.dart';
import 'island_components.dart';
import 'paper_art.dart';

/// The settlement scene. Flutter owns the data ([AppState]); this game only
/// draws it and plays one-off effects when Flutter reports an event.
class IslandGame extends FlameGame {
  IslandGame({required this.state});

  final AppState state;
  void Function(BuildingType type)? onBuilt;

  final rnd = math.Random();
  final root = PositionComponent();
  late final Yu yu;
  late final Islet islet;
  late final PaperArt art;

  /// 0 = day, 0.5 = dusk, 1 = night.
  double night = 0;
  double _nightTarget = 0;

  double _top = 120, _bottom = 340;
  double _topTarget = 120, _bottomTarget = 340;
  bool _viewportSet = false;

  double _zoom = 1, _zoomTarget = 1;
  final _focus = Vector2.zero();
  final _focusTarget = Vector2.zero();
  double _focusHold = 0;

  static final houseSlot = Vector2(-40, -22);
  static final slots = {
    BuildingType.garden: Vector2(-92, 30),
    BuildingType.library: Vector2(58, -30),
    BuildingType.workshop: Vector2(74, 64),
    BuildingType.bridge: Vector2(181, 12),
  };
  static const _trees = [
    (-132.0, -14.0, 1.0),
    (-8.0, -70.0, 0.9),
    (118.0, -56.0, 1.1),
    (-62.0, 74.0, 0.85),
    (138.0, 30.0, 0.9),
    (-112.0, -56.0, 0.75),
    (20.0, -67.0, 0.7),
  ];

  @override
  Color backgroundColor() => Pal.sea;

  @override
  Future<void> onLoad() async {
    art = PaperArt.ready ?? await PaperArt.load();
    night = _nightTarget = nightFromClock(DateTime.now());

    addAll([SeaGradient(), WaterShimmer(), root]);
    for (var i = 0; i < 4; i++) {
      add(Cloud(i));
    }
    addAll([NightOverlay(), LightsLayer()]);

    islet = Islet();
    yu = Yu();
    root.addAll([
      Foam(),
      Ground(),
      islet,
      YuHouse(houseSlot),
      for (final (x, y, s) in _trees) Tree(Vector2(x, y), s),
      yu,
    ]);
    for (final type in state.built) {
      root.add(_createBuilding(type));
      if (type == BuildingType.bridge) islet.fog = 0;
    }
    final shown = <Category, int>{};
    for (final c in state.traces) {
      final n = shown[c] = (shown[c] ?? -1) + 1;
      if (n < maxTracesPerSpot) root.add(Trace(c, traceSpot(c, n)));
    }
    _layoutRoot();
  }

  /// Screen insets covered by Flutter UI; the island centers between them.
  void setViewport({required double top, required double bottom}) {
    _topTarget = top;
    _bottomTarget = bottom;
    if (!_viewportSet) {
      _viewportSet = true;
      _top = top;
      _bottom = bottom;
    }
  }

  void setTimeOfDay(double value) => _nightTarget = value;

  void focusOn(Vector2 point, {double hold = 2.4}) {
    _focusTarget.setFrom(point * 0.75);
    _zoomTarget = 1.22;
    _focusHold = hold;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_focusHold > 0) {
      _focusHold -= dt;
      if (_focusHold <= 0) {
        _focusTarget.setZero();
        _zoomTarget = 1;
      }
    }
    final k = 1 - math.exp(-dt * 3.5);
    _zoom += (_zoomTarget - _zoom) * k;
    _focus.add((_focusTarget - _focus)..scale(k));
    _top += (_topTarget - _top) * k * 1.6;
    _bottom += (_bottomTarget - _bottom) * k * 1.6;
    night += (_nightTarget - night) * (1 - math.exp(-dt * 1.6));
    _layoutRoot();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layoutRoot();
  }

  void _layoutRoot() {
    final avail = math.max(160.0, size.y - _top - _bottom);
    final base = math.min(size.x / 440, avail / 290);
    final s = base * _zoom;
    root.scale.setAll(s);
    root.position.setValues(
      size.x / 2 - _focus.x * s,
      _top + avail / 2 - 15 * base - _focus.y * s,
    );
  }

  /// Keepsakes of one kind line up next to each other; older ones beyond
  /// this count stay in the history only.
  static const maxTracesPerSpot = 4;

  /// Where the [n]-th keepsake of category [c] stands.
  Vector2 traceSpot(Category c, [int n = 0]) {
    final (Vector2 base, Vector2 step) = switch (c) {
      Category.ruch when state.built.contains(BuildingType.workshop) => (
        slots[BuildingType.workshop]! + Vector2(40, 2),
        Vector2(-9, 7),
      ),
      Category.ruch => (houseSlot + Vector2(30, 2), Vector2(8, 3)),
      Category.nauka when state.built.contains(BuildingType.library) => (
        slots[BuildingType.library]! + Vector2(30, 2),
        Vector2(8, 3),
      ),
      Category.nauka => (houseSlot + Vector2(-30, 2), Vector2(-8, 3)),
      Category.dom => (houseSlot + Vector2(11, 3), Vector2(3, 7)),
    };
    return base + step * n.toDouble();
  }

  Building _createBuilding(BuildingType type) {
    final pos = slots[type]!;
    return switch (type) {
      BuildingType.garden => Garden(pos),
      BuildingType.library => Library(pos),
      BuildingType.workshop => Workshop(pos),
      BuildingType.bridge => Bridge(pos),
    };
  }

  /// Scaffolding, dust and a springy reveal. The purchase is already saved,
  /// so an interrupted animation never loses the building.
  void build(BuildingType type) {
    // Before onLoad finishes there is no scene yet; onLoad reads the
    // building from state, so nothing is lost.
    if (!isLoaded) return;
    final pos = slots[type]!;
    final building = _createBuilding(type);
    final scaffold = Scaffolding(pos, building.size);
    root.add(scaffold);
    focusOn(pos - Vector2(0, building.size.y / 2), hold: 3.4);

    yu.busy = true;
    yu.goTo(pos + Vector2(-building.size.x / 2 - 12, 4));

    scaffold.add(
      TimerComponent(
        period: 0.26,
        repeat: true,
        onTick: () => dust(
          pos +
              Vector2(
                (rnd.nextDouble() - 0.5) * building.size.x,
                -rnd.nextDouble() * 10,
              ),
        ),
      ),
    );
    root.add(
      TimerComponent(
        period: 1.7,
        removeOnFinish: true,
        onTick: () {
          scaffold.removeFromParent();
          building.scale = Vector2.zero();
          root.add(building);
          building.add(
            ScaleEffect.to(
              Vector2.all(1),
              EffectController(duration: 0.75, curve: Curves.elasticOut),
            ),
          );
          final center = pos - Vector2(0, building.size.y * 0.45);
          sparkle(center, count: 24);
          ring(center);
          yu.busy = false;
          yu.hop();
          if (type == BuildingType.bridge) {
            islet.reveal();
            focusOn(islet.position - Vector2(0, 20), hold: 3.5);
          }
          onBuilt?.call(type);
        },
      ),
    );
  }

  void addTrace(Category category) {
    if (!isLoaded) return;
    final n = state.traces.where((c) => c == category).length - 1;
    if (n >= maxTracesPerSpot) return;
    final spot = traceSpot(category, n);
    final trace = Trace(category, spot)..scale = Vector2.zero();
    root.add(trace);
    trace.add(
      ScaleEffect.to(
        Vector2.all(1),
        EffectController(
          duration: 0.7,
          startDelay: 0.35,
          curve: Curves.elasticOut,
        ),
      ),
    );
    focusOn(spot - Vector2(0, 10), hold: 2.4);
    sparkle(spot - Vector2(0, 8), count: 16);
    ring(spot - Vector2(0, 6));
    if (!yu.busy) yu.goTo(spot + Vector2(-16, 4));
  }

  // --- Particles -----------------------------------------------------------

  void _emit(Vector2 at, Particle particle) => root.add(
    ParticleSystemComponent(position: at, priority: 5000, particle: particle),
  );

  void sparkle(Vector2 at, {int count = 16}) {
    const life = 0.95;
    _emit(
      at,
      Particle.generate(
        count: count,
        lifespan: life,
        generator: (i) {
          final a = rnd.nextDouble() * math.pi * 2;
          final speed = 30 + rnd.nextDouble() * 55;
          final r = 2.5 + rnd.nextDouble() * 2;
          return AcceleratedParticle(
            lifespan: life,
            speed: Vector2(math.cos(a), math.sin(a) - 0.4) * speed,
            acceleration: Vector2(0, 50),
            child: ComputedParticle(
              lifespan: life,
              renderer: (c, p) => drawStar(
                c,
                r * (1 - p.progress) + 0.4,
                Paint()..color = Pal.spark.withValues(alpha: 1 - p.progress),
              ),
            ),
          );
        },
      ),
    );
  }

  void ring(Vector2 at) {
    _emit(
      at,
      ComputedParticle(
        lifespan: 0.8,
        renderer: (c, p) => c.drawCircle(
          Offset.zero,
          4 + 34 * Curves.easeOut.transform(p.progress),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * (1 - p.progress) + 0.3
            ..color = Pal.spark.withValues(alpha: 0.8 * (1 - p.progress)),
        ),
      ),
    );
  }

  void dust(Vector2 at) {
    const life = 0.7;
    _emit(
      at,
      Particle.generate(
        count: 5,
        lifespan: life,
        generator: (i) => AcceleratedParticle(
          lifespan: life,
          speed: Vector2(
            (rnd.nextDouble() - 0.5) * 40,
            -10 - rnd.nextDouble() * 22,
          ),
          acceleration: Vector2(0, 30),
          child: ComputedParticle(
            lifespan: life,
            renderer: (c, p) => c.drawCircle(
              Offset.zero,
              1.5 + 3.5 * p.progress,
              Paint()
                ..color = Pal.path.withValues(alpha: 0.6 * (1 - p.progress)),
            ),
          ),
        ),
      ),
    );
  }

  void smoke(Vector2 at) {
    const life = 2.6;
    _emit(
      at,
      AcceleratedParticle(
        lifespan: life,
        speed: Vector2((rnd.nextDouble() - 0.3) * 5, -11),
        acceleration: Vector2(2.5, -1),
        child: ComputedParticle(
          lifespan: life,
          renderer: (c, p) => c.drawCircle(
            Offset.zero,
            2.2 + 5 * p.progress,
            Paint()
              ..color = const Color(0xFFE6E9E0)
                  .withValues(alpha: 0.32 * (1 - p.progress)),
          ),
        ),
      ),
    );
  }

  void hearts(Vector2 at) {
    const life = 1.1;
    _emit(
      at,
      Particle.generate(
        count: 3,
        lifespan: life,
        generator: (i) => AcceleratedParticle(
          lifespan: life,
          speed: Vector2((i - 1) * 14.0, -34 - rnd.nextDouble() * 10),
          acceleration: Vector2(0, 18),
          child: ComputedParticle(
            lifespan: life,
            renderer: (c, p) => c.drawPath(
              heartPath(4.5 * (1 - p.progress * 0.4)),
              Paint()..color = Pal.roof.withValues(alpha: 1 - p.progress),
            ),
          ),
        ),
      ),
    );
  }
}

double nightFromClock(DateTime now) {
  final h = now.hour + now.minute / 60;
  if (h >= 7.5 && h < 17) return 0;
  if (h >= 17 && h < 21.5) return ((h - 17) / 4.5).clamp(0.0, 1.0);
  if (h >= 5 && h < 7.5) return 1 - (h - 5) / 2.5;
  return 1;
}

void drawStar(Canvas c, double r, Paint paint) {
  final path = Path()
    ..moveTo(0, -r)
    ..quadraticBezierTo(0, 0, r, 0)
    ..quadraticBezierTo(0, 0, 0, r)
    ..quadraticBezierTo(0, 0, -r, 0)
    ..quadraticBezierTo(0, 0, 0, -r)
    ..close();
  c.drawPath(path, paint);
}

Path heartPath(double s) => Path()
  ..moveTo(0, s * 0.45)
  ..cubicTo(-s * 1.1, -s * 0.2, -s * 0.5, -s, 0, -s * 0.45)
  ..cubicTo(s * 0.5, -s, s * 1.1, -s * 0.2, 0, s * 0.45)
  ..close();
