import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/redux/selectors_source.dart';

import 'support/parses.dart';

const _selectors = '''
import 'app_state.dart';

mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectLogIn get logIn => SelectLogIn(state);
}

extension type SelectConnectivity(AppState _state) {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectLogIn(AppState _state) {
  String? get email => _state.logIn.email;
}
''';

void main() {
  late Directory dir;
  late SelectorsSource source;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('frx_selectors_');
    final file = File('${dir.path}/selectors.dart')
      ..writeAsStringSync(_selectors);
    source = SelectorsSource(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A `selectors.dart` of some other shape, for the compatibility case.
  File _tmp(String content) =>
      File('${dir.path}/other.dart')..writeAsStringSync(content);

  test('wire adds the facade getter and appends the extension type', () {
    final r = source.wire(
      field: 'profile',
      pascal: 'Profile',
      block:
          'extension type SelectProfile(AppState _state) {\n'
          '  String? get value => _state.profile.value;\n'
          '}\n',
      imports: const [],
    );
    expect(r.unchanged, isFalse);
    // One getter, on the mixin. There were two — the second on an `extension
    // type Select` that carried the same list — and nothing called it: no
    // consumer constructed a `Selector` or read `.select`, so half of what
    // wiring a substate cost was a list only this writer ever touched.
    expect(
      r.source,
      contains('SelectProfile get profile => SelectProfile(state);'),
    );
    expect(
      r.source,
      isNot(contains('SelectProfile(_state);')),
      reason: 'the `_state` spelling belonged to the spine type that is gone',
    );
    expect(r.source, contains('extension type SelectProfile('));
    expectParses(r.source);
  });

  test('a project written before the spine collapsed keeps both ways in', () {
    // `frx create` no longer writes `extension type Select`, but every project
    // made before it has one — and its hand-written screens may read
    // `state.select.<field>`, which was a documented way in. Wiring must not
    // *require* the type, and must extend it when it is there: adding to the
    // mixin alone would have `add-substate` report success while
    // `state.select.cart` did not exist, and the developer would meet a compile
    // error in code the tool had just claimed to wire.
    final old = _tmp('''
import 'app_state.dart';

extension type const Selector(AppState _state) {
  Select get select => Select(_state);
}

extension type Select(AppState _state) implements Selector {
  SelectLogIn get logIn => SelectLogIn(_state);
}

mixin Selectors {
  AppState get state;

  SelectLogIn get logIn => SelectLogIn(state);
}

extension type SelectLogIn(AppState _state) implements Selector {
  String? get email => _state.logIn.email;
}
''');

    final r = SelectorsSource(old).wire(
      field: 'profile',
      pascal: 'Profile',
      block: 'extension type SelectProfile(AppState _state) {\n}\n',
      imports: const [],
    );
    expect(r.unchanged, isFalse);
    expect(
      r.source,
      contains('SelectProfile get profile => SelectProfile(state);'),
    );
    expect(
      r.source,
      contains('SelectProfile get profile => SelectProfile(_state);'),
      reason: 'the pre-collapse hop keeps working in the project that has it',
    );
    expectParses(r.source);
  });

  test('wire is idempotent when the Select<Pascal> type already exists', () {
    final r = source.wire(
      field: 'logIn',
      pascal: 'LogIn',
      block: 'extension type SelectLogIn(AppState _state) {}\n',
      imports: const [],
    );
    expect(r.unchanged, isTrue);
    expect(r.source, _selectors);
  });

  test('unwire removes the extension type, both getters and scoped import', () {
    // First wire a search-kind block that pulls in a shared FIC import.
    final wired = source.wire(
      field: 'profile',
      pascal: 'Profile',
      block:
          'extension type SelectProfile(AppState _state) implements Selector {\n'
          '  IList<int> get view => _state.profile.view;\n'
          '}\n',
      imports: const [
        'package:fast_immutable_collections/fast_immutable_collections.dart',
        'profile/models/profile_state.dart',
      ],
    );
    source.file.writeAsStringSync(wired.source);

    final unwired = source.unwire(
      field: 'profile',
      pascal: 'Profile',
      snake: 'profile',
    );
    expect(unwired.found, isTrue);
    source.file.writeAsStringSync(unwired.source);

    expect(unwired.source, isNot(contains('SelectProfile')));
    expect(
      unwired.source,
      isNot(contains('profile/models/profile_state.dart')),
    );
    // The FIC import is now unused → pruned.
    expect(unwired.source, isNot(contains('fast_immutable_collections')));
    // The untouched selectors survive.
    expect(unwired.source, contains('SelectLogIn'));
    expect(unwired.source, contains('SelectConnectivity'));
    expectParses(unwired.source);
  });

  test('unwire reports not-found for an absent selector', () {
    final r = source.unwire(field: 'nope', pascal: 'Nope', snake: 'nope');
    expect(r.found, isFalse);
    expect(r.source, _selectors);
  });
}
