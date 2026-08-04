import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';

/// The contract between the CLI and the VS Code extension, checked from the
/// side that owns it.
///
/// The extension is a front for `frx`, so it knows things the CLI also knows:
/// which commands exist, what each accepts. Nothing compared the two. The
/// extension's own `validate-manifest.ts` checks its `package.json` against its
/// own TypeScript and never reads the CLI at all — and its CI job has Node but
/// no Dart, so it cannot. This is the Dart side of that gate, where both the
/// command list and a Dart toolchain are already present.
///
/// It exists because the drift had already happened twice: `add-nav` shipped in
/// the CLI and the extension had never heard of it, and the mixin catalogue had
/// drifted to eight of the ten before it was read live.
void main() {
  final vscode = Directory(p.join(Directory.current.path, 'vscode'));
  if (!vscode.existsSync()) {
    test('the extension contract', () {
      markTestSkipped('no vscode/ beside the CLI');
    });
    return;
  }

  final commands = FrxRunner().commands.values
      .where((c) => !c.hidden)
      .map((c) => c.name)
      .toSet();

  late String source;
  setUpAll(() {
    source = [
      for (final f
          in vscode
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.ts') &&
                    !f.path.contains('node_modules') &&
                    !f.path.contains(p.join('vscode', 'out')) &&
                    !f.path.contains(p.join('vscode', 'test')),
              ))
        f.readAsStringSync(),
    ].join('\n');
  });

  test('every frx command the extension invokes exists', () {
    // The failure this catches is quiet in the other direction: the extension
    // spawns a command that does not exist, frx exits 64, and the user sees
    // "FRX failed (exit 64)" with no clue which name is wrong.
    final invoked = RegExp(
      r"'(add-[a-z-]+|list-[a-z-]+|remove|rename|doctor|graph|flow|which|new|watch)'",
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(invoked, isNotEmpty, reason: 'found no frx invocations to check');
    expect(
      invoked.difference(commands),
      isEmpty,
      reason: 'the extension invokes a command frx does not have',
    );
  });

  test('every frx command is either surfaced or deliberately not', () {
    // The one that catches `add-nav`. Not every command needs a button — but
    // the decision has to be written down, not left as an omission nobody can
    // tell from an oversight.
    final mentioned = {
      for (final c in commands)
        if (source.contains("'$c'")) c,
    };
    expect(
      commands.difference(mentioned).difference(_notInTheEditor),
      isEmpty,
      reason:
          'frx has a command the extension never mentions. Surface it, or add '
          'it to _notInTheEditor with the reason.',
    );
    expect(
      _notInTheEditor.difference(commands),
      isEmpty,
      reason: '_notInTheEditor names a command that no longer exists',
    );
  });

  test('every declared command is in both the palette and the overlay', () {
    // The mirror rule: one inventory, two renderings. It tightens the check
    // above rather than adding a new one — same question ("surfaced, or
    // deliberately not, with the reason written down"), asked of the editor's own
    // commands instead of the CLI's.
    //
    // It matters more than usual here, because the defect it fixes *was* drift
    // nobody noticed: the two surfaces had come apart in both directions, and
    // the manifest's shape hides that — in this editor, no palette entry means
    // "visible in every workspace", not "hidden".
    final manifest =
        jsonDecode(File(p.join(vscode.path, 'package.json')).readAsStringSync())
            as Map<String, Object?>;
    final contributes = manifest['contributes']! as Map<String, Object?>;
    final declared = {
      for (final c in (contributes['commands']! as List).cast<Map>())
        c['command'] as String,
    };
    final palette = {
      for (final e
          in ((contributes['menus']! as Map)['commandPalette']! as List)
              .cast<Map>())
        e['command'] as String: e['when'] as String,
    };
    final overlay = RegExp(r"command:\s*'(frx\.[A-Za-z]+)'")
        .allMatches(
          File(
            p.join(vscode.path, 'src', 'commands', 'menu.ts'),
          ).readAsStringSync(),
        )
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, isNotEmpty);

    for (final command in declared) {
      // A command with no palette entry is not hidden — it is visible in every
      // workspace, contradicting the documented claim that everything is gated
      // on real project markers.
      expect(
        palette,
        contains(command),
        reason:
            '$command has no commandPalette entry, so it appears in an '
            'unrelated workspace.',
      );
      if (_notInThePalette.containsKey(command)) {
        expect(
          palette[command],
          'false',
          reason: '$command is allowlisted out of the palette but not hidden',
        );
      } else {
        expect(
          palette[command],
          'frx.isMonorepo',
          reason:
              '$command is in the palette but not gated on the monorepo. '
              'Gate it, or add it to _notInThePalette with the reason.',
        );
      }
      if (!_notInTheOverlay.containsKey(command)) {
        expect(
          overlay,
          contains(command),
          reason:
              '$command is in the palette but not in the overlay. Add it to '
              'the inventory, or to _notInTheOverlay with the reason.',
        );
      }
    }

    // The other direction: an overlay row for a command that does not exist is a
    // dead entry, which is how the last drift started.
    expect(overlay.difference(declared), isEmpty);
    for (final absent in [..._notInThePalette.keys, ..._notInTheOverlay.keys]) {
      expect(
        declared,
        contains(absent),
        reason: 'the allowlist names $absent, which no longer exists',
      );
    }
  });

  test('the editor agrees with remove about what kinds exist', () {
    // `--kind` crosses the boundary as a bare string, so nothing else would
    // catch the extension offering a value the CLI stopped accepting — or, the
    // direction that actually happened, the CLI gaining five kinds while the
    // editor's union still said `'substate' | 'page'` and its disambiguation
    // picker still offered exactly those two.
    final allowed =
        (FrxRunner().commands['remove']!.argParser.options['kind']!.allowed ??
                const <String>[])
            .toSet();
    expect(allowed, isNotEmpty);

    final declared = RegExp(
      r'export const ARTIFACT_KINDS = \[([^\]]*)\]',
    ).firstMatch(File(p.join(vscode.path, 'src', 'ui.ts')).readAsStringSync());
    expect(
      declared,
      isNotNull,
      reason: 'ARTIFACT_KINDS is gone from ui.ts — the contract has no subject',
    );
    final kinds = RegExp(
      "'([a-z-]+)'",
    ).allMatches(declared!.group(1)!).map((m) => m.group(1)!).toSet();

    expect(
      allowed.difference(kinds),
      isEmpty,
      reason:
          'frx remove --kind accepts kind(s) the editor never offers. Add them '
          'to ARTIFACT_KINDS in src/ui.ts (and to KIND_BLURB beside it).',
    );
    expect(
      kinds.difference(allowed),
      isEmpty,
      reason:
          'the editor offers a --kind value frx remove would reject with '
          'exit 64.',
    );
  });

  test('the editor keeps no copy of the non-substate folder list', () {
    // There was one, and it was deliberate: the "New here" folder entry had a
    // right-clicked folder and no resolved workspace, so it could not consult
    // the CLI live. Removing that entry removed the copy's only justification —
    // so what used to be pinned as "these two agree" is now pinned as "there is
    // only one of them", which is the stronger property.
    expect(
      source,
      isNot(contains('NOT_SUBSTATE_DIRS')),
      reason:
          'the extension is keeping a second statement of '
          'FrxWorkspace.notSubstateDirs. Read it from the CLI instead.',
    );
  });
}

