import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One choice in a [SegmentedControl].
class Segment<T> {
  const Segment({required this.value, required this.icon, required this.label});

  final T value;
  final IconData icon;

  /// The control is icon-only, so this is what assistive technology reads.
  final String label;
}

/// Icon-only segmented control over a fixed set of values.
///
/// Selection is [FieldVm.value]; a tap reports through [FieldVm.onChanged].
/// `enabled: false` dims the icons and drops the handler.
///
/// Every value must have a segment. A [FieldVm.value] outside [segments] leaves
/// none of them selected, which reads as a broken control rather than as a
/// third state.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    required this.vm,
    required this.segments,
    super.key,
  });

  final FieldVm<T> vm;
  final List<Segment<T>> segments;

  static const double _inset = 2;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const .all(_inset),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: Radii.control,
        border: .all(color: context.colors.borderStrong),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          for (final (index, segment) in segments.indexed) ...[
            if (index > 0) const SizedBox(width: _gap),
            _Segment(vm: vm, segment: segment),
          ],
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({required this.vm, required this.segment});

  final FieldVm<T> vm;
  final Segment<T> segment;

  static const double _width = 32;
  static const double _height = 26;
  static const double _iconSize = 14;

  /// Matches Material's disabled treatment.
  static const _disabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = vm.value == segment.value;

    var ink = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    if (!vm.enabled) {
      ink = ink.withValues(alpha: _disabledOpacity);
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: vm.enabled,
      label: segment.label,
      child: GestureDetector(
        onTap: vm.enabled ? () => vm.onChanged(segment.value) : null,
        // A plain box, not `Ink`: `Ink` paints into the nearest Material, which
        // sits below the track's opaque background, so the fill never showed.
        child: Container(
          width: _width,
          height: _height,
          alignment: .center,
          decoration: BoxDecoration(
            color: selected ? scheme.surfaceContainerHighest : null,
            borderRadius: Radii.segment,
          ),
          child: Icon(segment.icon, size: _iconSize, color: ink),
        ),
      ),
    );
  }
}
