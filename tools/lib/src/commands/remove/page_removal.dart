import 'package:path/path.dart' as p;

import '../../engine/build_step.dart';
import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../model/page_artifact.dart';
import '../../routing/routes_source.dart';
import '../../util/casing.dart';
import '../../util/console.dart';
import '../wiring.dart';
import '../writing_command.dart';

/// `remove --kind page`: the page, its connector, and the route that reached
/// them — the inverse of `add-page`.
///
/// A page is *wired*: it is found by what the project declares (an `AppRouter`
/// route) and removing one is mostly an unwiring job.
mixin PageRemoval on WritingCommand {
  WritePlan removePage(
    Casing name,
    RoutesSource routes, {
    required bool apply,
  }) {
    final a = PageArtifact(name);
    final files = [
      a.pageFile(routes.pagesDir),
      a.connectorFile(routes.connectorsDir),
    ];

    final unwire = routes.unwirePage(
      routeType: a.routeType,
      connectorImport: a.connectorImport,
    );
    final wiring = [
      Wiring.of(
        'Router',
        routes.file,
        unwire,
        skipped: 'route ${a.routeType} not registered — nothing to unwire.',
        way: WiringWay.unwired,
      ),
    ];

    return WritePlan(
      changes: Changeset([
        for (final f in files)
          if (f.existsSync()) DeleteFile(f.path),
        ...wiring.edits,
      ]),
      header: 'Remove page "${name.pascal}"  (route: ${a.routeType})',
      narrate: () {
        for (final f in files) {
          if (!f.existsSync()) {
            console.out.writeln('  • ${p.relative(f.path)} — not found');
          }
        }
        console.out.writeln();
        wiring.narrate();
        for (final w in unwire.warnings) {
          console.err.writeln('⚠ $w');
        }
      },
      previewOnly: !apply,
      previewNotice: kPreviewNotice,
      closing: '✓ Removed page "${name.pascal}".',
      // The deleted page lives in `ui`, but build_runner runs in `app`.
      build: (_) => BuildStep.cleanBuild(
        routes.appPackageRoot.path,
        nextHint: 'regenerate the router (drop the ${a.routeType} class)',
      ),
    );
  }
}
