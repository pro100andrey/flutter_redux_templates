import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'source_index.dart';

/// One constructor parameter of a view-model.
class VmField {
  const VmField({
    required this.name,
    required this.type,
    required this.required,
    this.defaultValue,
  });

  final String name;

  /// The written type, e.g. `String`, `String?`, `List<String>`, `ImageVm`.
  /// Not resolved — frx parses without resolution, so this is the source text.
  final String type;

  /// True for `required this.x`; false for an optional or defaulted one.
  final bool required;

  /// The default expression as written, e.g. `false`. Null when there is none.
  final String? defaultValue;

  bool get nullable => type.endsWith('?');

  /// Whether the written type is a callback.
  ///
  /// A callback outside equality is the idiom, not a defect: `fromStore()`
  /// builds a fresh closure every time, so a view-model that compared them
  /// would be unequal to itself on every rebuild. Ten of this repository's
  /// eleven fields outside equality are these.
  ///
  /// Judged from the source text, because frx does not resolve. An explicit
  /// `Function` type says so outright; everything else is a naming convention —
  /// Flutter's callback typedefs end in `Callback`, `Builder`, `Validator` or
  /// `Predicate`, plus the three `Value…` ones that do not.
  ///
  /// A convention is incomplete by construction: `typedef OnTap = void
  /// Function()` in somebody's project is not recognised, and its field would be
  /// reported. That is the reason this finding is a silenceable warning rather
  /// than an error — and the reason the rule was widened once already, when
  /// `FormFieldValidator<T>?` on this repository's own `FieldVm` was reported
  /// and the file next to it explained, in a comment, exactly why it is correct.
  bool get isCallback {
    final name = bareType.split('<').first;
    return bareType.contains('Function') ||
        const {'ValueChanged', 'ValueSetter', 'ValueGetter'}.contains(name) ||
        const [
          'Callback',
          'Builder',
          'Validator',
          'Predicate',
        ].any(name.endsWith);
  }

  /// The type with any trailing `?` removed — what a value table keys on.
  String get bareType => nullable ? type.substring(0, type.length - 1) : type;

  /// The element type of a `List<T>` / `Iterable<T>`, or null.
  String? get elementType {
    final m = RegExp(r'^(?:List|Iterable)<(.+)>$').firstMatch(bareType);
    return m?.group(1);
  }
}

/// A render model as read from source.
class ViewModel {
  ViewModel({
    required this.className,
    required this.fields,
    required List<String> equality,
    this.declaresOwnEquals = false,
    Set<String> equalityMentions = const {},
    bool equalityReadable = true,
  }) : equality = equality,
       equalityMentions = equalityMentions,
       equalityReadable = equalityReadable;

  final String className;

  /// Constructor parameters, in declaration order.
  final List<VmField> fields;

  /// The names this class compares on, as bare identifiers in its equality list.
  ///
  /// Two shapes, because there are two architectures: `equatable`'s `props`
  /// getter, which this reader was written for, and AsyncRedux's
  /// `super(equals: [\u2026])`, which is what every view-model in this repository
  /// actually uses. Reading only the first is why the check below had never
  /// fired here and could not have.
  ///
  /// Empty is a real answer \u2014 `equals: [1]` compares nothing \u2014 and is no longer
  /// the same as [equalityReadable] being false. Conflating them is what let one
  /// element that changes nothing about `==` switch the rule off for a class.
  final List<String> equality;

  /// Names appearing *inside* elements that are not bare identifiers, so
  /// `ids.length` records `ids`.
  ///
  /// A field here but not in [equality] is compared through something derived
  /// from it, which is not a comparison of it: two lists of equal length and
  /// different contents pass. Worth reporting, and worth reporting differently \u2014
  /// a field spelled right there in the list, called absent, reads as the tool
  /// being wrong.
  final Set<String> equalityMentions;

  /// Whether the equality list could be enumerated at all.
  ///
  /// False for a spread or a computed list, where the membership genuinely is
  /// wider than the text and naming the visible part would invent findings; and
  /// false when the class states no equality. Not false merely because an
  /// element was something other than a field name.
  final bool equalityReadable;

  /// Whether the class writes its own `operator ==`.
  ///
  /// It has then said what equality means, and frx has nothing to add. This
  /// repository has one — a dialog view-model whose `==` is deliberately not an
  /// equivalence relation, with a comment saying so — and a rule that reported
  /// it would be arguing with a decision already taken.
  final bool declaresOwnEquals;

  /// Fields the class left out of its equality, and should not have.
  ///
  /// A value field outside equality is a lie in `==`: two models with different
  /// values compare equal, so a connector's rebuild does not reach the widget.
  /// That is the failure this exists for, and it is a failure of the *clone* —
  /// every view-model in this template is correct, because they were written
  /// once by somebody who knew. The one that grows a field six months later is
  /// the one this catches.
  ///
  /// Empty when the equality list cannot be enumerated (a spread means the real
  /// membership is wider than what is written), and empty when the class
  /// declares its own `==`. Callbacks are never reported.
  List<VmField> get fieldsOutsideEquality =>
      !equalityReadable || declaresOwnEquals
      ? const []
      : [
          for (final f in fields)
            if (!equality.contains(f.name) && !f.isCallback) f,
        ];

