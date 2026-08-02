import 'package:args/command_runner.dart';

import '../command_runner.dart';

/// Generates one agent skill per frx command, plus the router that sits over
/// them, into the repository's `.claude/skills/`.
///
/// **Why one per command.** A traced run measured the failure this replaces: an
/// agent read `frx --help`, then `README.md`'s full command map, then
/// `frx help` for eleven commands — all inside the first forty seconds — and
/// then, thirty minutes later, hand-wrote fifty-six selector getters and every
/// state field. Three documents carried the index and none of them fired at the
/// moment of writing. A skill's description is matched by the harness on every
/// step instead of being recalled, so the decision is made where it is taken.
///
/// **What is generated and what is authored.** Everything mechanical — the
/// invocation, the aliases, the flag list — comes off the `Command` objects
/// themselves, so it cannot drift from the CLI the way a hand-kept copy does
/// (this repository has already paid for that once, in the editor extension).
/// The one authored part is [_Situation.when]: the description is the trigger,
/// and it has to match how the task sounds in someone's head, not what the
/// command is called. "A value computed from state" finds `add-selector`;
/// "add-selector" only finds it if you already knew.
class SkillGen {
  /// path (relative to repo root) -> file content.
  static Map<String, String> generate() {
    final runner = FrxRunner();
    final out = <String, String>{};

    for (final cmd in runner.commands.values) {
      if (cmd.hidden) continue;
      final s = _situations[cmd.name];
      if (s == null) continue; // covered by the router instead
      out['.claude/skills/frx-${cmd.name}/SKILL.md'] = _skill(cmd, s);
    }
    out['.claude/skills/wiring-artifacts/SKILL.md'] = _router(runner);
    return out;
  }

  static String _skill(Command<int> cmd, _Situation s) {
    final alias = cmd.aliases.isEmpty ? '' : ' (alias `${cmd.aliases.first}`)';
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('name: frx-${cmd.name}')
      ..writeln('description: >-')
      // The description is the trigger, so it carries the situation and the
      // command name and stops there. Splicing the CLI's own one-liner in as a
      // clause reads as a conjugation bug ("which add a field…") because those
      // are imperative, and the body repeats it verbatim two lines down.
      ..writeln(
        _wrap(
          '${s.when} ${_writes.contains(cmd.name) ? 'Wired by' : 'Answered by'} '
              '`frx ${cmd.name}`$alias.',
          '  ',
        ),
      )
      ..writeln('---')
      ..writeln()
      ..writeln('# `frx ${cmd.name}`')
      ..writeln()
      ..writeln(cmd.description)
      ..writeln()
      ..writeln('```')
      ..writeln(cmd.invocation)
      ..writeln('```')
      ..writeln();

    if (s.traps.isNotEmpty) {
      b.writeln('## Before you run it');
      b.writeln();
      for (final t in s.traps) {
        b.writeln('- ${_wrap(t, '  ').trimLeft()}');
      }
      b.writeln();
    }

    b
      ..writeln('## Flags')
      ..writeln()
      ..writeln('```')
      ..writeln(cmd.argParser.usage.trimRight())
      ..writeln('```')
      ..writeln()
      ..writeln(_shared)
      ..writeln()
      ..writeln(_gates);
    return b.toString();
  }

