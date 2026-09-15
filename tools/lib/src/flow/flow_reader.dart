import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../ast/source_index.dart';
import '../workspace/frx_workspace.dart';
import 'action_reader.dart';
import 'connector_visitor.dart';
import 'dispatch_visitor.dart';
import 'flow_model.dart';

/// Every `dispatch*(...)` in a file, paired with the action files its imports
/// resolve to.
typedef DispatchRead = ({
  List<DispatchStep> steps,
  Map<String, File> actionFiles,
});

/// Reads a page's use-case flow out of the source AST.
///
/// Parse-only, like the rest of frx — which means the parser cannot know that
/// `RegistrationAction(...)` is a constructor rather than a function call, so
/// both arrive as a [MethodInvocation] with a null target. That's fine: frx
/// already keys off the naming conventions it generates.
class FlowReader {
  FlowReader(this.workspace);

  final FrxWorkspace workspace;

  /// Build the flow for [connectorFile] — its `_Vm` callbacks, the actions they
  /// dispatch, and what each of those actions does.
  /// **It descends into the connectors the page is composed of.** A route
  /// connector need not hold a view-model at all: a page split into regions
  /// hands each slot a connector of its own, and the frame is then a `build`
  /// that constructs six widgets and reads nothing. Stopping at the route
  /// connector reported such a page as having no interactions — not "the frame
  /// has none", which is true, but "the page has none", which is the opposite
  /// of why the split was made. The regions are where every callback went.
  ///
  /// Depth is not bounded. The composition that prompted this is three deep —
  /// a page, a content region switching between eight views, and a rail taking
  /// a project picker as a slot — and "one level" would be a number chosen to
  /// fit one app.
  ///
  /// One index scope per read: the walk reaches an action file through the
  /// region that dispatches it and again through the page's own imports, and
  /// outside a scope every lookup is a fresh parse.
  PageFlow read({
    required File connectorFile,
    required String page,
    required String connectorClass,
    required String pageClass,
  }) => inSourceIndex(
    () => _read(
      connectorFile: connectorFile,
      page: page,
      connectorClass: connectorClass,
      pageClass: pageClass,
    ),
  );

  PageFlow _read({
    required File connectorFile,
    required String page,
    required String connectorClass,
    required String pageClass,
  }) {
    final useCases = <UseCase>[];
    final actions = <String, ActionInfo>{};
    final regions = <String>[];
    final untraced = <UntracedDispatch>[];

    // Keyed by canonical path: a region reachable through two slots is one
    // region, and a cycle between two connectors is a stack overflow.
    final seen = <String>{};

    void walk(File file, String? owner) {
      if (!seen.add(p.canonicalize(file.path))) {
        return;
      }

      final unit = sourceIndex.unitFor(file);

      final vm = _VmVisitor(localFunctionBodies(unit));
      unit.accept(vm);

      // What the file dispatches, against what the walk got to. The difference
      // is reported rather than dropped: a region with no use case gets no lane
      // and vanishes, and a map that is quietly six regions short is read as a
      // map of a page that is small. See [UntracedDispatch].
      //
      // Compared as *sets of call sites*, never as counts. One helper reached
      // from two `_Vm` fields is a shape `_VmVisitor` supports on purpose, and
      // it makes attributions outnumber call sites — subtracting tallies then
      // reads as "nothing missing" and hides a genuinely unreachable dispatch
      // elsewhere in the same file.
      final all = DispatchVisitor();
      unit.accept(all);
      final missed = all.callSites.difference(vm.attributed);
      if (missed.isNotEmpty) {
        untraced.add(
          UntracedDispatch(
            connectorClass: owner ?? connectorClass,
            count: missed.length,
          ),
        );
      }

      // Resolve every `package:business/...` import to a file on disk so a
      // dispatched action can be looked up by class name.
      final actionFiles = _actionFilesFrom(unit, file.parent);

      for (final useCase in vm.useCases) {
        useCases.add(
          owner == null
              ? useCase
              : UseCase(name: useCase.name, steps: useCase.steps, owner: owner),
        );
        for (final step in useCase.steps) {
          if (step.isNavigation || actions.containsKey(step.target)) {
            continue;
          }

          final actionFile = actionFiles[step.target];
          actions[step.target] = actionFile == null
              ? ActionInfo(className: step.target)
              : readAction(actionFile);
        }
      }

      // Depth-first in source order, so the regions read down the page the way
      // its slots are written.
      for (final nested in _connectorsIn(unit, file.parent).entries) {
        if (seen.contains(p.canonicalize(nested.value.path))) {
          continue;
        }
        regions.add(nested.key);
        walk(nested.value, nested.key);
      }
    }

    walk(connectorFile, null);

    return PageFlow(
      page: page,
      connectorClass: connectorClass,
      pageClass: pageClass,
      useCases: useCases,
      actions: actions,
      connectorFile: connectorFile.path,
      regions: regions,
      untraced: untraced,
    );
  }

