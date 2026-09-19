import 'situation.dart';

/// The name rule every artifact whose class carries a suffix shares, with the
/// pair that makes it concrete for the command — `Home` and `HomePage` for a
/// page. Five commands carry it; stated once, so the sixth cannot drift.
///
/// A `String`, so it sits in a `traps:` list beside the plain ones — and a
/// `const` one, so the map below stays a literal.
extension type const _SuffixTrap._(String _text) implements String {
  const _SuffixTrap(String bare, String full)
    : this._(
        'The suffix is optional and idempotent: `$bare` and `$full` scaffold '
        'the same artifact. Do not strip it yourself, and do not add it — pass '
        'the name as you have it. `frx remove` reads the same rule, so '
        'whichever spelling created it removes it.',
      );
}

/// Shared by `add-page` and `add-connector`: both scaffold the same three
/// classes, so the shape is stated once rather than twice.
const _connectorContext = '''
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

/// Authored: how each job sounds in the moment, plus what its help omits.
/// `create`, `new` and `completions` are deliberately absent — they are not
/// reached for mid-task, and the router names them.
const situations = <String, Situation>{
  'add-substate': Situation.wired(
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
      '''
The kind decides the shape: `table` for a keyed collection with an ordering,
`search` for a query with results, `value` for one value. Ask which before
scaffolding — changing it later is a rewrite.''',
      '''