  static String _router(CommandRunner<int> runner) {
    final rows = <String>[];
    for (final e in _routes) {
      rows.add('| ${e.$1} | `frx ${e.$2}` |');
    }
    return '''
---
name: wiring-artifacts
description: >-
  Router for this Flutter AsyncRedux + auto_route monorepo — picks which `frx`
  command wires the artifact you are about to write, and carries the rules that
  belong to no single command. Use when several artifacts are needed at once,
  when it is unclear which command owns a change, right after hand-editing files
  of this architecture, or when deleting anything that is not a substate or a
  page.
---

# Which command wires what

Every row has its own skill (`frx-<command>`), which carries that command's
flags and its traps. This table is the map; reach for the row's skill when you
act on it.

| You are about to write… | Use |
| --- | --- |
${rows.join('\n')}

Names take any casing — `myProfile`, `my_profile`, `MyProfile` and `my-profile`
all resolve to the same artifact.

## More than one artifact at once

`frx batch` takes the intents as data and wires them in **one** transaction, in
the order written. A shell loop over the same commands is the usual substitute
and is not the same thing: it has no rollback boundary, so a failure at the
fifth intent leaves the first four wired and the state half-built. Batch covers
the creation commands only — `rename` and `remove` are refused with the reason.

## The rules that belong to no single command

- **A write applies completely or not at all.** A failed write is
  indistinguishable from a write never attempted, so a zero exit means the whole
  changeset landed and you never have to parse anything to find out. Exit `64` is
  a usage error, `70` is "cannot do this here". What sits outside the
  transaction: `dart format`, the `docs/flows` refresh and `build_runner` run
  after it and roll nothing back.
- **After editing files by hand, run the audit, then the type analyzer.** The
  audit knows this architecture and the analyzer knows Dart; neither substitutes
  for the other. The way this one is lost is not skipping it but spacing it — run
  it once before starting and once when done and the whole middle went
  unmeasured, every finding surfacing where any of a hundred edits could have
  caused it.
- **The graph is a gate you close as you go.** The audit and the analyzer both
  pass on code nothing reaches: a selector no reader calls, an action no widget
  dispatches. The moment is precise — the feature compiles, and you have not
  started the next one.
- **Deleting anything that is not a substate or a page is manual.** `frx remove`
  knows those two. A widget, a connector, a service, a model, an enum, a theme
  extension comes out with `rm`, and nothing unwires it: what still imports it is
  yours to find, and a widget leaves its mirrored preview behind. So `rm` and
  then the audit, in the same breath.
- **Around a live `build_runner watch`, commands stand down.** They hand the
  build over rather than starting a second one. The fact is reported in the
  command's own result (`--json` carries it as `build.handedToWatch`), not by the
  audit — read it there, at the moment you act. An *orphaned* watch is the
  converse: it regenerates nothing, and the audit reports it.
- **A private `StatefulWidget` is a widget that never became an artifact.** In
  `ui` a private class is a stateless fragment of the widget above it, or that
  widget's `State`. A component with its own lifecycle earns a file in a family
  folder, which is what gives it a preview and a name anything else can reach.
- **A value and the callback that changes it travel as one view-model.**
  `FieldVm` (or `ChoiceVm`, when the value is picked from a finite set) carries
  the value, its `onChanged`, an optional validator and a server-side error
  together. Split into two fields they are fresh closures every build, so the
  view-model rebuilds the connector on every dispatch.
- **Actions read through the selector facade.** A reducer reaching into
  `state.<slice>.<field>` states the shape of the state twice, and the graph
  cannot see the read, so the selector looks dead and the coupling looks absent.

## Project defaults

A `.frxrc` at the repo root sets the house style once — `buildRunner`, `format`,
`substateKind`, and a `placement` block that silences an audit rule by id. An
explicit flag always wins.

## Orientation

- [`README.md`](../../../README.md) — the architecture and the full command map.
- `frx --help` — the authority, and it always travels with the CLI.
- `docs/flows/` is **generated** from the sources. Regenerate it, never hand-edit
  it; the audit reports it as drift when it falls behind.
''';
  }

  /// Fold to ~76 columns so the frontmatter stays readable in a diff.
  static String _wrap(String text, String indent) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var line = indent;
    for (final w in words) {
      if (line.length + w.length + 1 > 76 && line.trim().isNotEmpty) {
        lines.add(line.trimRight());
        line = indent;
      }
      line += '$w ';
    }
    if (line.trim().isNotEmpty) lines.add(line.trimRight());
    return lines.join('\n');
  }

  static const _shared = '''
Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.''';

  static const _gates = '''
## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.''';

  static const _writes = {
    'add-substate',
    'add-page',
    'add-tabs',
    'add-action',
    'add-field',
    'add-selector',
    'add-widget',
    'add-connector',
    'add-nav',
    'add-model',
    'add-enum',
    'add-service',
    'add-retrofit',
    'add-theme-extension',
    'batch',
    'remove',
    'rename',
  };

  /// The router's table, in the order a feature is usually built.
  static const _routes = <(String, String)>[
    ('a slice of application state', 'add-substate'),
    ('a field on a slice that already exists', 'add-field'),
    ('a value computed from state', 'add-selector'),
    ('something that changes state', 'add-action'),
    ('a screen and its route', 'add-page'),
    ('a tabbed shell over several screens', 'add-tabs'),
    ('getting from one screen to another', 'add-nav'),
    ('a reusable piece of UI', 'add-widget'),
    ('a store connection for a dumb widget', 'add-connector'),
    ('a data shape', 'add-model'),
    ('a fixed set of values', 'add-enum'),
    ('a service and its dispatcher', 'add-service'),
    ('an HTTP API client', 'add-retrofit'),
    ('theme values', 'add-theme-extension'),
    ('several of the above at once', 'batch'),
    ('a rename of a substate or page', 'rename'),
    ('a deletion of a substate or page', 'remove'),
    ('an audit of the project', 'doctor'),
    ('what reaches what, and what nothing reaches', 'graph'),
    ('what happens when the user taps', 'flow'),
    ('what artifact an identifier belongs to', 'which'),
    ('an inventory of state slices', 'list-substates'),
    ('an inventory of routes', 'list-routes'),
    ('where widgets live', 'list-widget-dirs'),
    ('which action mixins conflict', 'list-mixins'),
    ('codegen running continuously', 'watch'),
  ];
}