  /// Whether [field] is named inside the equality list without being compared —
  /// `ids` for `equals: [view, ids.length]`.
  bool comparedOnlyDerived(VmField field) =>
      !equality.contains(field.name) && equalityMentions.contains(field.name);
}

/// Reads view-model classes out of Dart source, without resolution.
///
/// The shape it expects is the one `add-widget -k view` generates and the
/// package's own models follow: a class with a single generative constructor
/// taking named `this.x` parameters, and its equality stated either in
/// `super(equals: [\u2026])` or in a `props` getter. Anything else reads as
/// "not a view-model" and is skipped rather than half-parsed.
abstract final class VmReader {
  /// Every view-model declared in [source].
  ///
  /// A class qualifies when it has a constructor whose parameters are all
  /// field-initialising (`this.x`) — the pure-data shape. The `Vm` suffix is
  /// not required: `read` is also pointed at the shared models
  /// (`FieldVm`, `ChoiceVm`), and at whatever a hand-written widget uses.
  static List<ViewModel> read(String source) =>
      _of(parseString(content: source, throwIfDiagnostics: false).unit);

  /// The same, for a file — through [sourceIndex], which is the difference.
  ///
  /// This was the one reader in the tier that called `parseString` itself, so
  /// its parses were invisible to the index: `parsesOf` could not count them,
  /// `doctor_test`'s "no file is parsed twice" could not see them, and
  /// `checkRecoveredFiles` could not report a view-model file whose tree was
  /// recovered — even though `checkViewModels` had just answered from it.
  ///
  /// Its only caller is that audit, and it already holds the [File].
  static List<ViewModel> of(File file) => _of(sourceIndex.unitFor(file));

  static List<ViewModel> _of(CompilationUnit unit) => [
    for (final decl in unit.declarations.whereType<ClassDeclaration>())
      if (_readClass(decl) case final vm?) vm,
  ];

  /// The view-model named [className] in [source], or null if absent.
  static ViewModel? readClass(String source, String className) {
    for (final vm in read(source)) {
      if (vm.className == className) return vm;
    }
    return null;
  }

  static ViewModel? _readClass(ClassDeclaration decl) {
    final ctor = _dataConstructor(decl);
    if (ctor == null) return null;
    final declared = _fieldTypes(decl);
    final stated = _equality(decl, ctor);
    return ViewModel(
      className: decl.namePart.typeName.lexeme,
      fields: [
        for (final p in ctor.parameters.parameters)
          if (_readParameter(p, declared) case final f?) f,
      ],
      equality: stated.names,
      equalityMentions: stated.mentions,
      equalityReadable: stated.readable,
      declaresOwnEquals: _members(
        decl,
      ).whereType<MethodDeclaration>().any((m) => m.name.lexeme == '=='),
    );
  }

  /// The constructor a caller would use: the unnamed one whose parameters are
  /// all field-initialising (`this.x`).
  ///
  /// At least one parameter is required. Without that, every marker class and
  /// private-constructor singleton in a file — `StyledSnackbar._()`,
  /// `const Foo()` — reads as a view-model with nothing in it, and a caller
  /// a consumer of whatever [read] returns would pick them up.
  ///
  /// A widget is excluded by its `super.key`, which is not field-initialising;
  /// one written without a key would qualify, which is the other reason callers
  /// name the class they want instead of taking the first that parses.
  static ConstructorDeclaration? _dataConstructor(ClassDeclaration decl) {
    for (final member in _members(decl).whereType<ConstructorDeclaration>()) {
      // Named constructors are alternates (`.fromJson`, `.empty`); the unnamed
      // one is the way to build the thing.
      if (member.name != null) continue;
      if (member.factoryKeyword != null) continue;
      final params = member.parameters.parameters;
      if (params.isEmpty) continue;
      if (params.every((p) => p is FieldFormalParameter)) return member;
    }
    return null;
  }

  static VmField? _readParameter(
    FormalParameter param,
    Map<String, String> declaredTypes,
  ) {
    if (param is! FieldFormalParameter) return null;
    final name = param.name.lexeme;
    // `this.x` is almost never written with a type — the type sits on the
    // field declaration. Reading only the parameter reports every field of
    // every model in this package as `dynamic`.
    return VmField(
      name: name,
      type: param.type?.toSource() ?? declaredTypes[name] ?? 'dynamic',
      required: param.isRequired,
      defaultValue: param.defaultClause?.value.toSource(),
    );
  }

  /// Declared type of each instance field, by name.
  static Map<String, String> _fieldTypes(ClassDeclaration decl) {
    final types = <String, String>{};
    for (final member in _members(decl).whereType<FieldDeclaration>()) {
      if (member.isStatic) continue;
      final type = member.fields.type?.toSource();
      if (type == null) continue;
      for (final v in member.fields.variables) {
        types[v.name.lexeme] = type;
      }
    }
    return types;
  }

