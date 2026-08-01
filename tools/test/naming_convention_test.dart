import 'package:test/test.dart';
import 'package:tools/src/model/naming_convention.dart';
import 'package:tools/src/model/page_artifact.dart';
import 'package:tools/src/model/substate_artifact.dart';
import 'package:tools/src/model/target_resolver.dart';
import 'package:tools/src/util/casing.dart';

/// Reading an artifact back out of a name — the inverse of what
/// [PageArtifact] and [SubstateArtifact] write.
///
/// Testable without a repo because the "does this exist" predicates are
/// passed in. Inside `which_command` this needed a TargetResolver, so it was
/// only ever reached through a subprocess test.
void main() {
  ResolvedName? resolve(
    String token, {
    Set<String> substates = const {},
    Set<String> pages = const {},
  }) => NamingConvention.resolve(
    token,
    isSubstate: (n) => substates.contains(n.snake),
    isPage: (n) => pages.contains(n.snake),
  );

  group('the inverse agrees with the forward direction', () {
    // The property that matters: whatever the artifacts *write*, this reads.
    // The two used to live in different tiers, so adding a suffix meant
    // finding two unrelated places.
    const names = ['log_in', 'home', 'forgot_password', 'a'];

    test('every name a PageArtifact generates resolves back to it', () {
      for (final raw in names) {
        final a = PageArtifact(Casing.parse(raw));
        for (final token in [a.routeType, a.connectorClass, a.pageClass]) {
          final got = resolve(token, pages: {raw});
          expect(got?.name, raw, reason: '$token → $raw');
          expect(got?.kind, ArtifactKind.page, reason: token);
        }
      }
    });

    test('every name a SubstateArtifact generates resolves back to it', () {
      for (final raw in names) {
        final a = SubstateArtifact(Casing.parse(raw));
        for (final token in [a.stateType, a.selectorType]) {
          final got = resolve(token, substates: {raw});
          expect(got?.name, raw, reason: '$token → $raw');
          expect(got?.kind, ArtifactKind.substate, reason: token);
        }
      }
    });
  });

  test('a connector is not mistaken for a page', () {
    // `LogInPageConnector` also ends in `Page`… no it does not, but it ends in
    // `Connector` and starts with the page name, and a shorter suffix tried
    // first would decompose it to `LogInPageConn`. Order is the guard.
    final got = resolve('LogInPageConnector', pages: {'log_in'});
    expect(got?.name, 'log_in');
    expect(got?.suffix, 'PageConnector');
  });

  test('the affix that identified the token is reported', () {
    // The editor uses it to know how much of a symbol to select on rename.
    expect(resolve('LogInRoute', pages: {'log_in'})?.suffix, 'Route');
    expect(resolve('SelectLogIn', substates: {'log_in'})?.prefix, 'Select');
    expect(resolve('LogInState', substates: {'log_in'})?.suffix, 'State');
  });

  test('a bare name resolves with no affix at all', () {
    expect(resolve('logIn', substates: {'log_in'})?.suffix, isNull);
    expect(resolve('log_in', substates: {'log_in'})?.name, 'log_in');
  });

  test('a token that matches nothing in the repo is unresolved', () {
    expect(resolve('LogInRoute'), isNull);
    expect(resolve('Whatever', pages: {'home'}), isNull);
  });

  test('a substate wins over a page when both could match a bare token', () {
    // Deliberate and load-bearing for `remove`/`rename`, which ask the user to
    // disambiguate with --kind rather than guessing differently per command.
    expect(
      resolve('home', substates: {'home'}, pages: {'home'})?.kind,
      ArtifactKind.substate,
    );
  });

  test('an unparseable base is skipped, not thrown', () {
    // `Route` alone leaves an empty base; Casing.parse refuses it, and the
    // next candidate (the bare token) has to still get a turn.
    expect(() => resolve('Route', pages: {'route'}), returnsNormally);
    expect(resolve('Route', pages: {'route'})?.name, 'route');
  });
}