  /// The connector classes constructed inside [unit], by class name, in source
  /// order — each resolved to the file its import points at.
  ///
  /// **Constructions, not imports.** A connector importing another proves
  /// nothing about composition: a sidebar imports six action files it never
  /// builds. What makes a region part of a page is that the page's connector
  /// *builds* it — as a slot argument, or inside the `switch` a content region
  /// uses to pick one of eight views.
  ///
  /// Only `app`'s connectors can appear: `ui` does not depend on `app`, so a
  /// slot is filled where the widget tree is assembled and nowhere else.
  Map<String, File> _connectorsIn(CompilationUnit unit, Directory from) {
    final built = connectorNamesIn(unit);
    if (built.isEmpty) {
      return const {};
    }

    return {
      for (final (cls, file) in _importedClasses(unit, from, '_connector.dart'))
        if (built.contains(cls)) cls: file,
    };
  }

  /// Every `dispatch*(...)` in [file], paired with the action files its imports
  /// resolve to.
  ///
  /// The same read [read] performs on a connector, for a source that is not
  /// one. A service dispatcher dispatches into the store exactly as a
  /// view-model does, but it has no `_Vm` and no page — so a reader that only
  /// walks connectors reports its actions as dispatched by nobody.
  DispatchRead readDispatches(File file) =>
      dispatchesIn(sourceIndex.unitFor(file), file.parent);

  /// [readDispatches] for a caller that already holds the tree — a sweep that
  /// asks several questions of one file need not fetch it once per question.
  DispatchRead dispatchesIn(CompilationUnit unit, Directory from) {
    final v = DispatchVisitor();
    unit.accept(v);
    return (steps: v.steps, actionFiles: _actionFilesFrom(unit, from));
  }

  /// What a single action does: its mixins, whether it's async, the AppState
  /// field it writes, any cascading dispatches, and whether it can fail loudly.
  ActionInfo readAction(File file) => readActionWithImports(file).info;

  /// [readAction] plus the action files this action's own imports resolve to,
  /// from one parse.
  ///
  /// A caller that follows cascades needs both — what the action dispatches and
  /// which file each dispatched name refers to. Asking for them separately
  /// parsed every action file twice, and threw away a `steps` list identical to
  /// the `dispatches` it already held.
  ({ActionInfo info, Map<String, File> actionFiles}) readActionWithImports(
    File file,
  ) {
    final unit = sourceIndex.unitFor(file);
    return (
      info: readActionInfo(unit, file),
      actionFiles: _actionFilesFrom(unit, file.parent),
    );
  }

  /// Map of `ActionClassName` → file, built from the unit's `_action.dart`
  /// imports. A `package:business/redux/x/actions/y_action.dart` import maps to
  /// `<root>/business/lib/redux/x/actions/y_action.dart`.
  Map<String, File> _actionFilesFrom(CompilationUnit unit, Directory from) => {
    for (final (cls, file) in _importedClasses(unit, from, '_action.dart'))
      cls: file,
  };

  /// The class each import of [unit] ending in [suffix] declares, paired with
  /// the file the import resolves to, in import order. Imports that resolve to
  /// nothing on disk, or to a file declaring no class, are skipped.
  ///
  /// [from] is the directory holding the source, needed for relative imports:
  /// a connector lives in `app` and reaches actions by package uri, but a
  /// service lives *inside* `business` and reaches them by `../../`.
  Iterable<(String, File)> _importedClasses(
    CompilationUnit unit,
    Directory from,
    String suffix,
  ) sync* {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || !uri.endsWith(suffix)) {
        continue;
      }

      final file = _resolveImport(uri, from);
      if (file == null || !file.existsSync()) {
        continue;
      }

      final cls = firstClassNameIn(sourceIndex.unitFor(file));
      if (cls != null) {
        yield (cls, file);
      }
    }
  }

  /// `package:<pkg>/<path>` → `<root>/<pkg>/lib/<path>`; anything without a
  /// scheme is resolved against [from].
  File? _resolveImport(String uri, Directory from) {
    if (!uri.startsWith('package:')) {
      if (uri.contains(':')) {
        return null; // dart:, http: — not ours
      }

      return File(p.normalize(p.join(from.path, uri)));
    }
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) {
      return null;
    }
    return File(
      p.join(
        workspace.root.path,
        rest.substring(0, slash),
        'lib',
        rest.substring(slash + 1),
      ),
    );
  }
}

/// Finds the `_Vm(...)` construction and treats each named argument as one
/// user-facing interaction.
///
/// Each argument is read with the file's own function table in hand, so a
/// callback assembled by a helper on the factory is followed rather than
/// missed — see [DispatchVisitor].
class _VmVisitor extends RecursiveAstVisitor<void> {
  _VmVisitor(this._locals);

  final Map<String, AstNode> _locals;
  final useCases = <UseCase>[];

  /// Every `dispatch*(` call site any use case here accounts for.
  ///
  /// A set and not a count, because the same site legitimately answers for two
  /// fields — see the accounting in [FlowReader.read].
  final attributed = <int>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == '_Vm') {
      for (final a in node.argumentList.arguments.whereType<NamedArgument>()) {
        // A visited set per argument, not per file: two fields may legitimately
        // both go through the same row helper, and each is its own use case.
        final v = DispatchVisitor(a.argumentExpression, _locals);
        a.argumentExpression.accept(v);
        if (v.steps.isEmpty) {
          continue;
        }
        attributed.addAll(v.callSites);
        useCases.add(UseCase(name: a.name.lexeme, steps: v.steps));
      }
    }
    super.visitMethodInvocation(node);
  }
}