  /// A class body's members. An `EmptyClassBody` (`class Foo;`) has none.
  static List<ClassMember> _members(ClassDeclaration decl) {
    final body = decl.body;
    return body is BlockClassBody ? body.members : const [];
  }

  /// The names this class compares on, from whichever shape it uses.
  ///
  /// `super(equals: [\u2026])` first, because it is what this repository writes;
  /// a `props` getter otherwise. A class using neither states no equality, which
  /// is not the same as stating an empty one.
  static _Equality _equality(
    ClassDeclaration decl,
    ConstructorDeclaration ctor,
  ) {
    for (final initializer in ctor.initializers) {
      if (initializer is! SuperConstructorInvocation) continue;
      for (final arg in initializer.argumentList.arguments) {
        if (arg is! NamedArgument || arg.name.lexeme != 'equals') continue;
        return _identifiersIn(arg.argumentExpression);
      }
    }
    return _props(decl);
  }

  /// The identifiers listed by the `props` getter, in order.
  ///
  /// Only a plain list literal of identifiers is understood — a computed
  /// `props` is left as unknown (an empty list) rather than half-read, so the
  /// lint stays quiet instead of guessing wrong.
  static _Equality _props(ClassDeclaration decl) {
    for (final m in _members(decl).whereType<MethodDeclaration>()) {
      if (!m.isGetter || m.name.lexeme != 'props') continue;
      final body = m.body;
      final expr = switch (body) {
        ExpressionFunctionBody(:final expression) => expression,
        BlockFunctionBody(:final block) => switch (block.statements) {
          [ReturnStatement(:final expression?)] => expression,
          _ => null,
        },
        _ => null,
      };
      return expr == null ? const _Equality.unreadable() : _identifiersIn(expr);
    }
    // No `equals:` and no `props`: the class states no equality at all, which is
    // not the same as stating one frx cannot read — but both leave the rule with
    // nothing to check, so both are unreadable here.
    return const _Equality.unreadable();
  }

  /// What a written equality list actually compares.
  ///
  /// ## Why not all-or-nothing
  ///
  /// This used to return "unknown" for any element that was not a bare
  /// identifier, on the reasoning that the real membership might be wider than
  /// what is written. That is true of exactly one shape — a spread, which can
  /// carry the very field that looks missing — and false of every other:
  ///
  /// ```dart
  /// super(equals: [view, 1])                 // `1` compares nothing
  /// super(equals: [view, other.hashCode])    // nor does another object's hash
  /// ```
  ///
  /// Both left `ids` genuinely uncompared, and both silenced the rule for the
  /// whole class. Measured on one project: every row of a four-row experiment
  /// had a field outside equality, and three of the four were quiet, told apart
  /// only by an element that changed nothing about what `==` does. A rule that
  /// an unrelated literal switches off is worse than one that does not exist,
  /// because the clean run is read as evidence.
  ///
  /// So unknown now means what it says: a list frx cannot enumerate at all.
  /// Everything else is enumerated, and an element that names no field simply
  /// compares no field.
  ///
  /// [mentions] carries the names that appear *inside* non-bare elements, so
  /// `ids.length` can be reported as the partial comparison it is rather than as
  /// an absence — the field is spelled right there, and calling it missing reads
  /// as the tool being wrong.
  static _Equality _identifiersIn(Expression expr) {
    if (expr is! ListLiteral) return const _Equality.unreadable();

    final names = <String>[];
    final mentions = <String>{};
    for (final e in expr.elements) {
      // A spread, or an `if`/`for` that computes the list: the membership is
      // genuinely wider than the text, and naming the visible part would invent
      // findings for fields the spread may well carry.
      if (e is! Expression) return const _Equality.unreadable();
      if (e is SimpleIdentifier) {
        names.add(e.name);
        continue;
      }
      e.accept(_IdentifierNames(mentions.add));
    }
    return _Equality(names: names, mentions: mentions);
  }
}

/// A view-model's stated equality, as far as it can be read.
class _Equality {
  const _Equality({required this.names, required this.mentions})
    : readable = true;

  /// A list frx cannot enumerate — a spread, or not a list literal at all.
  const _Equality.unreadable()
    : names = const [],
      mentions = const {},
      readable = false;

  final List<String> names;
  final Set<String> mentions;
  final bool readable;
}

/// The identifiers an expression *reads*, excluding member names.
///
/// `user.id` reads `user`; `id` is a member of it and names nothing in this
/// class. Collecting both made `equals: [user.id, tasks.length]` record `id`,
/// so an unrelated field of that name was reported as "compared only through
/// something derived from it" — the finding stayed true and its wording, which
/// is the whole reason the wording exists, became false.
class _IdentifierNames extends RecursiveAstVisitor<void> {
  _IdentifierNames(this.onName);

  final void Function(String) onName;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final isMemberName =
        (parent is PropertyAccess && parent.propertyName == node) ||
        (parent is PrefixedIdentifier && parent.identifier == node) ||
        (parent is MethodInvocation && parent.methodName == node);
    if (!isMemberName) onName(node.name);
    super.visitSimpleIdentifier(node);
  }
}