class _Situation {
  const _Situation(this.when, {this.traps = const []});

  /// The trigger. Written the way the task sounds before the command is known.
  final String when;
  final List<String> traps;
}

/// Authored: how each job sounds in the moment, plus what its help omits.
/// `create`, `new` and `completions` are deliberately absent — they are not
/// reached for mid-task, and the router names them.
const _situations = <String, _Situation>{
  'add-substate': _Situation(
    'A new slice of application state — a list or table of things, a search, '
    'or a single value the app holds onto.',
    traps: [
      'The kind decides the shape: `table` for a keyed collection with an '
          'ordering, `search` for a query with results, `value` for one value. '
          'Ask which before scaffolding — changing it later is a rewrite.',
      'It wires the `AppState` field *and* its `initial()` entry, the selectors '
          'facade and the change log. What dispatches its starter actions is '
          'yours.',
    ],
  ),
  'add-field': _Situation(
    'A piece of data a state slice does not hold yet — the slice already '
    'exists and needs one more field on it. Also the shape of a slice you '
    'just created: each field is one of these, not a file you open and type.',
    traps: [
      'The field is spliced into the `@freezed` factory via AST. A '
          'non-nullable type **requires** `--default`, because a state is '
          'constructed with no arguments.',
      'It also writes the `Select…` getter, unless `--no-selector`. A field a '
          'connector cannot read is half-wired — which is why hand-writing the '
          'field means hand-writing the facade too, and usually forgetting it.',
      '`IList` / `IMap` / `ISet` types auto-import '
          '`fast_immutable_collections`. `--action` scaffolds the '
          '`Set<Field>Action` setter and never clobbers an existing one.',
    ],
  ),
  'add-selector': _Situation(
    'A value computed from state rather than stored in it — a count, a '
    'filtered list, a derived flag; anything a screen reads that the state '
    'does not hold directly.',
    traps: [
      '`--expr` is the getter body and defaults to reading the state field of '
          'the same name; `--type` tightens the return type from `Object?`. No '
          'codegen — selectors are hand code.',
      'A selector nothing reads is reported by the graph as a fact, not a '
          'defect: in a template it can be API for whoever builds on it.',
    ],
  ),
  'add-action': _Situation(
    'Something that changes state — a reducer, a mutation, an async operation '
    'a screen dispatches.',
    traps: [
      'Mixins conflict, and the conflict is a **compile error**: async_redux '
          'makes groups mutually exclusive by colliding on a private member. '
          'Ask `frx list-mixins` which exclude which and let the scaffolder '
          'write the `with` clause — it refuses a bad pair up front.',
      '`-k waiting` also adds the substate\'s `isWaiting` getter, on the same '
          'ground as a field\'s getter: a waiting action a page cannot ask '
          'about is half-wired.',
    ],
  ),
  'add-page': _Situation(
    'A new screen and the route that reaches it.',
    traps: [
      'It wires the page, its `@RoutePage()` connector, the `AutoRoute` entry '
          'and auth-area membership (`--public`). Navigation **to** it is a '
          'separate decision — that is `add-nav`.',
      '`--param name:type` becomes both a `/:name` path segment and a '
          'constructor field.',
    ],
  ),
  'add-tabs': _Situation(
    'A tabbed shell — several screens living under one tab bar, as a nested '
    'route.',
  ),
  'add-nav': _Situation(
    'Getting from one screen to another — a tap that opens another page.',
    traps: [
      'Five edits across two packages, four of which alone leave code that '
          'does not compile. `--kind` picks the `GoAction` factory: `push`, '
          '`replace` or `navigate`.',
    ],
  ),
  'add-widget': _Situation(
    'A reusable piece of UI in the `ui` package — an input, a button, a tile, '
    'a container.',
    traps: [
      '`--dir` is required and open-ended: a name that does not exist creates '
          'the folder. Ask `frx list-widget-dirs` which already hold widgets '
          'instead of inventing a home.',
      'Previews are scaffolded alongside into a mirrored tree, so a widget '
          'moved or deleted by hand leaves its preview behind.',
      '`-k` picks what it takes in: `field` takes a `FieldVm`, `choice` a '
          '`ChoiceVm`, `action` is a labelled button, `view` draws a render '
          'model, `container` wraps children.',
    ],
  ),
  'add-connector': _Situation(
    'Connecting a dumb widget to the store — the `StoreConnector` that builds '
    'its view-model.',
  ),
  'add-model': _Situation(
    'A data shape the app passes around — a freezed model, or a sealed union '
    'when the value is one of several cases.',
    traps: [
      '`-c <case>` twice or more makes it a sealed union with one factory per '
          'case. Three answers as three cases beat a nullable field with a '
          'flag beside it.',
    ],
  ),
  'add-enum': _Situation(
    'A fixed set of values — a status, a priority, a mode.',
  ),
  'add-service': _Situation(
    'A service and the Redux dispatcher that lets it reach the store.',
  ),
  'add-retrofit': _Situation(
    'An HTTP API client — endpoints against a base URL.',
  ),
  'add-theme-extension': _Situation(
    'Theme values the design needs — colours, sizes, spacing read off the '
    'theme.',
  ),
  'batch': _Situation(
    'Several artifacts at once — a whole feature\'s worth of state, screens '
    'and actions, wired together.',
    traps: [
      'One rollback boundary where eight invocations are eight boundaries: a '
          'failure at the fifth intent leaves nothing of the first four.',
      'Intents apply **in the order written** and fail loudly — `add-action` '
          'refuses a substate that is not there — so a prerequisite comes '
          'first. Nothing is reordered for you, on purpose.',
      'Creation commands only. `rename` and `remove` are refused, and an '
          'intent carrying `--dry-run`, `--json`, `--build-runner` or '
          '`--format` is refused too: those decide whether the batch writes.',
    ],
  ),
  'remove': _Situation(
    'Deleting a state slice or a screen, with everything that points at it.',
    traps: [
      'Previews by default; `--apply` is what touches disk.',
      'It knows a substate and a page. Everything else — a widget, a service, '
          'a model, an enum — is `rm` plus the audit.',
    ],
  ),
  'rename': _Situation(
    'Renaming a state slice or a screen — files, classes and every wiring '
    'reference.',
    traps: [
      'Previews by default; `--apply` is what touches disk. Identifiers move '
          'off the parse tree, so a name inside a persistence key survives '
          'untouched.',
    ],
  ),
  'doctor': _Situation(
    'Checking the project is still consistent — after hand edits, after a '
    'deletion, or before calling something done.',
    traps: [
      'It finds wiring drift, ungenerated code and misplaced declarations — '
          'what the Dart analyzer cannot know. Run both.',
      '`--fix` repairs what is safe to repair: runs codegen, removes an orphan '
          'substate folder that holds nothing. Placement findings never '
          'auto-fix — a deliberately placed file is the false positive being '
          'accepted.',
    ],
  ),
  'graph': _Situation(
    'What reaches what — who can change this slice, what breaks if it is '
    'touched, and which selectors or actions nothing reaches at all.',
    traps: [
      '`--focus` takes a node id, a symbol or a bare name; `-d inbound` '
          'answers "what breaks if I touch this" and is unbounded by default.',
      'The `unresolved` section matters as much as the edges: a missing edge '
          'and a relation that does not exist look identical, so the gaps are '
          'named rather than dropped.',
    ],
  ),
  'flow': _Situation(
    'What actually happens when the user taps something, how the screens '
    'connect, or refreshing the generated flow docs.',
    traps: [
      '`--md` writes `docs/flows/`; `--check` verifies it is current and exits '
          '1 when not. Never hand-edit that folder.',
    ],
  ),
  'which': _Situation(
    'What artifact a class, route or field belongs to — and the canonical name '
    'to hand `rename`.',
  ),
  'list-substates': _Situation(
    'What state slices exist and are composed into `AppState`.',
  ),
  'list-routes': _Situation('What routes the router registers.'),
  'list-widget-dirs': _Situation(
    'Where widgets already live, before inventing a folder for a new one.',
  ),
  'list-mixins': _Situation(
    'Which action mixins imply what, and which exclude which — before passing '
    'a second `--mixin`.',
  ),
  'watch': _Situation(
    'Running codegen continuously while working, instead of after each write.',
  ),
};
