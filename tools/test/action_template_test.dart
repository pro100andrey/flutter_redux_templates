import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/scaffold/artifact_templates.dart';
import 'package:tools/src/util/casing.dart';

import 'support/package_source.dart';
import 'support/parses.dart';

String render(ActionKind kind, {List<String> mixins = const []}) =>
    ArtifactTemplates.action(
      Casing.parse('fetch_profile'),
      kind,
      mixins: ActionMixin.expand(mixins),
    );

void main() {
  _mixinCatalogueTests();
  test('every template emits Dart that parses', () {
    // The substring assertions below each check that one fragment is present.
    // None of them would notice a fused token or an unbalanced brace elsewhere
    // in the file — which is exactly how the AppState wire shipped broken.
    for (final kind in ActionKind.values) {
      for (final mixins in [
        <String>[],
        ['retry', 'unlimitedRetries'],
        ['checkInternet', 'noDialog'],
        ['nonReentrant'],
      ]) {
        expectParses(
          render(kind, mixins: mixins),
          reason: '${kind.name} + ${mixins.join(', ')}',
        );
      }
    }
    expectParses(
      ArtifactTemplates.fieldSetter(
        Casing.parse('log_in'),
        Casing.parse('nickname'),
        'String?',
      ),
    );
    expectParses(ArtifactTemplates.widget(Casing.parse('avatar_badge')));
    expectParses(ArtifactTemplates.connector(Casing.parse('avatar_badge')));
    expectParses(ArtifactTemplates.model(Casing.parse('user'), json: true));
    expectParses(
      ArtifactTemplates.modelUnion(Casing.parse('result'), [
        Casing.parse('ok'),
        Casing.parse('failed'),
      ], json: false),
    );
    expectParses(
      ArtifactTemplates.enumeration(Casing.parse('status'), [
        Casing.parse('idle'),
        Casing.parse('busy'),
      ]),
    );
    expectParses(ArtifactTemplates.service(Casing.parse('clock')));
    expectParses(ArtifactTemplates.serviceDispatcher(Casing.parse('clock')));
    expectParses(ArtifactTemplates.retrofit(Casing.parse('user_api')));
    expectParses(ArtifactTemplates.themeExtension(Casing.parse('spacing')));
  });

  group('the generated base class', () {
    test('is the app\'s own Action, for every kind', () {
      // Every hand-written action in the repo extends `Action` — it is what
      // carries deps/env/Selectors. Scaffolding a bare ReduxAction meant the
      // first edit to a generated file was changing its base class.
      for (final kind in ActionKind.values) {
        final out = render(kind);
        expect(out, contains('extends Action'), reason: kind.name);
        expect(
          out,
          isNot(contains('extends ReduxAction')),
          reason: '${kind.name} must not bypass the house base',
        );
        expect(out, contains("import '../../common/action.dart';"));
      }
    });

    test('imports async_redux only when a mixin needs it', () {
      expect(render(ActionKind.async), isNot(contains('async_redux')));
      expect(
        render(ActionKind.async, mixins: ['retry']),
        contains("import 'package:async_redux/async_redux.dart';"),
      );
    });
  });

  group('the with clause', () {
    test('omits the type argument — Dart infers it from the constraint', () {
      final out = render(ActionKind.async, mixins: ['checkInternet', 'retry']);
      expect(out, contains('with CheckInternet, Retry'));
      expect(out, isNot(contains('<AppState>,')));
      expect(out, isNot(contains('CheckInternet<AppState>')));
    });

    test('inserts an implied mixin before its dependent', () {
      final out = render(ActionKind.async, mixins: ['noDialog']);
      expect(out, contains('with CheckInternet, NoDialog'));
    });

    test('puts WaitingAction after a mixin that ends the after() chain', () {
      // The bug this pins: `add-action -k waiting -m nonReentrant` emitted
      //
      //     class ProbeAction extends Action with WaitingAction, NonReentrant
      //
      // and `NonReentrant.after()` does not call `super.after()`, so the
      // barrier `WaitingAction.after()` lowers was never lowered. Measured on
      // a real store: the action finished and `isWaitingForType<T>()` stayed
      // true for the rest of the session, which is a permanently disabled
      // button. Every existing test passed — the file parses, analyzes clean,
      // and only misbehaves at runtime.
      for (final m in ActionMixin.values.where((m) => m.swallowsAfter)) {
        expect(
          _withClause(render(ActionKind.waiting, mixins: [m.name])),
          endsWith('WaitingAction'),
          reason: '${m.name} ends the after() chain, so it cannot be last',
        );
      }
    });

    test('puts WaitingAction last even when nothing swallows after()', () {
      // Unconditional, so there is no branch to take wrongly — and so the one
      // combination that must not compile stays visible: `CheckInternet`
      // narrows `before()` to `Future<void>`, which is why `WaitingAction`
      // declares `Future<void>` rather than `void`.
      expect(
        _withClause(render(ActionKind.waiting, mixins: ['checkInternet'])),
        'CheckInternet, WaitingAction',
      );
      expect(_withClause(render(ActionKind.waiting)), 'WaitingAction');
    });
  });

  group('ActionMixin.conflictIn', () {
    test('rejects a pair async_redux declares mutually exclusive', () {
      // These collide on a private member, so `dart analyze` reports the
      // combination — frx used to scaffold it happily. The *compiler* accepts
      // it, which is measured in `business/test/mixin_exclusion_test.dart`;
      // what stops it there is an assert on first dispatch, in debug builds
      // only. Either way, refusing it here is the check that happens before
      // the file exists.
      for (final pair in [
        ['debounce', 'retry'],
        ['checkInternet', 'abortWhenNoInternet'],
        ['throttle', 'nonReentrant'],
        ['fresh', 'throttle'],
        ['unlimitedRetryCheckInternet', 'checkInternet'],
      ]) {
        final clash = ActionMixin.conflictIn(ActionMixin.expand(pair));
        expect(clash, isNotNull, reason: pair.join(' + '));
      }
    });

    test('accepts the combinations that do compose', () {
      for (final ok in [
        ['checkInternet', 'noDialog'],
        ['retry', 'unlimitedRetries'],
        ['checkInternet', 'noDialog', 'retry', 'unlimitedRetries'],
        ['nonReentrant'],
        <String>[],
      ]) {
        expect(
          ActionMixin.conflictIn(ActionMixin.expand(ok)),
          isNull,
          reason: ok.join(' + '),
        );
      }
    });

    test('the catalogue matches the mixins async_redux actually declares', () {
      // Derived, not transcribed. The test this replaces asserted a hardcoded
      // list in the test against the hardcoded list in the source and read
      // nothing from the package — so when async_redux 28 added five mixins,
      // the test whose comment said "guards against the list drifting behind
      // the package again" stayed green while the list drifted.
      //
      // `containsAll` was the other half of the problem: one-directional, so
      // additions to the package were invisible by construction. This is set
      // equality against what is on disk.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }

      // `on <Base>`, not `on ReduxAction`: frx's own `NoDialog` sits on
      // `CheckInternet` and `UnlimitedRetries` on `Retry`, and narrowing the
      // pattern would report both as inventions.
      final declared = <String>{};
      final pattern = RegExp(
        r'^mixin\s+([A-Za-z]\w*)(?:<[^>]*>)?\s+on\s+\w',
        multiLine: true,
      );
      for (final file in PackageSource.dartFiles(lib)) {
        for (final m in pattern.allMatches(file.readAsStringSync())) {
          declared.add(m.group(1)!);
        }
      }
      expect(declared, isNotEmpty, reason: 'the scan found no mixins at all');

      final offered = ActionMixin.values.map((m) => m.clause).toSet();
      expect(
        offered.difference(declared),
        isEmpty,
        reason: 'frx offers a mixin async_redux does not declare',
      );
      expect(
        declared.difference(offered).difference(_notScaffolded),
        isEmpty,
        reason:
            'async_redux declares a mixin frx neither offers nor has decided '
            'to leave out — add it to ActionMixin, or to _notScaffolded with '
            'the reason',
      );
    });

    test('implies is the `on` clause async_redux declares', () {
      // A third transcription. async_redux writes `mixin NoDialog on
      // CheckInternet`, and frx writes `noDialog(implies: checkInternet)` —
      // the same fact, by hand. Deriving it means a mixin that gains or loses
      // a base cannot leave frx emitting a `with` clause in the wrong order,
      // which is a compile error in the generated file.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }
      final bases = <String, String>{};
      final pattern = RegExp(
        r'^mixin\s+(\w+)(?:<[^>]*>)?\s+on\s+(\w+)',
        multiLine: true,
      );
      for (final file in PackageSource.dartFiles(lib)) {
        for (final m in pattern.allMatches(file.readAsStringSync())) {
          bases[m.group(1)!] = m.group(2)!;
        }
      }
      expect(bases, isNotEmpty, reason: 'found no mixin declarations');

      for (final m in ActionMixin.values) {
        final base = bases[m.clause];
        // `on ReduxAction` is the plain case and implies nothing.
        final expected = base == 'ReduxAction' ? null : base;
        expect(
          m.implies?.clause,
          expected,
          reason: '${m.name}: async_redux declares ${m.clause} on $base',
        );
      }
    });

    test('every knob a scaffold names is one async_redux declares', () {
      // The override blocks are strings, so a member renamed on the package
      // side would leave frx writing a `TODO` about a knob that no longer
      // exists — and a wrong name in a comment is still valid Dart, so
      // nothing downstream would notice. `knobs` makes those names data.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }
      final declared = <String>{};
      final member = RegExp(
        r'^\s+(?:int|bool|double|Duration|Object\??|void|String)\s+'
        r'(?:get\s+)?(\w+)',
        multiLine: true,
      );
      for (final file in PackageSource.dartFiles(lib)) {
        for (final m in member.allMatches(file.readAsStringSync())) {
          declared.add(m.group(1)!);
        }
      }
      expect(declared, isNotEmpty, reason: 'found no members at all');

      var checked = 0;
      for (final m in ActionMixin.values) {
        for (final knob in m.knobs) {
          checked++;
          expect(
            declared,
            contains(knob),
            reason: '${m.name} names a knob async_redux does not declare',
          );
          // And the block has to actually mention it, or `knobs` is a lie
          // that happens to typecheck.
          expect(
            m.overrideBlock,
            contains(knob),
            reason: '${m.name} lists $knob in knobs but never writes it',
          );
        }
      }
      expect(checked, greaterThan(6), reason: 'the scan found too few knobs');
    });

    test('a tuning override uses the unit async_redux measures it in', () {
      // The catalogue and the exclusion groups were derived; the *override
      // blocks* were not, and that was the blind spot. `fresh` emitted
      //
      //     int get freshFor => 60; // seconds
      //
      // while async_redux declares `int get freshFor => 1000; // Milliseconds`.
      // A scaffolded action stayed fresh for 60ms with a comment promising a
      // minute, so `Fresh` silently did nothing — and every test passed,
      // because a wrong number is still valid Dart.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }

      // `int get <knob> => <n>; // <Unit>` — the package labels its own units.
      final declared = <String, String>{};
      final pattern = RegExp(
        r'^\s*int get (\w+) => \d+;\s*//\s*(\w+)',
        multiLine: true,
      );
      for (final file in PackageSource.dartFiles(lib)) {
        for (final m in pattern.allMatches(file.readAsStringSync())) {
          declared[m.group(1)!] = m.group(2)!.toLowerCase();
        }
      }
      expect(declared, isNotEmpty, reason: 'found no unit-labelled knobs');

      var checked = 0;
      for (final m in ActionMixin.values) {
        final block = m.overrideBlock;
        for (final entry in declared.entries) {
          if (!block.contains('int get ${entry.key} =>')) continue;
          checked++;
          expect(
            block.toLowerCase(),
            contains(entry.value),
            reason:
                '${m.name} overrides ${entry.key}, which async_redux measures '
                'in ${entry.value} — the generated comment must say so',
          );
        }
      }
      expect(
        checked,
        greaterThan(0),
        reason: 'no override block matched a knob; the scan is broken',
      );
    });

    test('swallowsAfter matches which mixins actually end the chain', () {
      // The fourth fact frx transcribes from async_redux, and the one that was
      // missing while it mattered. `implies` says what must precede a mixin and
      // `exclusiveGroups` says which pairs the package rejects; neither says
      // which mixin silently eats another's cleanup — which is not a compile
      // error, not an assert, not an analyzer hint, and not visible in the
      // generated file.
      //
      // Derived for the reason the other three are: transcribed, it goes stale
      // the first time the package changes, and nothing fails.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }

      final slices = _mixinSources(lib);
      expect(slices, isNotEmpty, reason: 'the scan found no mixins at all');

      var swallowers = 0;
      for (final m in ActionMixin.values) {
        final slice = slices[m.clause];
        expect(
          slice,
          isNotNull,
          reason: '${m.clause} is not declared in async_redux',
        );
        // No `after()` at all keeps the same promise as one that chains: the
        // next mixin down is reached either way. Only an override that returns
        // without `super.after()` ends it.
        final body = _methodBody(slice!, 'after');
        final swallows = body != null && !body.contains('super.after()');
        if (swallows) swallowers++;

        // The other half of the same scan: which hooks it overrides at all.
        // `swallowsAfter` says whether putting it last breaks the chain; this
        // says whether there is a chain to break, which is what the audit needs
        // to judge an action that writes its own hook.
        expect(m.hooks, {
          for (final hook in const ['before', 'after'])
            if (_methodBody(slice, hook) != null) hook,
        }, reason: '${m.clause}: hooks must be what async_redux overrides');

        expect(
          m.swallowsAfter,
          swallows,
          reason: swallows
              ? '${m.clause}.after() does not call super.after(), so anything '
                    'mixed in before it never cleans up — mark it '
                    'swallowsAfter: true'
              : '${m.clause} chains (or does not override) after(), so '
                    'swallowsAfter must be false',
        );
      }
      expect(
        swallowers,
        greaterThan(0),
        reason: 'the scan found no swallowers at all; it is broken',
      );
    });

    test('the exclusion groups match the collisions async_redux encodes', () {
      // async_redux enforces exclusivity by private-member collision, and it
      // names the members after the group:
      //
      //   _cannot_combine_mixins_Fresh_Throttle_NonReentrant_UnlimitedRetryCheckInternet
      //
      // So the rule frx transcribes into `exclusiveGroups` is *readable* from
      // the package. Deriving it is the difference between "frx agrees with
      // itself" — which `conflictsWith agrees with conflictIn` already checks —
      // and "frx agrees with async_redux", which nothing checked.
      final lib = PackageSource.libOf('async_redux', repoRoot: _repoRoot());
      if (lib == null) {
        markTestSkipped('async_redux not resolved here — nothing to compare');
        return;
      }

      final marker = RegExp(r'_cannot_combine_mixins_([A-Za-z_]+)');
      final groups = <Set<String>>{};
      for (final file in PackageSource.dartFiles(lib)) {
        for (final m in marker.allMatches(file.readAsStringSync())) {
          groups.add(m.group(1)!.split('_').where((s) => s.isNotEmpty).toSet());
        }
      }
      expect(groups, isNotEmpty, reason: 'found no collision markers at all');

      /// Whether the package puts [a] and [b] in one group, following the
      /// implications: frx's `noDialog` is async_redux's `NoDialog`, which
      /// mixes in `CheckInternet` — and only `CheckInternet` is named in the
      /// marker.
      bool collideInPackage(ActionMixin a, ActionMixin b) {
        final left = ActionMixin.expand([a.name]).map((m) => m.clause).toSet();
        final right = ActionMixin.expand([b.name]).map((m) => m.clause).toSet();
        return groups.any(
          (g) => left.any(
            (l) => right.any((r) => l != r && g.contains(l) && g.contains(r)),
          ),
        );
      }

      for (final a in ActionMixin.values) {
        for (final b in ActionMixin.values) {
          if (a == b) continue;
          expect(
            a.conflictsWith.contains(b),
            collideInPackage(a, b),
            reason:
                '${a.name} + ${b.name}: frx says '
                '${a.conflictsWith.contains(b) ? '' : 'no '}conflict, '
                'async_redux says ${collideInPackage(a, b) ? '' : 'no '}conflict',
          );
        }
      }
    });
  });
}