It wires the `AppState` field *and* its `initial()` entry, the selectors
facade and the change log. What dispatches its starter actions is yours.''',
    ],
  ),
  'add-field': Situation.wired(
    'A piece of data a state slice does not hold yet — the slice already '
    'exists and needs one more field on it. Also the shape of a slice you '
    'just created: each field is one of these, not a file you open and type.',
    paths: ['business/lib/redux/*/models/*_state.dart'],
    context: '''
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
      '''
The field is spliced into the `@freezed` factory via AST. A non-nullable type
**requires** `--default`, because a state is constructed with no arguments.''',
      '''
It also writes the `Select…` getter, unless `--no-selector`. A field a
connector cannot read is half-wired — which is why hand-writing the field
means hand-writing the facade too, and usually forgetting it.''',
      '''
`IList` / `IMap` / `ISet` types auto-import `fast_immutable_collections`.
`--action` scaffolds the `Set<Field>Action` setter and never clobbers an
existing one.''',
      '''
Taking one out is `frx remove <field> --kind field --state <slice>` — the
inverse of this command, and the only way: the state file refuses a hand edit
in either direction. It takes the factory parameter, the facade getter and the
`Set<Field>Action` together, and prunes an import nothing else needs.''',
    ],
  ),
  'add-selector': Situation.wired(
    'A value computed from state rather than stored in it — a count, a '
    'filtered list, a derived flag; anything a screen reads that the state '
    'does not hold directly.',
    paths: ['business/lib/redux/selectors.dart'],
    context: '''
## What a selector is here

Not a function, and nothing to memoise. async_redux's own documentation teaches
selector functions cached with `cache1` / `cache2`; this template has none of
that. A selector is a getter on an `extension type` over `AppState`, so reading
one is a field access, and all of them live in a single file,
`business/lib/redux/selectors.dart`:

```dart
extension type SelectLogin(AppState _state) {
  /// Returns email value
  String? get email => _state.login.email;

  /// Returns password value
  String? get password => _state.login.password;
}
```

The facade is the `Selectors` mixin, and mixing it in is the only way in:

- a reducer, because `Action` mixes it in — `login.email`
- a connector's `_Factory`, for the same reason

There is no root type and no `state.select` hop. There were both, plus a
`Select` extension type carrying the same getter list as the mixin, and nothing
in the template ever called them — so adding a slice cost two parallel lists,
one of which was unreachable.

A value that spans slices belongs to `SelectComposites`, on the facade itself —
not inside one of the slices. The template's own member there is `isBusy`, the
fold the modal barrier reads; one that read two slices would look like this:

```dart
extension SelectComposites on Selectors {
  bool get canSubmit => session.isAvailable && !login.isBusy;
}
```

That works because `Selectors` has every slice in scope. A `SelectX` does not
reach its siblings, and in the whole template not one of them tried to. Write
one only for a reader that exists: `frx graph` lists a selector nothing reads
under "nothing reaches", and the template shipped one there for months.

`doctor` reports a selector declared anywhere but the facade
(`selector-outside-facade`), so the file is the convention, not a habit.
''',
    traps: [
      '''
`--expr` is the getter body and defaults to reading the state field of the
same name; `--type` tightens the return type from `Object?`. No codegen —
selectors are hand code.''',
      '''
A selector nothing reads is reported by the graph as a fact, not a defect: in
a template it can be API for whoever builds on it.''',
    ],
  ),
  'add-action': Situation.wired(
    'Something that changes state — a reducer, a mutation, an async operation '
    'a screen dispatches.',
    context: '''
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
`isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>()`. With
behaviour mixins alongside it, `WaitingAction` goes **last**: several of them
end the `after()` chain, so anything before one never takes the barrier down.

**How it is dispatched**, from a connector's `_Factory`: `dispatchSync` for a
synchronous setter, `dispatchAndWait` when the next step depends on the result,
plain `dispatch` for fire-and-forget.
''',
    traps: [
      _SuffixTrap('ArchiveTask', 'ArchiveTaskAction'),
      '''
Mixins conflict, and the conflict is an **analyzer error**: async_redux makes
groups mutually exclusive by colliding on a private member, so `dart analyze`
reports `private_collision_in_mixin_application`. The compiler does not —
`flutter test` on such a file runs, and an `assert` inside async_redux throws
on the first dispatch, in a debug build only. Ask `frx list-mixins` which
exclude which and let the scaffolder write the `with` clause; it refuses a bad
pair up front.''',
      '''
`-k waiting` also adds the substate's `isWaiting` getter, on the same ground
as a field's getter: a waiting action a page cannot ask about is half-wired.''',
      '''
The **order** of a `with` clause is load-bearing, and getting it wrong is not
a compile error. Dart runs one `after()` — the last mixin's — so a mixin that
overrides it without `super.after()` ends the chain. Through async_redux 28.1
`NonReentrant`, `Throttle` and `Fresh` did: `with WaitingAction, NonReentrant`
analyzed clean and never lowered the wait barrier, and the button reading
`isWaiting` stayed dead for the session. Since 28.3.1 every mixin chains (this
template requires ≥ 28.4), and the rule stays for the next one that does not:
`WaitingAction` goes **last**; `add-action` writes it there, `frx list-mixins`
says which mixins end the chain, and `frx doctor` reports a clause that has
it wrong.''',
    ],
  ),
  'add-page': Situation.wired(
    'A new screen and the route that reaches it.',
    context: _connectorContext,
    traps: [
      _SuffixTrap('Home', 'HomePage'),
      '''
It wires the page, its `@RoutePage()` connector, the `AutoRoute` entry and
auth-area membership (`--public`). Navigation **to** it is a separate decision
— that is `add-nav`.''',
      '''
`--param name:type` becomes both a `/:name` path segment and a constructor
field.''',
    ],
  ),
  'add-tabs': Situation.wired(
    'A tabbed shell — several screens living under one tab bar, as a nested '
    'route.',
    traps: [_SuffixTrap('Main', 'MainPage')],
  ),
  'add-nav': Situation.wired(
    'Getting from one screen to another — a tap that opens another page.',
    paths: ['app/lib/connectors/*.dart', 'app/lib/navigation/*.dart'],
    traps: [
      '''
Five edits across two packages, four of which alone leave code that does not
compile. `--kind` picks the `GoAction` factory: `push`, `replace` or
`navigate`.''',
    ],
  ),
  'add-widget': Situation.wired(
    'A reusable piece of UI in the `ui` package — an input, a button, a tile, '
    'a container.',
    context: '''
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
''',
    traps: [
      '''
It writes the file; what the widget is *handed* is the part that goes wrong.
`data-driven-widgets` carries it — the render model, where it lives, and what
belongs in its equality.''',
      '''
`--dir` is required and open-ended: a name that does not exist creates the
folder. Ask `frx list-widget-dirs` which already hold widgets instead of
inventing a home.''',
      '''
`-k` picks what it takes in: `field` takes a `FieldVm`, `choice` a `ChoiceVm`,
`action` is a labelled button, `view` draws a render model, `container` wraps
children.''',
      '''
**The kind adds a suffix to the name**, and the file is named after the
resulting class: `-k field Pin` writes `PinFormField` in
`pin_form_field.dart`, `-k action Submit` writes `SubmitButton`. `view` and
`container` add none. Adding it yourself is harmless — the suffix is
idempotent — but a name that reads right in the command can come out different
on disk, so check the plan before `--apply` if the spelling matters.''',
      '''
None of the kinds wraps `SegmentedControl`. A control over a set the design
fixes is `-k view` plus a `FieldVm` — `ThemeSwitcher` and `LanguageSwitcher`
are the precedent, and `data-driven-widgets` says why it is not a `ChoiceVm`.''',
      '''
A component with its own lifecycle earns a file in a family folder — never a
private `StatefulWidget` inside a page. Hidden there it has no name anything
else can reach, so the next screen that needs it copies it instead. There is
not one in the package.''',
    ],
  ),
  'add-connector': Situation.wired(
    'Connecting a dumb widget to the store — the `StoreConnector` that builds '
    'its view-model.',
    paths: ['app/lib/connectors/*.dart'],
    context: _connectorContext,
    traps: [
      '''
Converting a domain value here means **naming its type here**, and `app` does
not depend on `models` out of the box — no connector in the template converts
one. Add `models` to `app/pubspec.yaml` and run `flutter pub get`; `frx
add-package` creates a workspace member and does not draw a dependency edge
between two that exist.''',
      _SuffixTrap('Toolbar', 'ToolbarConnector'),
    ],
  ),
  'add-model': Situation.wired(
    'A data shape the app passes around — a freezed model, or a sealed union '
    'when the value is one of several cases.',
    traps: [
      '''
It writes `factory Task({required int id})` and stops. **The fields are yours
to add**, by hand, in the factory it wrote — `add-field` is for a substate's
state class and refuses a model. Then run `build_runner` in `models`, or
nothing compiles: a freezed model is half generated.''',
      '''
`-c <case>` twice or more makes it a sealed union with one factory per case.
Three answers as three cases beat a nullable field with a flag beside it.''',
    ],
  ),
  'add-enum': Situation.wired(
    'A fixed set of values — a status, a priority, a mode.',
  ),
  'add-service': Situation.wired(
    'A service and the Redux dispatcher that lets it reach the store.',
    traps: [_SuffixTrap('Sync', 'SyncService')],
  ),
  'add-package': Situation.wired(
    'A whole workspace member is missing — `add-model` or `add-retrofit` '
    'refused because the package it writes into is not in this project.',
    paths: ['pubspec.yaml'],
    context: '''
## Which packages are optional

`models` and `http_client` are optional, and a project may have been created
without them — `frx create --without models,http_client` is what leaves them
out. `app`, `business`, `ui` and `localization` are not — the app does not
compile without them, so there is nothing to add.

| kind | holds | written into by |
| --- | --- | --- |
| `models` | freezed models and JSON converters shared between packages | `add-model` |
| `http_client` | Dio + Retrofit clients and interceptors | `add-retrofit` |
| `storage` | key-value persistence behind `BaseKeyValueStorage` | nothing — `AppPersistor` uses it |

## What it writes

Five files and two kinds of edit, applied together or not at all: the package's
`pubspec.yaml` (with `resolution: workspace`, the line that makes it a member),
`analysis_options.yaml`, `build.yaml` where a builder runs, `.gitignore`,
`lib/.gitkeep` — one entry spliced into the root pubspec's `workspace:` list,
and the path dependency spliced into each package that declares it (`business`
for all three, and `http_client` for `models`).

## After it runs

**`flutter pub get` from the workspace root, before anything else.** A new
member changes what pub resolves, and until it has run the package is a
directory the analyzer cannot see. That is why this command runs no codegen of
its own — build_runner needs the resolution it just invalidated.
''',
    traps: [
      '''
It declares the dependency in the packages the template declares it in, and
nowhere else. A **different** package that wants to import `package:models/…`
still needs the entry in its own `pubspec.yaml`.''',
      '''
Asking for a package that is already a member is not an error: it writes
nothing and says so.''',
    ],
  ),
  'add-retrofit': Situation.wired(
    'An HTTP API client — endpoints against a base URL.',
  ),
  'add-theme-extension': Situation.wired(
    'Theme values the design needs — colours, sizes, spacing read off the '
    'theme.',
  ),
  'batch': Situation.wired(
    "Several artifacts at once — a whole feature's worth of state, screens "
    'and actions, wired together.',
    traps: [
      '''
One rollback boundary where eight invocations are eight boundaries: a failure
at the fifth intent leaves nothing of the first four.''',
      '''
Intents apply **in the order written** and fail loudly — `add-action` refuses
a substate that is not there — so a prerequisite comes first. Nothing is
reordered for you, on purpose.''',
      '''
Creation commands only. `rename` and `remove` are refused, and an intent
carrying `--dry-run`, `--json`, `--build-runner` or `--format` is refused too:
those decide whether the batch writes.''',
    ],
  ),
  'remove': Situation.wired(
    'Deleting any artifact — a state slice, a field on one, a screen, an '
    'action, a model, a widget, a connector, a service — with everything that '
    'points at it.',
    traps: [
      'Previews by default; `--apply` is what touches disk.',
      '''
The kind is auto-detected; pass `--kind` only when the name matches more than
one, and `--state` when an action name is used under more than one substate.''',
      '''
A **field** is the exception: it is never auto-detected, so it is `--kind
field` every time, plus `--state` unless one slice alone has a field of that
name. It takes the factory parameter, the `Select…` getter and the
`Set<Field>Action` together — and it is the only way out of a field, since the
state file refuses a hand edit.''',
      '''
Removing a field is **refused** while something still reads it — a computed
getter on the state class, a hand-written selector over it. Rewrite those
first: a selector body is yours to edit, so that is the end you start from.
Actions that merely assign the field are named in the plan and left alone; fix
them after.''',
      '''
Reach for it instead of `rm`, which deletes the file you name and leaves the
rest of the set: a service's dispatcher, a model's `.freezed.dart` and
`.g.dart` — and those two stop the package compiling once their source is
gone.''',
      '''
It deletes the artifact and unwires what registered it. It does not chase the
code that used it: what still dispatches a deleted action or imports a deleted
model is yours to fix, so run the audit after.''',
    ],
  ),
  'rename': Situation.wired(
    'Renaming a state slice or a screen — files, classes and every wiring '
    'reference.',
    traps: [
      '''
Previews by default; `--apply` is what touches disk. Identifiers move off the
parse tree, so a name inside a persistence key survives untouched.''',
    ],
  ),
  'doctor': Situation.read(
    'Checking the project is still consistent — after hand edits, after a '
    'deletion, or before calling something done.',
    traps: [
      '''
It finds wiring drift, ungenerated code and misplaced declarations — what the
Dart analyzer cannot know. Run both.''',
      '''
`--fix` repairs what is safe to repair: runs codegen, removes an orphan
substate folder that holds nothing. Placement findings never auto-fix — a
deliberately placed file is the false positive being accepted.''',
    ],
  ),
  'graph': Situation.read(
    'What reaches what — who can change this slice, what breaks if it is '
    'touched, and which selectors or actions nothing reaches at all.',
    traps: [
      '''
`--focus` takes a node id, a symbol or a bare name; `-d inbound` answers "what
breaks if I touch this" and is unbounded by default.''',
      '''
The `unresolved` section matters as much as the edges: a missing edge and a
relation that does not exist look identical, so the gaps are named rather than
dropped.''',
      '''
**"No dispatcher found" is not always dead code.** The walk starts at
connectors, actions and service dispatchers, so an action dispatched from
anywhere else — the boot in `run_env.dart` being the one the template itself
needs — is reported as reached by nobody. Check where it is dispatched before
deleting it; a substate's `Retrieve…Action` is the expected case.''',
    ],
  ),
  'flow': Situation.read(
    'What actually happens when the user taps something, how the screens '
    'connect, or refreshing the generated flow docs.',
    traps: [
      '''
`--md` writes `docs/flows/`; `--check` verifies it is current and exits 1 when
not. Never hand-edit that folder.''',
    ],
  ),
  'which': Situation.read(
    'What artifact a class, route or field belongs to — and the canonical name '
    'to hand `rename`.',
  ),
  'list-substates': Situation.read(
    'What state slices exist and are composed into `AppState`.',
  ),
  'list-routes': Situation.read('What routes the router registers.'),
  'list-widget-dirs': Situation.read(
    'Where widgets already live, before inventing a folder for a new one.',
  ),
  'list-mixins': Situation.read(
    'Which action mixins imply what, and which exclude which — before passing '
    'a second `--mixin`.',
  ),
  'watch': Situation.read(
    'Running codegen continuously while working, instead of after each write.',
  ),
};
