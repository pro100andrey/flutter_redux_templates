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
    out['.claude/skills/wiring-artifacts/SKILL.md'] = _router();
    out['.claude/skills/asyncredux-in-this-template/SKILL.md'] = _asyncRedux;
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
      // The prohibition stays. Anthropic's guide recommends negative triggers
      // in a description, and the 650-trial comparison has imperative-plus-
      // prohibition activating 98.6% against 62.6% for the imperative alone.
      // The opposite rule — prompt the positive — governs the body, not this.
      ..writeln(
        _wrap(
          '${s.when} ${_writes.contains(cmd.name) ? 'Wired by' : 'Answered by'} '
              '`frx ${cmd.name}`$alias.'
              '${_writes.contains(cmd.name) ? ' Do NOT hand-write this artifact '
                        'or edit the files it wires — run the command.' : ''}',
          '  ',
        ),
      );

    if (s.paths.isNotEmpty) {
      b.writeln('paths:');
      for (final p in s.paths) {
        b.writeln('  - "$p"');
      }
    }

    b
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

    // Context first: what the thing is comes before what to watch out for.
    if (s.context != null) {
      b.writeln(s.context!.trim());
      b.writeln();
    }

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

  static String _router() {
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

# Wiring artifacts of this architecture

Every artifact this architecture has is created and wired by one `frx` command,
and each command carries its own skill — how the artifact is written here, and
what its help does not say. Those skills reach you on their own: they fire on
the situation, and the file-editing ones fire again on the file. Reading them
ahead of time is not how they work and not how they are counted.

`frx --help` lists the commands. This file carries what belongs to no single one.

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
- **`ui` is data-driven and knows no domain.** It depends on neither `models` nor
  `business`; a widget draws what it is handed. The connector is the seam where a
  domain value becomes a primitive, a formatted string or a `ui`-local render
  model. See `frx-add-widget` and `frx-add-connector`.

## Writing the body, not just the file

A command scaffolds the file and its wiring. How the body is written afterwards
is this architecture's own, and in several places it is the opposite of what
async_redux's documentation shows — `@freezed` rather than a hand-written
`copy()`, an `extension type` facade rather than memoised selector functions,
`extends Action` rather than `extends ReduxAction`.

Read **`asyncredux-in-this-template`** before filling in a reducer, a connector
or a state class, and whenever recalled async_redux knowledge is about to be
applied here. Each command's own skill carries the rules for its artifact.

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
}

class _Situation {
  const _Situation(
    this.when, {
    this.context,
    this.paths = const [],
    this.traps = const [],
  });

  /// The trigger. Written the way the task sounds before the command is known.
  final String when;

  /// Globs that make the skill load when those files are being worked on.
  ///
  /// The measured failure this targets: an agent read five state files and
  /// rewrote them wholesale ten minutes after reading the skill that says not
  /// to. A description cannot fix that, because the standard says an agent
  /// "only consult[s] skills for tasks that require knowledge or capabilities
  /// beyond what they can handle alone" — and writing a Dart file looks like
  /// one it can. `paths` fires on the file instead of on the intent.
  ///
  /// Only for commands that edit an artifact that already exists. A creation
  /// command has no file to match yet, and a glob would narrow it to nothing.
  final List<String> paths;

  /// What the artifact *is*, in this template's terms, with code from it.
  ///
  /// The command help says what the command writes; it cannot say how the body
  /// is written afterwards, and that is where an agent falls back on recalled
  /// async_redux knowledge — which is right about the library and wrong here in
  /// five places (freezed rather than a hand-written `copy()`, an `extension
  /// type` facade rather than memoised selector functions, `extends Action`
  /// rather than `extends ReduxAction`, `IList` rather than `List`, private
  /// `_Factory`/`_Vm` in the connector file). Raw markdown, so it can carry the
  /// fenced code that makes the shape unambiguous.
  final String? context;

  final List<String> traps;
}