/// Mixins async_redux declares that `add-action` deliberately does not offer.
///
/// Each needs more than a `with` clause to be useful — an abstract member to
/// implement, or a companion type — so scaffolding one would emit an action
/// that does not compile until the developer fills in the rest. `add-action`
/// offers the knobs you can turn by naming them alone.
const _notScaffolded = {
  // Each requires overriding members beyond the mixin itself (the optimistic
  // family needs `newValue`/`reloadValue`, `ServerPush`/`Polling` a stream or
  // an interval plus a payload type).
  'OptimisticCommand',
  'OptimisticSync',
  'OptimisticSyncWithPush',
  'ServerPush',
  'Polling',
};

/// The `with` clause of the single class [source] declares, without `with `.
String _withClause(String source) {
  final m = RegExp(
    r'class \w+ extends Action with ([^{]+?)\s*\{',
  ).firstMatch(source);
  expect(m, isNotNull, reason: 'no `extends Action with …` in:\n$source');
  return m!.group(1)!;
}

/// Every `mixin X on …` in [lib], mapped to its source from the declaration to
/// the next one (or the end of the file).
///
/// Slicing on the next declaration rather than brace-matching the body: a
/// mixin's own doc comment sits above it, so the slice picks up the following
/// mixin's doc comment and nothing else — harmless for a member scan, and it
/// cannot be thrown off by a brace inside a string literal.
Map<String, String> _mixinSources(Directory lib) {
  final slices = <String, String>{};
  final decl = RegExp(r'^mixin\s+(\w+)(?:<[^>]*>)?\s+on\s', multiLine: true);
  for (final file in PackageSource.dartFiles(lib)) {
    final source = file.readAsStringSync();
    final found = decl.allMatches(source).toList();
    for (var i = 0; i < found.length; i++) {
      final end = i + 1 < found.length ? found[i + 1].start : source.length;
      slices[found[i].group(1)!] = source.substring(found[i].start, end);
    }
  }
  return slices;
}

