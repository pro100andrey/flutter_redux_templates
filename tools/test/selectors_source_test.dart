import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/redux/selectors_source.dart';

import 'support/parses.dart';

const _selectors = '''
import 'app_state.dart';

extension type const Selector(AppState _state) {
  Select get select => Select(_state);
}

extension type Select(AppState _state) implements Selector {
  SelectConnectivity get connectivity => SelectConnectivity(_state);
  SelectLogIn get logIn => SelectLogIn(_state);
}

mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectLogIn get logIn => SelectLogIn(state);
}

extension type SelectConnectivity(AppState _state) implements Selector {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectLogIn(AppState _state) implements Selector {
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

  test('wire adds both facade getters and appends the extension type', () {
    final r = source.wire(
      field: 'profile',
      pascal: 'Profile',
      block:
          'extension type SelectProfile(AppState _state) implements Selector {\n'
          '  String? get value => _state.profile.value;\n'
          '}\n',
      imports: const [],
    );
    expect(r.unchanged, isFalse);
    expect(
      r.source,
      contains('SelectProfile get profile => SelectProfile(_state);'),
    );
    expect(
      r.source,
      contains('SelectProfile get profile => SelectProfile(state);'),
    );
    expect(r.source, contains('extension type SelectProfile('));
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