/// Authored: how each job sounds in the moment, plus what its help omits.
/// `create`, `new` and `completions` are deliberately absent — they are not
/// reached for mid-task, and the router names them.
/// The async_redux context that belongs to no single command.
///
/// Not a copy of the library's documentation. What an agent already knows about
/// async_redux is mostly right and, in five places, exactly wrong here — so this
/// states the divergence and stops. Anything a command owns lives in that
/// command's skill instead.
const _asyncRedux = r'''
---
name: asyncredux-in-this-template
description: >-
  How async_redux is actually used in this monorepo, where it diverges from the
  library's own documentation, and the pieces no `frx` command owns —
  dispatching, waiting, user-facing errors, persistence and injected
  dependencies. Use before writing the body of a reducer, a connector or a state
  class, and whenever recalled async_redux knowledge is about to be applied
  here.
---

# async_redux, as this template uses it

## Five places the library's docs point the wrong way

| Stock async_redux | Here |
| --- | --- |
| an immutable class with its own `copy()` | `@freezed`, and `state.copyWith.<slice>(…)` for a nested write |
| `extends ReduxAction<AppState>` | `extends Action` — it mixes in `Selectors` and types `deps` and `env` |
| selector functions memoised with `cache1` / `cache2` | a facade of `extension type`s over `AppState`, zero-cost, nothing to memoise |
| `VmFactory` / `Vm` written however | `_Factory` / `_Vm`, private, in the connector file, `with Selectors` |
| `List` / `Map` in state | `IList` / `IMap` / `ISet` |

Everything below is the part no command scaffolds.

## Dispatching

- `dispatchSync` — a synchronous reducer. Setters from a connector use this.
- `dispatchAndWait` — returns the `ActionStatus`; await it when the next step
  depends on whether the action succeeded.
- `dispatch` — fire and forget, including `GoAction` for navigation.

Navigation is itself an action (`GoAction.push` / `replace` / `navigate` / `pop`
/ `popUntilRoot`), so it is observable and testable like any other, and
connectors never poke the router.

## Waiting

`Wait` is a field on `AppState`, owned by async_redux. An action opts in with the
`WaitingAction` mixin, which raises the barrier in `before()` and clears it in
`after()`. The reader is a selector keyed on the action type:

```dart
bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();
```

`frx add-action -k waiting` writes both. Never reduce `wait` yourself.

## Errors the user should see

Throw `UserException` from a reducer and async_redux shows it. `store.dart`
installs a `GlobalErrorObserver` that logs, wraps anything else into a
`UserException`, and gives the app a first chance to translate through a
`UserErrorWrapperHandler` returning a `LocalizedMessage` (title + message) — so a
message can be localised without `business` depending on the app's locale.

## Persistence

`AppPersistor` (`business/lib/persistor.dart`) is a `Persistor<AppState>` over
`KeyValueStorage` from `storage`. Boot goes through `createStore`: open storage,
read the persisted state, fall back to `AppState.initial()`. The app layer never
touches the storage backend. A persistor rebuilds state without dispatching,
which is why `frx graph` gives it a node of its own.

## Injected dependencies and environment

`AppDependencies` is built once by the store and reaches a reducer as `deps` on
the `Action` base; `Environment` (base URL, prod/dev) reaches it as `env`. Both
are already typed there — reading `store.dependencies` and casting is the long
way round.

## What this template does not use

Undo/redo, stream and timer actions, the provider integration, flutter_hooks,
events, `abortDispatch`, the optimistic-update mixin, and async_redux's testing
helpers — the template ships no test harness at all. If a task genuinely needs
one of these it is new ground here, not an established pattern: say so rather
than adopting it silently.
''';

/// Shared by `add-page` and `add-connector`: both scaffold the same three
/// classes, so the shape is stated once rather than twice.
const _connectorContext = r'''
## What a connector is here

Three classes in one file under `app/lib/connectors/`, two of them private. The
public one carries `@RoutePage()` and does nothing but wire the other two:

```dart
@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LogInPage(email: vm.email, theme: vm.theme),
  );
}
```

The factory reads the store. `with Selectors` is what lets it say `login.email`
instead of reaching into the state, and it is where a dispatch is bound to a
callback:

```dart
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    email: FieldVm(
      value: login.email,
      validator: emailValidator,
      onChanged: (v) => dispatchSync(SetEmailAction(v)),
    ),
    onPressedLogIn: () => dispatchAndWait(LogInWithEmailAction()),
    onPressedRegister: () => dispatch(GoAction.push(const RegistrationRoute())),
  );
}
```

The view-model holds what the dumb widget needs, and `equals:` names **only the
fields that carry data**:

```dart
class _Vm extends Vm {
  _Vm({required this.email, required this.onPressedLogIn})
    : super(equals: [email]);

  final FieldVm<String?> email;
  final VoidCallback onPressedLogIn;
}
```

A callback is a fresh closure every build, so listing one in `equals:` makes the
view-model unequal to itself and the connector rebuilds on every dispatch. That
is why a value and the callback that changes it travel together as `FieldVm`
(or `ChoiceVm`, when the value comes from a finite set): its `props` deliberately
omit the closures, so the value can be compared and the behaviour cannot break
the comparison.

**Which dispatch:** `dispatchSync` for a synchronous setter, `dispatchAndWait`
when the next step depends on the result, `dispatch(GoAction.push(...))` for
navigation. Connectors never touch the router directly.

This file is also the seam between the domain and the screen: `ui` depends on
neither `models` nor `business`, so an enum, a `DateTime` or a domain object
becomes a primitive, a formatted string or a `ui`-local render model **here**,
before it is handed over.
''';