/// The body of `void <name>()` declared directly in [mixinSource], or null when
/// the mixin does not override it.
///
/// Anchored at two-space indentation, which is what keeps a `void after()` in
/// somebody's doc-comment example (`///   void after() {`) from being read as a
/// declaration.
String? _methodBody(String mixinSource, String name) {
  final decl = RegExp(
    '^  (?:Future<void>|void)\\s+$name\\(\\)\\s*(async\\s*)?(\\{|=>)',
    multiLine: true,
  ).firstMatch(mixinSource);
  if (decl == null) return null;

  // `=> expr;` — everything to the semicolon.
  if (decl.group(2) == '=>') {
    final end = mixinSource.indexOf(';', decl.end);
    return mixinSource.substring(decl.end, end == -1 ? null : end);
  }
  // `{ … }` — brace-matched from the opening brace.
  var depth = 0;
  for (var i = decl.end - 1; i < mixinSource.length; i++) {
    if (mixinSource[i] == '{') depth++;
    if (mixinSource[i] == '}' && --depth == 0) {
      return mixinSource.substring(decl.end, i);
    }
  }
  return mixinSource.substring(decl.end);
}

/// The monorepo root, where the Flutter packages are resolved.
///
/// The tests run from `tools/`, whose own `.dart_tool` has never heard of
/// async_redux — see [PackageSource].
Directory _repoRoot() => Directory.current;

