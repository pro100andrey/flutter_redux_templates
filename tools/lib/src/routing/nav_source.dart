import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast/construction.dart';
import '../ast/source_index.dart';
import '../redux/ast_edit.dart';

/// The outcome of wiring one navigation hop into a file.
class NavWireResult implements EditOutcome {
  const NavWireResult({
    required this.source,
    required this.changes,
    required this.alreadyWired,
  });

  /// The full, edited source (unchanged if [alreadyWired]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a callback of that name was already there — nothing changed.
  final bool alreadyWired;

  @override
  bool get unchanged => alreadyWired;
}

/// One argument the destination route takes — `id` of type `int`.
class NavParam {
  const NavParam(this.name, this.type);

  final String name;
  final String type;
}

/// Reads and edits a page connector and its dumb page to add a navigation hop.
///
/// A hop is not one edit but five, spread over two packages: the callback in
/// `_Vm`, the `dispatch(GoAction.push(...))` that fills it, the argument handed
/// down in `builder:`, and the parameter plus field on the page itself. Doing
/// four of them leaves code that does not compile, which is why they live in
/// one place rather than in the command.
class NavSource {
  const NavSource();

  /// The route's parameters, read from the destination connector's fields —
  /// `final int id;` next to a `this.id` constructor parameter.
  ///
  /// Read from the connector rather than from the `:id` segments of the route
  /// path: the path says a parameter exists, only the field says its type.
  static List<NavParam> paramsOf(File connector) {
    if (!connector.existsSync()) return const [];
    final unit = sourceIndex.unitFor(connector);
    for (final d in unit.declarations.whereType<ClassDeclaration>()) {
      final name = d.namePart.typeName.lexeme;
      if (!name.endsWith('Connector')) continue;
      final body = d.body;
      if (body is! BlockClassBody) continue;

      // Only what the constructor binds as `this.<name>`, in the order it
      // takes them. Every field would sweep up anything the connector holds
      // for itself — a controller, a cached value — and hand it to a route
      // constructor that does not accept it.
      final bound = <String>[
        for (final c in body.members.whereType<ConstructorDeclaration>())
          for (final param in c.parameters.parameters)
            if (param is FieldFormalParameter) param.name.lexeme,
      ];
      final types = {
        for (final f in body.members.whereType<FieldDeclaration>())
          if (f.fields.type != null && !f.isStatic)
            for (final v in f.fields.variables)
              v.name.lexeme: f.fields.type!.toSource(),
      };
      return [
        for (final n in bound)
          if (types[n] case final type?) NavParam(n, type),
      ];
    }
    return const [];
  }

  /// Wires the hop into the *source* connector: the `_Vm` callback, the
  /// dispatch that fills it, the argument passed to the page, and the two
  /// imports the route and `GoAction` need.
  ///
  /// [args] is what the route constructor is handed, already spelled — `id: id`
  /// for a callback that takes the id, `productId: connector.id` for one the
  /// connector already holds.
  NavWireResult wireConnector({
    required String original,
    required String callback,
    required String routeType,
    required String method,
    required String args,
    required List<NavParam> params,
    required String pageClass,
  }) {
    // The imports go in first, one re-parse each: `importInsertion` places an
    // import among the ones it can see, and two computed against the same parse
    // both aim at the spot the other is about to take.
    var content = original;
    final changes = <String>[];
    for (final uri in [
      '../navigation/app_router.dart',
      '../navigation/go_action.dart',
    ]) {
      final dirs = parseString(
        content: content,
        throwIfDiagnostics: false,
      ).unit.directives.whereType<ImportDirective>().toList();
      if (dirs.any((d) => d.uri.stringValue == uri)) continue;
      content = applyEdits(content, [importInsertion(dirs, uri)]);
      changes.add("import '$uri';");
    }

    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    final vm = _class(unit, '_Vm');
    final factory = _class(unit, '_Factory');
    if (vm == null || factory == null) {
      throw StateError(
        'the connector has no `_Vm`/`_Factory` pair — it was not written by '
        'frx, so where the callback goes is a guess',
      );
    }
    if (_hasField(vm, callback)) {
      return NavWireResult(
        source: original,
        changes: const [],
        alreadyWired: true,
      );
    }

    final signature = 'void Function(${params.map((p) => p.type).join(', ')})';
    final edits = <Edit>[];

    // `_Vm({required this.onTapItem, …})` plus the field it initialises.
    final ctor = _constructor(vm);
    if (ctor == null) {
      throw StateError('`_Vm` has no constructor to add the callback to');
    }
    edits.add(_namedParamInsertion(ctor, 'required this.$callback'));
    edits.add(Edit.insert(vm.end - 1, '\n  final $signature $callback;\n'));
    changes.add('_Vm.$callback ($signature)');

    // `_Vm fromStore() => _Vm(onTapItem: (id) => dispatch(…))`.
    final created = _vmCreation(factory);
    if (created == null) {
      throw StateError('`_Factory.fromStore` does not return a `_Vm(...)`');
    }
    final lambda = params.map((p) => p.name).join(', ');
    edits.add(
      insertIntoList(
        elements: created.arguments.arguments,
        closer: created.arguments.rightParenthesis,
        element:
            '$callback: ($lambda) => '
            'dispatch(GoAction.$method($routeType($args)))',
      ),
    );
    changes.add('dispatch(GoAction.$method($routeType($args)))');

    // `builder: (context, vm) => CatalogPage(onTapItem: vm.onTapItem)`. The
    // page gains an argument, so a `const` construction cannot stay const.
    final page = _builderPage(unit, pageClass);
    if (page != null) {
      final keyword = page.constKeyword;
      if (keyword != null && keyword.lexeme == 'const') {
        edits.add(Edit.replace(keyword.offset, page.nameOffset, ''));
      }
      edits.add(
        insertIntoList(
          elements: page.arguments.arguments,
          closer: page.arguments.rightParenthesis,
          element: '$callback: vm.$callback',
        ),
      );
      changes.add('$pageClass($callback: vm.$callback)');
    }

    return NavWireResult(
      source: applyEdits(content, edits),
      changes: changes,
      alreadyWired: false,
    );
  }

