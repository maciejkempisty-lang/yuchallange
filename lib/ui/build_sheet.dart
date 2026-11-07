import 'package:flutter/material.dart';

import '../model.dart';
import '../palette.dart';
import '../game/paper_art.dart';

IconData buildingIcon(BuildingType t) => switch (t) {
  BuildingType.garden => Icons.local_florist_outlined,
  BuildingType.library => Icons.local_library_outlined,
  BuildingType.workshop => Icons.handyman_outlined,
  BuildingType.bridge => Icons.alt_route,
};

PaperAsset buildingIllustration(BuildingType type) => switch (type) {
  BuildingType.garden => PaperAsset.garden,
  BuildingType.library => PaperAsset.library,
  BuildingType.workshop => PaperAsset.workshop,
  BuildingType.bridge => PaperAsset.bridge,
};

/// Lets the player pick what to build; returns the chosen type.
Future<BuildingType?> showBuildSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<BuildingType>(
    context: context,
    backgroundColor: Pal.sheet,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      namesRoute: true,
                      child: const Text(
                        'Co budujemy?',
                        style: TextStyle(
                          color: Pal.text,
                          fontFamily: 'Fraunces',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.auto_awesome, color: Pal.spark, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${state.balance}',
                    style: const TextStyle(color: Pal.text, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final t in BuildingType.values)
                _BuildTile(type: t, state: state),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BuildTile extends StatelessWidget {
  const _BuildTile({required this.type, required this.state});

  final BuildingType type;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final built = state.built.contains(type);
    final affordable = state.canBuild(type);
    final Widget trailing;
    if (built) {
      trailing = const Text('Stoi ✓', style: TextStyle(color: Pal.accent));
    } else {
      trailing = FilledButton.icon(
        onPressed: affordable ? () => Navigator.pop(context, type) : null,
        style: FilledButton.styleFrom(
          backgroundColor: Pal.accent,
          foregroundColor: Pal.onAccent,
          disabledBackgroundColor: Pal.card,
          disabledForegroundColor: Pal.textDim,
        ),
        icon: const Icon(Icons.auto_awesome, size: 16),
        label: Text('${type.cost}'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Image.asset(
            buildingIllustration(type).path,
            width: 58,
            height: 58,
            cacheWidth: 174,
            excludeFromSemantics: true,
            fit: BoxFit.contain,
            // Keep the menu usable if an illustration cannot be decoded.
            errorBuilder: (context, error, stack) => Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(buildingIcon(type), color: Pal.accent),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.label,
                  style: const TextStyle(
                    color: Pal.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  !built && !affordable
                      ? 'Brakuje ${type.cost - state.balance} iskier'
                      : type.description,
                  style: const TextStyle(color: Pal.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