void _mixinCatalogueTests() {
  group('mixin catalogue', () {
    test('conflictsWith agrees with the check add-action actually runs', () {
      // The picker filters by this set; the command refuses by conflictIn over
      // the expanded list. If the two ever disagree, the editor offers a
      // combination that then fails, or hides one that would have worked.
      for (final a in ActionMixin.values) {
        for (final b in ActionMixin.values) {
          if (a == b) continue;
          final refused =
              ActionMixin.conflictIn(ActionMixin.expand([a.name, b.name])) !=
              null;
          expect(
            a.conflictsWith.contains(b),
            refused,
            reason: '${a.name} + ${b.name}',
          );
        }
      }
    });

    test('an implied mixin carries its parent\'s exclusions', () {
      // `noDialog` shares no group with `abortWhenNoInternet` — the
      // `checkInternet` it implies does. A picker filtering on the literal
      // pick would offer the pair.
      expect(
        ActionMixin.noDialog.conflictsWith,
        contains(ActionMixin.abortWhenNoInternet),
      );
      expect(
        ActionMixin.unlimitedRetries.conflictsWith,
        contains(ActionMixin.debounce),
      );
    });

    test('exclusion is symmetric', () {
      for (final a in ActionMixin.values) {
        for (final b in a.conflictsWith) {
          expect(b.conflictsWith, contains(a), reason: '${a.name} ↔ ${b.name}');
        }
      }
    });

    test('every mixin describes itself, so no consumer has to', () {
      for (final m in ActionMixin.values) {
        expect(m.summary, isNotEmpty, reason: m.name);
      }
    });
  });
}