  /// Wires the receiving end into the dumb page: the constructor parameter and
  /// the field. What the page *does* with the callback is left alone — which
  /// button calls it is the one part of this frx cannot know.
  NavWireResult wirePage({
    required String content,
    required String callback,
    required String pageClass,
    required List<NavParam> params,
  }) {
    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    final cls = _class(unit, pageClass);
    if (cls == null) {
      throw StateError('no `class $pageClass` in the page file');
    }
    if (_hasField(cls, callback)) {
      return NavWireResult(
        source: content,
        changes: const [],
        alreadyWired: true,
      );
    }
    final ctor = _constructor(cls);
    if (ctor == null) {
      throw StateError('`$pageClass` has no constructor');
    }

    final signature = 'void Function(${params.map((p) => p.type).join(', ')})';
    // Before `super.key`, which convention keeps last.
    final named = _namedParams(ctor).toList();
    final superKey = named.where((p) => p.name?.lexeme == 'key').firstOrNull;
    return NavWireResult(
      source: applyEdits(content, [
        superKey != null
            ? Edit.insert(superKey.offset, 'required this.$callback, ')
            : _namedParamInsertion(ctor, 'required this.$callback'),
        Edit.insert(cls.end - 1, '\n  final $signature $callback;\n'),
      ]),
      changes: ['$pageClass.$callback ($signature)'],
      alreadyWired: false,
    );
  }

  ClassDeclaration? _class(CompilationUnit unit, String name) {
    for (final d in unit.declarations.whereType<ClassDeclaration>()) {
      if (d.namePart.typeName.lexeme == name) return d;
    }
    return null;
  }

  List<ClassMember> _members(ClassDeclaration c) {
    final body = c.body;
    return body is BlockClassBody ? body.members : const [];
  }

  bool _hasField(ClassDeclaration c, String name) => _members(c)
      .whereType<FieldDeclaration>()
      .any((f) => f.fields.variables.any((v) => v.name.lexeme == name));

  ConstructorDeclaration? _constructor(ClassDeclaration c) =>
      _members(c).whereType<ConstructorDeclaration>().firstOrNull;

  /// The named parameters of [ctor] — the `{…}` group a callback joins.
  Iterable<FormalParameter> _namedParams(ConstructorDeclaration ctor) =>
      ctor.parameters.parameters.where((p) => p.isNamed);

  /// Splices a named parameter into [ctor], opening a `{…}` group when the
  /// constructor has none.
  ///
  /// `_Vm()` takes nothing at all, and inserting into its parameter list
  /// straight makes the parameter *positional* — `_Vm(required this.onTap)`,
  /// which does not parse. Every generated `_Vm` starts out that way, so this
  /// is the common case rather than the corner one.
  Edit _namedParamInsertion(ConstructorDeclaration ctor, String element) {
    final params = ctor.parameters;
    final named = params.parameters.where((p) => p.isNamed).toList();
    if (named.isNotEmpty) {
      return insertIntoList(
        elements: named,
        closer: params.rightDelimiter ?? params.rightParenthesis,
        element: element,
      );
    }
    // Dart forbids a constructor from having both an `[optional]` group and a
    // named one, so there is no correct place to put this — appending after
    // the last parameter would splice it inside the brackets and produce
    // source that does not parse. Refused rather than mangled, like a
    // connector frx did not write.
    if (params.parameters.any((p) => p.isOptionalPositional)) {
      throw StateError(
        'the constructor takes optional positional parameters, which Dart '
        'does not allow alongside named ones — add `$element` by hand',
      );
    }
    final positional = params.parameters.toList();
    return positional.isEmpty
        ? Edit.insert(params.rightParenthesis.offset, '{$element}')
        : Edit.insert(positional.last.end, ', {$element}');
  }

  /// The `_Vm(...)` that `fromStore` returns.
  Construction? _vmCreation(ClassDeclaration factory) {
    for (final m in _members(factory).whereType<MethodDeclaration>()) {
      if (m.name.lexeme != 'fromStore') continue;
      final body = m.body;
      final expr = body is ExpressionFunctionBody
          ? body.expression
          : _returned(body);
      final made = Construction.of(expr);
      if (made != null && made.fullName == '_Vm') return made;
    }
    return null;
  }

  Expression? _returned(FunctionBody body) {
    final finder = _ReturnFinder();
    body.accept(finder);
    return finder.expression;
  }

  /// The page construction inside `builder: (context, vm) => <Page>(…)`.
  Construction? _builderPage(CompilationUnit unit, String pageClass) {
    final finder = _PageCreationFinder(pageClass);
    unit.accept(finder);
    return finder.found;
  }
}

class _ReturnFinder extends GeneralizingAstVisitor<void> {
  Expression? expression;

  @override
  void visitReturnStatement(ReturnStatement node) {
    expression ??= node.expression;
  }
}

class _PageCreationFinder extends GeneralizingAstVisitor<void> {
  _PageCreationFinder(this.pageClass);

  final String pageClass;
  Construction? found;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _consider(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _consider(node);
    super.visitMethodInvocation(node);
  }

  void _consider(Expression e) {
    final made = Construction.of(e);
    if (made != null && made.fullName == pageClass) found ??= made;
  }
}