const _situations = <String, _Situation>{
  'add-substate': _Situation(
    'A new slice of application state — a list or table of things, a search, '
    'or a single value the app holds onto.',
    context: r'''
## What a state slice is here

The store holds one immutable `AppState`. It is never edited — a reducer returns
a new one. `AppState` is a `@freezed` class composing the slices, and every slice
has an entry in `initial()`:

```dart
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required LoginState login,
    required ThemeState theme,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    login: LoginState(),
    theme: ThemeState(),
    wait: Wait.empty,
  );
}
```

`wait` is async_redux's own barrier registry, not a slice of this app. Leave it
alone — actions raise and clear it through the `WaitingAction` mixin.

A slice is a `@freezed` class of its own, at
`business/lib/redux/<slice>/models/<slice>_state.dart`. Every field is nullable
or carries `@Default(…)`, because the state is constructed with no arguments,
and collections are `IList` / `IMap` / `ISet` — value equality is what stops a
connector rebuilding on an identical list.

**`--kind` picks the shape**, and changing it later is a rewrite:

- `value` — one `String? value`, plus `SetValueAction`
- `search` — a `String? query` and an `IList<int> view` of results, plus
  `SetQueryAction`
- `table` — an `IMap<int, Object> table` and an `IList<int> view` over it, plus
  `Add…Action` / `Retrieve…Action`

```dart
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({
    @Default(IMapConst<int, Object>({})) IMap<int, Object> table,
    @Default(IListConst<int>([])) IList<int> view,
  }) = _TodosState;
}
```

The slice is never read directly. The command writes its getters into the
selector facade, so a screen says `todos.view` and so does a reducer —
`_state.todos.view` appears only inside the facade itself.
''',
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
    paths: ['business/lib/redux/*/models/*_state.dart'],
    context: r'''
## What a field is here

A field belongs to a slice's `@freezed` class. Adding one is three coordinated
edits, and the command makes all three.

**1. The factory**, spliced in via AST. A field is either nullable or carries
`@Default(…)`, because the state is constructed with no arguments:

```dart
const factory TodosState({
  @Default(IMapConst<int, Object>({})) IMap<int, Object> table,
  @Default(IListConst<int>([])) IList<int> view,
  DateTime? dueAt,
}) = _TodosState;
```

A collection field is `IList` / `IMap` / `ISet`, and the import comes with it.
`List` / `Map` compare by identity, so a connector would rebuild on an identical
list.

**2. The getter on the facade**, so anything can read the field without knowing
where it sits:

```dart
/// Returns dueAt
DateTime? get dueAt => _state.todos.dueAt;
```

`--no-selector` skips it. Rarely what you want: a field a connector cannot read
is half-wired, and it is this getter that makes the read visible to `frx graph`.

**3. A setter action**, with `--action` — positional constructor, `final` field,
and freezed's nested `copyWith`:

```dart
class SetDueAtAction extends Action {
  SetDueAtAction(this.dueAt);

  final DateTime? dueAt;

  @override
  AppState reduce() => state.copyWith.todos(dueAt: dueAt);
}
```

That `state.copyWith.<slice>(<field>: …)` form is how every write to a slice is
spelled — not `state.copyWith(todos: state.todos.copyWith(…))`.
''',
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
    paths: ['business/lib/redux/selectors.dart'],
    context: r'''
## What a selector is here

Not a function, and nothing to memoise. async_redux's own documentation teaches
selector functions cached with `cache1` / `cache2`; this template has none of
that. A selector is a getter on an `extension type` over `AppState`, so reading
one is a field access, and all of them live in a single file,
`business/lib/redux/selectors.dart`:

```dart
extension type SelectLogin(AppState _state) implements Selector {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();

  /// Returns email value
  String? get email => _state.login.email;
}
```

Three things reach those getters, and none of them names the state directly:

- a screen, through `state.select.login.email`
- a reducer, because `Action` mixes in `Selectors` — `login.email`
- a connector's `_Factory`, for the same reason

A value that spans slices belongs to `SelectComposites`, the
`extension … on Select` — not inside one of the slices:

```dart
extension SelectComposites on Select {
  bool get canEnterApp => session.isAvailable && !login.isWaiting;
}
```

Within a slice you can still reach another one: every `SelectX` implements
`Selector`, which is what lets that line say `session` and `login` at once.

`doctor` reports a selector declared anywhere but the facade
(`selector-outside-facade`), so the file is the convention, not a habit.
''',
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
    paths: ['business/lib/redux/*/actions/*.dart'],
    context: r'''
## What an action is here

An action is a class with a `reduce()` method. You dispatch it; the store calls
`reduce()` and replaces the state with what it returns. Returning `null` means
"no state change" — the action still ran, and observers still see it.

Actions extend **`Action`**, not `ReduxAction<AppState>`. The base lives in
`business/lib/redux/common/action.dart` and is what gives a reducer its three
tools:

```dart
abstract class Action extends ReduxAction<AppState> with Selectors {
  AppDependencies get deps => store.dependencies! as AppDependencies;
  Environment get env => store.environment! as Environment;
}
```

- `Selectors` — the selector facade, so state is read as `login.email`
- `deps` — injected services
- `env` — base URL, prod/dev

**Synchronous.** Parameters arrive through the constructor as `final` fields;
the write is freezed's nested `copyWith`:

```dart
class SetEmailAction extends Action {
  SetEmailAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.login(email: value);
}
```

**Asynchronous.** `Future<AppState?> reduce() async`, and every path must
`await`. Reads go through the facade — `login.email`, never `state.login.email`:

```dart
class LogInWithEmailAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _request(email: login.email!, password: login.password!);

    return state.copyWith(login: const LoginState());
  }
}
```

`with WaitingAction` raises a wait barrier for the duration — `before()` puts it
up, `after()` takes it down — and a screen asks about it through a selector,
`isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>()`.

**How it is dispatched**, from a connector's `_Factory`: `dispatchSync` for a
synchronous setter, `dispatchAndWait` when the next step depends on the result,
plain `dispatch` for fire-and-forget.
''',
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
    context: _connectorContext,
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
    paths: ['app/lib/connectors/*.dart', 'app/lib/navigation/*.dart'],
    traps: [
      'Five edits across two packages, four of which alone leave code that '
          'does not compile. `--kind` picks the `GoAction` factory: `push`, '
          '`replace` or `navigate`.',
    ],
  ),
  'add-widget': _Situation(
    'A reusable piece of UI in the `ui` package — an input, a button, a tile, '
    'a container.',
    paths: ['ui/lib/**/*.dart'],
    context: r'''
## What a widget is here — `ui` is data-driven

A widget draws what it is handed and decides nothing. It does not fetch, derive,
look up or branch on the domain. Its inputs are data and callbacks: primitives,
a `ui`-local render model, `FieldVm` / `ChoiceVm`.

This is a boundary, not a preference. `ui` depends on neither `models` nor
`business`, so a domain type cannot even be named in this package — the
conversion happens in the connector, the one place that sees both sides.

```dart
class InputFormField extends StatelessWidget {
  const InputFormField({required this.vm, this.labelText, super.key});

  final FieldVm<String?> vm;
  final String? labelText;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: vm.value,
    validator: vm.validator,
    onChanged: vm.onChanged,
    decoration: InputDecoration(labelText: labelText),
  );
}
```

`FieldVm` is what makes that possible: the value, its `onChanged`, an optional
validator and a server-side error arrive as one object, and its `props` omit the
closures so the view-model above can still compare equal between builds.

**Text: chrome is looked up, content arrives resolved.** A widget's own fixed
label may come from `S.current`, because `ui` does depend on `localization`.
Anything that depends on the domain or the data — an option's label, a formatted
date, a pluralised count — arrives as a finished `String`, resolved in the
connector where the locale and the domain both live. `ChoiceItemVm.label` puts it
in one line: *label is data, not design*.

Every widget is scaffolded with previews into a mirrored tree under
`ui/lib/previews/`, which is what gives it a name and a rendering anything else
can reach:

```dart
@AppPreview(name: 'primary', group: 'Button')
Widget buttonPrimaryPreview() =>
    Button.primary(label: 'Primary', onPressed: () {});
```
''',
    traps: [
      '`--dir` is required and open-ended: a name that does not exist creates '
          'the folder. Ask `frx list-widget-dirs` which already hold widgets '
          'instead of inventing a home.',
      'Previews are scaffolded alongside into a mirrored tree, so a widget '
          'moved or deleted by hand leaves its preview behind.',
      '`-k` picks what it takes in: `field` takes a `FieldVm`, `choice` a '
          '`ChoiceVm`, `action` is a labelled button, `view` draws a render '
          'model, `container` wraps children.',
      'A component with its own lifecycle earns a file in a family folder — '
          'never a private `StatefulWidget` inside a page. Hidden there it has '
          'no preview and no name anything else can reach, so the next screen '
          'that needs it copies it instead. There is not one in the package.',
    ],
  ),
  'add-connector': _Situation(
    'Connecting a dumb widget to the store — the `StoreConnector` that builds '
    'its view-model.',
    paths: ['app/lib/connectors/*.dart'],
    context: _connectorContext,
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
