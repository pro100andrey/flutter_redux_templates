import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One choice in a [SegmentedControl].
class Segment<T> {
  const Segment({required this.value, required this.label, this.icon});

  final T value;

  /// Drawn when there is one; otherwise [label] is drawn as text.
  ///
  /// Optional because not every fixed set has icons. Light and dark do — a sun
  /// and a moon read instantly. Languages do not: the honest control for `en`
  /// versus `uk` shows those two words, and a flag would be wrong anyway
  /// (a flag is a country, not a language).
  final IconData? icon;

  /// What assistive technology reads — and what is drawn when [icon] is null.
  final String label;
}

/// Segmented control over a fixed set of values, drawn as icons or as text.
///
/// Which one is per [Segment]: it draws [Segment.icon] where there is one and
/// [Segment.label] where there is not, so a theme switcher gets a sun and a
/// moon and a language switcher gets "English" and "Українська".
///
/// Selection is [FieldVm.value]; a tap reports through [FieldVm.onChanged].
/// `enabled: false` dims the segments and drops the handler.
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
      // Scrollable rather than overflowing: the track is laid out inside a
      // width-capped container, and three text segments at a large text scale
      // do not fit it. `shrinkWrap` semantics come from `mainAxisSize: .min`,
      // so a control that does fit still hugs its content.
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        child: Row(
          mainAxisSize: .min,
          children: [
            for (final (index, segment) in segments.indexed) ...[
              if (index > 0) const SizedBox(width: _gap),
              _Segment(vm: vm, segment: segment),
            ],
          ],
        ),
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

  /// A text segment sets its own width from the label rather than taking
  /// [_width], which is sized for a 14px glyph and would clip two characters.
  static const _textPadding = EdgeInsets.symmetric(horizontal: 8);

  /// The tallest a segment grows before the row starts scrolling instead.
  ///
  /// An icon segment is a fixed [_height] box, and a text one used to be too —
  /// which caps the label at whatever fits 26 logical pixels. At an
  /// accessibility text scale `labelMedium` is taller than that, so the label
  /// overflowed its own box vertically while the row overflowed horizontally.
  static const double _maxHeight = 44;

  /// Matches Material's disabled treatment.
  static const _disabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = vm.value == segment.value;
    final icon = segment.icon;

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
          width: icon == null ? null : _width,
          height: icon == null ? null : _height,
          constraints: icon == null
              ? const BoxConstraints(
                  minHeight: _height,
                  maxHeight: _maxHeight,
                )
              : null,
          padding: icon == null ? _textPadding : null,
          alignment: .center,
          decoration: BoxDecoration(
            color: selected ? scheme.surfaceContainerHighest : null,
            borderRadius: Radii.segment,
          ),
          child: icon == null
              ? Text(
                  segment.label,
                  // One line, ellipsised. The control sits in a `Row` inside a
                  // width-capped container, so a long endonym or a large text
                  // scale is a RenderFlex overflow rather than a wrap.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: ink),
                )
              : Icon(icon, size: _iconSize, color: ink),
        ),
      ),
    );
  }
}
