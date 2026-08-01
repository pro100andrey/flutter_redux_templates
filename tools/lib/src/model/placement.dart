/// Code that is fully wired, compiles, and still sits in the wrong place.
///
/// The audit's other checks are about **drift** — two things out of sync with
/// each other. This is about *convention*: a selector declared outside the
/// facade, an action file outside its substate's `actions/` directory, an
/// annotated page connector outside the connectors package. Nothing else catches
/// it. The Dart analyzer knows Dart, not this architecture.
///
/// **Why here and not in an analyzer plugin.** A plugin would get resolved
/// types, which is strictly more information. But `tools/` sits outside the pub
/// workspace by design (so its `analyzer` dependency stays isolated), so a plugin
/// could not import the modules that own these conventions — [FrxWorkspace] for
/// which folders under `redux/` are substates and where the facade and the
/// connectors package live, and `model/` for the naming — and the conventions
/// would fork. That is the failure this repository has already paid for once,
/// when a command list copied into the editor drifted to eight of ten entries. So
/// a check that needs the conventions lives beside them.
///
/// **The scope is therefore placement, not inheritance.** Parsing can judge
/// where a declaration sits. It cannot soundly judge what a class *extends*:
/// aliases, re-exports and intermediate bases all defeat a syntactic reading.
///
/// **The rule for admitting a future rule: it ships only if its syntactic form
/// cannot be wrong in the common case.** Every rule here keys on a folder, a
/// filename convention, or an annotation that is present or absent. A rule about
/// what a type *is* stays with the analyzer.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
import 'page_artifact.dart';
import '../workspace/frx_workspace.dart';
import 'selector_shape.dart';

/// A convention about where a declaration belongs.
///
/// Each is separately silenceable through `.frxrc`, by [id]. False positives here
/// are guaranteed by construction rather than by accident — this template is
/// cloned and diverged from on purpose — so a project that means it must be able
/// to say so per rule rather than switching the whole check off.
enum PlacementRule {
  /// A selector declared anywhere but the facade.
  selectorOutsideFacade(
    'selector-outside-facade',
    'a selector declared outside the selectors facade',
  ),

  /// An action file outside `redux/<substate>/actions/`.
  actionOutsideActionsDir(
    'action-outside-actions-dir',
    "an action file outside its substate's actions directory",
  ),

  /// An `@RoutePage()` class outside the connectors package.
  connectorOutsideConnectors(
    'connector-outside-connectors',
    'an annotated page connector outside the connectors package',
  ),

  /// A view-model value field left out of the equality it declares.
  ///
  /// Not a placement rule in the "wrong folder" sense, and here anyway: what
  /// this enum really is, is the set of findings a project may silence — and
  /// this is the one that most needs to be silenceable, because recognising a
  /// callback is a list of type names and a clone is free to typedef its own.
  fieldOutsideEquality(
    'field-outside-equality',
    "a view-model field missing from the equality it declares",
  );

  const PlacementRule(this.id, this.summary);

  /// The `.frxrc` key, kebab-case like the finding it produces.
  final String id;

  /// What it reports, for the docs and the help text.
  final String summary;

  static PlacementRule? byId(String id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// One misplaced declaration: which rule, which file, and what to say.
typedef PlacementFinding = ({PlacementRule rule, String file, String message});

/// Every placement finding in [repo], minus the [silenced] rules.
///
/// One sweep of the three lib trees frx already sweeps, with a cheap textual
/// pre-filter before each parse: the point of the rules is to be affordable on
/// every audit, and parsing every file to find the handful that could match
/// would make the audit something you avoid running.
List<PlacementFinding> placementFindings(
  FrxWorkspace repo, {
  Set<PlacementRule> silenced = const {},
}) {
  final findings = <PlacementFinding>[];
  final facade = p.canonicalize(repo.selectorsFile.path);
  final connectors = p.canonicalize(repo.appConnectors.path);
  final businessLib = p.canonicalize(repo.businessLib.path);
  final reduxDir = p.canonicalize(repo.businessRedux.path);

  String rel(String path) => p.relative(path, from: repo.root.path);

  for (final pkg in const ['business', 'app', 'ui']) {
    final lib = Directory(p.join(repo.root.path, pkg, 'lib'));
    // Generated output is not anybody's placement decision, and the index
    // leaves it out of every listing.
    for (final entity in sourceIndex.filesUnder(lib)) {
      final path = p.canonicalize(entity.path);

      // --- an action file outside its substate's actions/ ------------------
      //
      // Only under `business/lib`, which is where this convention applies. The
      // app package has its own `navigation/go_action.dart` — a navigation
      // action, not a substate's — and a rule that reported it would be wrong
      // about a file the architecture puts exactly where it belongs.
      if (!silenced.contains(PlacementRule.actionOutsideActionsDir) &&
          p.basename(path).endsWith('_action.dart') &&
          p.isWithin(businessLib, path) &&
          !_isInActionsDir(path, reduxDir)) {
        findings.add((
          rule: PlacementRule.actionOutsideActionsDir,
          file: entity.path,
          message:
              '${rel(entity.path)} — an action belongs in '
              'redux/<substate>/actions/.',
        ));
      }

      // Two questions over one file, and the parse is worth doing only if at
      // least one of them could say yes. The pre-filter is textual and the
      // judgement is not: it decides whether to look, never what to report.
      final source = sourceIndex.sourceOf(entity);
      final wantsSelectors =
          !silenced.contains(PlacementRule.selectorOutsideFacade) &&
          path != facade &&
          source.contains('extension') &&
          source.contains('Select');
      final wantsConnector =
          !silenced.contains(PlacementRule.connectorOutsideConnectors) &&
          !p.isWithin(connectors, path) &&
          source.contains('@${PageArtifact.routePageAnnotation}');
      if (!wantsSelectors && !wantsConnector) continue;

      final unit = sourceIndex.unitFor(entity);

      for (final decl in unit.declarations) {
        // --- a selector outside the facade --------------------------------
        final selector = wantsSelectors ? SelectorShape.of(decl) : null;
        if (selector != null) {
          findings.add((
            rule: PlacementRule.selectorOutsideFacade,
            file: entity.path,
            message:
                '${rel(entity.path)} — ${selector.label} belongs in '
                '${rel(repo.selectorsFile.path)}, the single home for '
                'selectors.',
          ));
        }

        // --- an annotated connector outside the connectors package --------
        if (wantsConnector &&
            decl is ClassDeclaration &&
            PageArtifact.isRoutePage(decl)) {
          findings.add((
            rule: PlacementRule.connectorOutsideConnectors,
            file: entity.path,
            message:
                '${rel(entity.path)} — @RoutePage() ${decl.namePart.typeName.lexeme} '
                'belongs in ${rel(repo.appConnectors.path)}.',
          ));
        }
      }
    }
  }
  return findings;
}

/// Whether [path] sits at `redux/<substate>/actions/…`.
bool _isInActionsDir(String path, String reduxDir) {
  if (!p.isWithin(reduxDir, path)) return false;
  final parts = p.split(p.relative(path, from: reduxDir));
  // <substate>/actions/<file>, and the folder has to be a substate — an action
  // file under `redux/services/actions/` is not in a substate's actions dir.
  return parts.length == 3 &&
      parts[1] == 'actions' &&
      FrxWorkspace.isSubstateDir(parts[0]);
}
