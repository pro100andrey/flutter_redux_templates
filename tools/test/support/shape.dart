import 'package:test/test.dart';

/// The two states compared the way the rule states it: same fields, same
/// changes, `applied` flipped.
///
/// Not deep equality. Two of the `build` fields describe an **event** — whether
/// the build ran, and whether it was handed to a live watch — and a plan has had
/// no event, so it reports them as not-yet-happened rather than predicting them.
/// Start a watch and the applied result honestly says `handedToWatch: true` while
/// the plan honestly says `false`; asserting they match made the suite go red on a
/// machine that was set up correctly.
void expectSameShape(
  Map<String, Object?> planned,
  Map<String, Object?> applied,
) {
  expect(planned['applied'], isFalse);
  expect(applied['applied'], isTrue);
  expect(
    applied.keys,
    planned.keys,
    reason: 'the same fields, in the same order',
  );
  expect(applied['command'], planned['command']);
  expect(applied['changes'], planned['changes'], reason: 'the same changeset');

  final plannedBuild = planned['build'] as Map<String, Object?>?;
  final appliedBuild = applied['build'] as Map<String, Object?>?;
  expect(appliedBuild?.keys, plannedBuild?.keys);
  if (plannedBuild != null) {
    expect(appliedBuild!['package'], plannedBuild['package']);
    expect(appliedBuild['command'], plannedBuild['command']);
    // `ran`, `handedToWatch` and `watchPid` are the event, and deliberately not
    // compared — but they must all be *present* in both, which the key check
    // above enforces.
    expect(plannedBuild['ran'], isFalse, reason: 'a plan has run nothing');
    expect(plannedBuild['handedToWatch'], isFalse);
  }
}
