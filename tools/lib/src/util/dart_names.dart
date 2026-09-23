/// Whether a name the user typed can become the Dart the scaffolders write.
///
/// [Casing.parse] checks characters, and characters were all anything checked.
/// So `frx add-substate class` reached the formatter with `required ClassState
/// class` in it and died with a stack trace; `add-field theme switch:bool?`
/// wrote a state file and a facade that did not parse; `add-enum -v default`
/// wrote an enum the analyzer rejected, and `-v values` one that collided with
/// the list every enum already has. None of it is a question about *this*
/// project — it is Dart's grammar, and the members every class of a kind
/// already owns — so it is answered once, here, and every scaffolder asks.
///
/// The per-context lists are maps from the name to what already owns it, so a
/// refusal can say *why*: "`key` is already Widget.key" is a message a user can
/// act on, where "invalid name" is not.
library;

import 'casing.dart';

abstract final class DartNames {
  const DartNames._();

  /// Never an identifier, anywhere.
  static const reserved = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
    'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
    'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var',
    'void', 'while', 'with',
    // Not reserved, but not a name inside the `async` bodies reducers and
    // services are written in.
    'await', 'yield',
  };

  /// Dart's built-in identifiers: legal as some names and not others, and the
  /// code frx writes puts a name in several places at once — a type, a field,
  /// a getter, a named argument. Refused rather than reasoned about per place.
  static const builtIn = {
    'abstract',
    'as',
    'covariant',
    'deferred',
    'dynamic',
    'export',
    'extension',
    'external',
    'factory',
    'Function',
    'get',
    'implements',
    'import',
    'interface',
    'late',
    'library',
    'mixin',
    'operator',
    'part',
    'required',
    'set',
    'static',
    'typedef',
  };

  /// What every Dart object already has.
  static const objectMembers = {
    'hashCode': 'Object.hashCode',
    'runtimeType': 'Object.runtimeType',
    'toString': 'Object.toString',
    'noSuchMethod': 'Object.noSuchMethod',
  };

  /// A field of a freezed class: the object's members plus the `copyWith`
  /// freezed generates beside them.
  static const Map<String, String> freezedMembers = {
    ...objectMembers,
    'copyWith': "freezed's copyWith",
  };

  /// A constructor parameter of a widget, which becomes a field beside the
  /// ones every widget has.
  static const Map<String, String> widgetMembers = {
    ...objectMembers,
    'key': 'Widget.key',
    'build': 'the widget’s build method',
    'createElement': 'Widget.createElement',
  };

  /// An enum value, beside the members every enum already has.
  static const Map<String, String> enumMembers = {
    ...objectMembers,
    'values': 'the enum’s own values list',
    'index': 'Enum.index',
    'name': 'Enum.name',
  };

  /// Why [identifier] cannot be written as a name, or null when it can.
  ///
  /// [taken] is what the context already owns, name → owner.
  static String? problem(
    String identifier, {
    Map<String, String> taken = const {},
  }) {
    if (reserved.contains(identifier)) {
      return '"$identifier" is a reserved word in Dart';
    }
    if (builtIn.contains(identifier)) {
      return '"$identifier" is a Dart built-in identifier';
    }
    if (taken[identifier] case final owner?) {
      return '"$identifier" is already $owner';
    }
    return null;
  }

  /// [problem] for a typed [name], asked of the spellings frx writes it as:
  /// the camel form (a field, a getter, a value) and the Pascal one (a class).
  static String? problemWith(
    Casing name, {
    Map<String, String> taken = const {},
  }) => problem(name.camel, taken: taken) ?? problem(name.pascal);
}
