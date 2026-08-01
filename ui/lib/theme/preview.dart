import 'package:flutter/widget_previews.dart';

import 'common.dart';

/// The app's themes, handed to the widget previewer.
///
/// `theme:` on `@Preview` takes a `PreviewThemeData Function()`, not a value —
/// an annotation is a constant expression, so it must be a reference to a
/// public top-level function.
///
/// Both brightnesses are supplied so the previewer's light/dark toggle works.
PreviewThemeData appPreviewTheme() =>
    PreviewThemeData(materialLight: lightTheme(), materialDark: darkTheme());

/// `@Preview` with this app's themes already wired in.
///
/// Widgets here read theme-varying tokens through `context.colors`,
/// which are `ThemeExtension`s — under a bare `ThemeData` they resolve to null
/// and take the widget down with them. Carrying the theme on the annotation
/// means a preview cannot be written without it, rather than each author
/// remembering to pass `theme: appPreviewTheme`.
///
/// Use it exactly like `@Preview`, minus `theme`:
///
/// ```dart
/// @AppPreview(name: 'Primary', group: 'Button')
/// Widget previewPrimary() =>
///     Button.primary(label: 'Ok', onPressed: () {});
/// ```
///
/// Previews live in `lib/previews/`, mirroring the package: the previews for
/// `lib/buttons/button.dart` sit in `lib/previews/buttons/button.dart`. Nothing
/// imports that tree, so it stays out of the app's compile graph — a broken
/// fixture fails `dart analyze` but not `flutter build`. Keeping them out of
/// the widget file also keeps production code from importing
/// `package:flutter/widget_previews.dart`.
///
/// The tree must stay under `lib/`: the previewer imports each file by its
/// `package:` URI, and a file outside `lib/` has none — it crashes the tool
/// rather than being skipped.
final class AppPreview extends Preview {
  const AppPreview({
    super.name,
    super.group,
    super.size,
    super.textScaleFactor,
    super.wrapper,
    super.brightness,
    super.localizations,
  }) : super(theme: appPreviewTheme);
}
