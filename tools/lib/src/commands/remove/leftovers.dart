import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as p;

import '../../ast/field_rename.dart';
import '../../ast/import_supply.dart' show declaredNamesIn;
import '../../ast/source_index.dart';
import '../../engine/changeset.dart';
import '../../model/page_artifact.dart';
import '../../model/substate_artifact.dart';
import '../../redux/app_state_source.dart';
import '../../util/casing.dart';
import '../../workspace/frx_workspace.dart';
import '../../workspace/workspace_uri.dart';
import '../writing_command.dart';
import 'left_in_place.dart';

/// A file a removal leaves naming what it took away, and what it names.
typedef Leftover = ({String path, List<String> names});

/// What removing [changes]' files leaves behind: every other source file that
/// still imports one of them, or still names a class one of them declared.
///
/// **One question, asked the same way for every kind.** Each removal answered
/// "what still points at this" for itself or not at all: a field named the
/// reducers still assigning it, a selector the connectors still reading it,
/// and a substate, a page, a model, an action or a service said nothing — its
/// closing line sent you to `frx doctor`, which did not check. So
/// `remove theme --kind substate` left the persistor, a connector and the
/// tests importing a deleted state file; `remove task --kind model` a facade
/// field of that type; `remove forgot_password_action` the connector
/// dispatching it; `remove tasks --kind page` the `onTapTasks` hop `add-nav`
/// wrote into the home connector, pushing a route that no longer exists; and
/// the removal of a tab, the shell's `routes: [FeedRoute(), …]`. None of those
/// files is frx's to rewrite — they are somebody's code — but every one of
/// them is named here, at the moment of the decision.
///
/// What a deleted file declared is read off the file; a page connector also
/// takes its generated route type with it (`@RoutePage() FeedPageConnector` →
/// `FeedRoute`), since that is what the rest of the app names. A slot taken
/// off `AppState` is looked for the way `rename` finds it ([FieldRename]):
/// `app.dart` reads `theme.mode` through the facade and imports nothing of the
/// substate.
/// The files the removal itself edits are judged on what they will say
/// afterwards.
List<Leftover> leftoversOf(FrxWorkspace repo, Changeset changes) {
  final deleted = <String>{};
  final edited = <String, String>{};
  for (final change in changes.changes) {
    switch (change) {
      case DeleteFile(:final path):
        deleted.add(p.normalize(p.absolute(path)));
      case DeleteDirectory(:final path) when Directory(path).existsSync():
        for (final f in Directory(path).listSync(recursive: true)) {
          if (f is File) {
            deleted.add(p.normalize(p.absolute(f.path)));
          }
        }
      case EditFile(:final path, :final after):
        edited[p.normalize(p.absolute(path))] = after;
      default:
        break;
    }
  }

  if (deleted.isEmpty) {
    return const [];
  }

  final gone = <String>{};
  for (final path in deleted) {
    if (!path.endsWith('.dart') || FrxWorkspace.isGenerated(path)) {
      continue;
    }
    final unit = sourceIndex.unitFor(File(path));
    gone.addAll(declaredNamesIn(unit));
    for (final c in unit.declarations.whereType<ClassDeclaration>()) {
      if (PageArtifact.isRoutePage(c)) {
        gone.add(_routeOf(c.namePart.typeName.lexeme));
      }
    }
  }
  final slots = _removedSlots(repo, edited);
  final packages = repo.packageLibs();
  final found = <Leftover>[];
  for (final package in FrxWorkspace.sourcePackages) {
    for (final tree in const ['lib', 'test']) {
      final dir = Directory(p.join(repo.root.path, package, tree));
      if (!dir.existsSync()) {
        continue;
      }
      for (final file in sourceIndex.filesUnder(dir)) {
        final path = p.normalize(file.absolute.path);
        if (deleted.contains(path) || FrxWorkspace.isGenerated(path)) {
          continue;
        }
        final source = edited[path] ?? sourceIndex.sourceOf(file);
        final names = <String>{
          for (final (:uri, offset: _) in directivesIn(source))
            if (workspaceTarget(uri, from: path, packages: packages)
                case final target? when deleted.contains(target))
              p.basename(target),
          // Parsed only when the text says a name at all — most files do not.
          if (gone.any(source.contains)) ..._namesIn(source, gone),
          for (final slot in slots)
            if (source.contains(slot.from) &&
                slot
                    .of(
                      parseString(
                        content: source,
                        throwIfDiagnostics: false,
                      ).unit,
                    )
                    .isNotEmpty)
              '.${slot.from}',
        };
        if (names.isNotEmpty) {
          found.add((path: path, names: names.toList()));
        }
      }
    }
  }
  return found..sort((a, b) => a.path.compareTo(b.path));
}

/// [plan], narrating what it leaves in place after its own narration.
///
/// Wrapped rather than asked of each kind, so a kind added later is covered
/// without remembering to be.
WritePlan withLeftovers(WritePlan plan, FrxWorkspace repo) {
  final leftovers = leftoversOf(repo, plan.changes);
  if (leftovers.isEmpty) {
    return plan;
  }
  return plan.withNarration(() {
    plan.narrate?.call();
    narrateLeftovers(leftovers);
  });
}

/// The `AppState` fields [edited] takes away, each as the [FieldRename] that
/// finds where the rest of the app reads it.
///
/// Judged on the text the removal will leave: a field whose `<Type> <field>`
/// parameter is no longer in it has gone.
List<FieldRename> _removedSlots(
  FrxWorkspace repo,
  Map<String, String> edited,
) {
  final AppStateSource source;
  try {
    source = AppStateSource.of(repo);
  } on Object {
    return const [];
  }
  final after = edited[p.normalize(source.file.absolute.path)];
  if (after == null) {
    return const [];
  }
  return [
    for (final s in source.readSubstates())
      if (s.isSubstate &&
          !RegExp(
            '\\b${RegExp.escape(s.type)}\\s+${RegExp.escape(s.field)}\\b',
          ).hasMatch(after))
        FieldRename(
          from: s.field,
          to: s.field,
          ownerTypes: {
            s.type,
            SubstateArtifact(Casing.parse(s.field)).selectorType,
          },
        ),
  ];
}

/// The identifiers in [source] that are among [gone], minus the ones it
/// declares for itself.
Iterable<String> _namesIn(String source, Set<String> gone) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final own = declaredNamesIn(unit);
  final named = <String>{};
  for (var t = unit.beginToken; !t.isEof; t = t.next!) {
    if (t.type == TokenType.IDENTIFIER &&
        gone.contains(t.lexeme) &&
        !own.contains(t.lexeme)) {
      named.add(t.lexeme);
    }
  }
  return named;
}

/// The route auto_route generates for a `@RoutePage()` class, under the
/// router's `replaceInRouteName: 'PageConnector|Page,Route'`.
String _routeOf(String className) =>
    className.replaceFirst(RegExp(r'(PageConnector|Page)$'), 'Route');