/// Editor commands deliberately absent from the palette, and why.
///
/// The rule's subject is capabilities of the *tooling* — things that change the
/// code or reveal something about it. A control that acts on the tooling's own UI
/// is not one.
const _notInThePalette = {
  // Refreshing a view acts on the view, the way a scrollbar does. It stays on
  // the tree's own title bar, where the thing it refreshes is.
  'frx.refreshTree': 'acts on the view, not on the code',
  // The three answers a shown plan takes. Each acts on one open document and is
  // meaningless without it: they live on that document's own toolbar, the way
  // `frx.refreshTree` lives on the tree's. Reaching them from the palette would
  // also break the rule the plan exists to keep — that nothing is applied
  // sight-unseen — since a palette is reachable from anywhere but the plan.
  'frx.planApply': 'answers the open plan, on the plan’s own toolbar',
  'frx.planDiscard': 'answers the open plan, on the plan’s own toolbar',
  'frx.planShow': 'reveals the open plan, from the status bar',
};

/// Editor commands deliberately absent from the overlay, and why.
const _notInTheOverlay = {
  'frx.refreshTree': 'acts on the view, not on the code',
  // It *is* the overlay. A row that reopened it would be a mirror facing itself.
  'frx.menu': 'it is the overlay',
  // The overlay lists work you can start. Answering a plan already in front of
  // you is the finish of work started elsewhere, not a way in.
  'frx.planApply': 'answers the open plan, on the plan’s own toolbar',
  'frx.planDiscard': 'answers the open plan, on the plan’s own toolbar',
  'frx.planShow': 'reveals the open plan, from the status bar',
};

/// CLI commands the extension deliberately does not surface, and why.
const _notInTheEditor = {
  // A stdin wizard. The editor offers each scaffolder by name instead, and a
  // QuickPick cannot drive a prompt loop over a pipe.
  'new',
  // It creates a *new* monorepo somewhere else. Every other command acts on the
  // project the editor has open; this one is what you run before there is one,
  // so a button inside an open monorepo would be offering to leave it.
  'create',
  // Shell completion installer — nothing for an editor to do with it.
  'completions',
  // The editor runs build_runner through its own watch control, which owns the
  // status bar item and the output channel.
  'watch',
  // Its input is a declaration file — reviewable, diffable, committable, and
  // written by whoever wants a feature's worth of artifacts wired at once. The
  // editor's equivalent is the guided flows, one artifact at a time; a button
  // that runs a file you have already got open in it adds nothing an editor is
  // for.
  'batch',
};
