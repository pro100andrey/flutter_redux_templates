import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/redux/app_state_source.dart';

import 'support/parses.dart';

const _appState = '''
import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/models/connectivity_state.dart';
import 'log_in/models/log_in_state.dart';

part 'app_state.freezed.dart';

@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LogInState logIn,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    connectivity: ConnectivityState(),
    logIn: LogInState(),
    wait: Wait.empty,
  );
}
''';

void main() {
  late Directory dir;
  late AppStateSource source;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('frx_appstate_');
    final file = File('${dir.path}/app_state.dart')
      ..writeAsStringSync(_appState);
    source = AppStateSource(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('readSubstates lists the composed fields in source order', () {
    final subs = source.readSubstates();
    expect(subs.map((s) => s.field), ['connectivity', 'logIn', 'wait']);
    expect(subs.map((s) => s.type), [
      'ConnectivityState',
      'LogInState',
      'Wait',
    ]);
  });

  test('wire adds import, factory field, and initial() entry before wait', () {
    final r = source.wireSubstate(
      field: 'profile',
      type: 'ProfileState',
      importPath: 'profile/models/profile_state.dart',
    );
    expect(r.alreadyWired, isFalse);
    expect(r.changes, hasLength(3));

    // Re-parse the produced source to confirm the field is now composed and
    // still sits before the framework `wait` field (which must stay last).
    source.file.writeAsStringSync(r.source);
    final fields = source.readSubstates().map((s) => s.field).toList();
    expect(fields, ['connectivity', 'logIn', 'profile', 'wait']);
    expect(r.source, contains("import 'profile/models/profile_state.dart';"));
    expect(r.source, contains('profile: ProfileState()'));
    expectParses(r.source);
  });

  test('wire onto a state with no `wait` still produces valid Dart', () {
    // Every fixture here includes `wait`, which is the only thing the two
    // insertions had to anchor before. Without it they used to splice at the
    // closing delimiter and fuse onto the neighbour — `logInrequired
    // ProfileState profile` — and no assertion in the suite noticed, because
    // each one only asked whether its own fragment was present.
    source.file.writeAsStringSync('''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({required LogInState logIn}) = _AppState;

  factory AppState.initial() => const AppState(logIn: LogInState());
}
''');
    final r = source.wireSubstate(
      field: 'profile',
      type: 'ProfileState',
      importPath: 'profile/models/profile_state.dart',
    );

    expectParses(r.source);
    source.file.writeAsStringSync(r.source);
    expect(source.readSubstates().map((s) => s.field), ['logIn', 'profile']);
  });

  test('wire is idempotent for an already-composed field', () {
    final r = source.wireSubstate(
      field: 'logIn',
      type: 'LogInState',
      importPath: 'log_in/models/log_in_state.dart',
    );
    expect(r.alreadyWired, isTrue);
    expect(r.source, _appState);
  });

  test('unwire is the inverse of wire (field set returns to the original)', () {
    final wired = source.wireSubstate(
      field: 'profile',
      type: 'ProfileState',
      importPath: 'profile/models/profile_state.dart',
    );
    source.file.writeAsStringSync(wired.source);

    final unwired = source.unwireSubstate(
      field: 'profile',
      importPath: 'profile/models/profile_state.dart',
    );
    expect(unwired.found, isTrue);
    source.file.writeAsStringSync(unwired.source);

    expect(source.readSubstates().map((s) => s.field), [
      'connectivity',
      'logIn',
      'wait',
    ]);
    expect(unwired.source, isNot(contains('profile_state.dart')));
    expect(unwired.source, isNot(contains('ProfileState')));
  });

  test('unwire reports not-found for an absent field', () {
    final r = source.unwireSubstate(field: 'nope');
    expect(r.found, isFalse);
    expect(r.source, _appState);
  });
}
