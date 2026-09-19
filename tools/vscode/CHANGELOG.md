# Changelog

The Marketplace renders this as the extension's **Changelog** tab.

The extension and the `frx` CLI share a version and are built on one tag — the
editor reads the CLI's contract out of generated constants, so a version pair
that can drift will. Entries here therefore cover both halves, and CLI-only
changes are marked as such.

## Unreleased

### Fixed

- **`graph` reads every action class, not every action file.** A file under
  `actions/` holds its public action and, often, what it dispatches on the
  way — a private `_ProbeStarted` beside `ProbeEmbedSpeedAction`, a
  `CloseTaskAction` beside `OpenTaskAction`, a `ReopenAndCheckAction` that
  dispatches the `ReopenAction` its file is named for. Keyed on the file, the
  graph had one node per file and reported every dispatch of the others as
  unresolved — seventeen on one project, each a class three lines under the
  import that declared it — and the main action itself as reached by nobody
  when its dispatcher was the second class in its own file. Read as one file,
  it also blended them: the last `reduce()` answered `isAsync` for all, so
  `frx flow` drew an async action as a plain arrow. Each class is now its own
  node, read on its own, resolved through the file's import or from the file
  itself; a private one is `action:<substate>.<MainAction>.<_Step>`, since two
  files in one substate may each declare a `_Started`, and carries its line.
  A named constructor (`RefreshAction.forOperator()`) and a `const`
  construction resolve to the class. *(CLI; the Map titles a private step by
  its file's action.)*

- **A connector opened through a function is built by its callers.** A
  dialog's connector is constructed in one place — the `openSettings(context)`
  its own file declares — and the screens that open it call that. The graph
  counted constructions and reported the connector as one no file constructs,
  and with it every action only it dispatches. A file that calls a function an
  imported file declares, where that function constructs a connector, now
  builds it; `HelpConnector.show(context)` the same way. *(CLI)*

- **A gap in a region is reported against the region.** A dispatch the graph
  could not resolve inside a region connector was listed under the page's own
  file, where the line is not. *(CLI)*

- **A connector file that puts `_Factory` first is still the connector.** A
  consumer node was named by the file's first class, so the node was
  `_Factory` — three files in a project all called that, one node. It is
  named by the first public class, or the file. *(CLI)*

### Added

- **`graph --focus session.token` — one field, not the slice.** A slice with
  fifty fields is a hub: every selector on it reads it, every setter writes
  it, and an inbound walk from the slice was the whole app (106 of 234 nodes
  for one `console`). Focused on a field, the edges at the slice are kept
  when they name the field or the whole slice — a flat `copyWith` and the
  persistor's restore change every field — and the walk goes on from what is
  left: 26 nodes. Every `reads` edge now says which field (`via
  session.token`), a substate node lists its `fields`, and a field the state
  class does not have is refused with the ones it has. *(CLI)*

- **`graph` records a direct read of the state.** `state.console.projectId`
  in a reducer, `store.state.session` in an `onInit`, `state.memory.x` in a
  connector callback that skipped the facade — the one reference no edge
  recorded, so "what breaks if I touch `console.seq`" missed the reducer
  reading it, and a selector on the dead list sat beside a reducer reading
  the same field with no way to say *dead selector, live field*. A `reads`
  edge from the action, page or connector, by field. *(CLI)*

- **`graph` reports a service dispatcher nothing constructs**, by the rule
  the connector verdict uses: it is built once, where the app wires its
  services, and one nothing constructs is dead with every action only it
  dispatches. `builds` edges reach `service:` nodes. *(CLI)*

- **`graph` reports a field nothing reads.** The question a dead selector
  could not settle: `SelectSetup.agentErrorOn` on the list says the getter is
  unused, and whether the field behind it is depended on every reducer and
  connector reading the state directly. Now that those reads are edges, by
  field, the list says `field:setup.agentErrorOn  written, nothing reads it`
  — four actions write it, nothing looks — and stays quiet about
  `console.seq`, whose selector is dead and whose field a reducer reads. A
  field is live when anything that is not a dead selector reads it, or when
  anything live reads the whole slice; the persistor's reads do not count.
  `--fail-on-orphans` gates on it. The FRX tree lists a slice's fields under
  it, with the same mark; `--focus field:setup.agentErrorOn` is accepted as
  the list spells it.

## 0.3.6

### Fixed

- **The FRX tree has its rows when its section is opened.** The graph behind
  it was read on the first `getChildren`, and a refresh only dropped the cache
  for the next one — but VS Code asks only a section that is visible and
  expanded, and holds a hidden section's refresh until it is opened. So a
  section collapsed at startup, or collapsed while the last change landed,
  ran `frx graph` on the click that opened it, and the rows arrived a CLI run
  later — beside a Dependencies view that had them at once. A refresh now
  reads immediately, and the activation refresh reads the tree along with the
  first audit.

- **A Map column is wide enough for the names it hides.** The column was
  measured to its widest *visible* line — the titles, subtitles and counts —
  while the actions and selectors under a substate start folded, and a folded
  name has no width to measure. Expanding `boot` then ran
  `SetEmbedderRendezvousAction` out past the box's edge. The measurement now
  unfolds every list first, and lets the layout engine size the column to its
  content rather than walking the lines by a selector — which is what the
  lists were missing from.

- **The Map no longer hangs the window on a cycle of builders.** A connector
  built by one of two connectors that build each other sent the nesting walk
  round that cycle forever, on the picture's first draw, with the extension
  host — and every other extension in it — stuck behind it. The walk is now
  bounded by the column: the row keeps its builder, and the cycle is cut at
  the first of its own rows, as before.

- **The Map's columns stay where they are across a click.** The shorter
  column is placed level with what it relates to, and which column that is
  was decided on every redraw from a height the last placement had set —
  so each expand, fold or resize handed the placement to the other column
  and every row on the page moved. The height is cleared before measuring,
  and the placed column now keeps the placement until the other is shorter
  by half: a row that opens is not a picture that changed shape.

- **`remove <action>` takes a waiting action's getter with it.** The one
  thing an action's `add-*` wires is the `isWaiting` getter keyed on its
  type, and a removal deleted the file and left the getter and its import
  behind — `selectors.dart` naming a type that was gone, with a note to go
  run the audit. The facade is unwired in the same plan; a getter another
  facade member still reads is kept and named in the preview. *(CLI)*

- **`add-action -k waiting` imports the action into the facade.** The
  `isWaiting` getter it writes names the action as a type argument, and
  `selectors.dart` imports nothing that declares it; the getter was written
  and the facade stopped compiling, on the first waiting action in a fresh
  project. *(CLI)*

- **A `--json` run keeps stdout to the one object.** Every apply printed
  `✓ docs/flows refreshed` on stdout ahead of the changeset, and a build
  asked for with `-b` inherited build_runner's output there too — in a
  repository with `docs/flows/` no `--apply --json` parsed. Both go to stderr
  in a machine run, where they are still said. *(CLI)*

- **The FRX panel is there when the window is.** The extension activated on
  `onStartupFinished` alone — after every other extension, which with the
  Dart tooling was eight seconds into the window — so the panel appeared
  late with nothing to say why. It now also activates on the marker file
  the CLI keys on (`app/lib/navigation/app_router.dart`), and the manifest
  check refuses a glob that drifts from the generated marker path.

### Added

- **A large page's flow is drawn in pieces.** `frx flow --md` and the Flow
  view drew a page as one sequence diagram however many lanes it took, and
  mermaid fits the drawing to the page: a screen composed of fifteen regions
  came out at forty-five lanes with every label at three pixels. Past a dozen
  lanes a page is now one diagram per interaction, each with only the lanes
  it touches, under a heading naming it. `frx flow <page> --doc` prints that
  document for one page, and the Flow view shows it — the interaction table
  included — falling back to the bare diagram on a CLI without the flag.
  *(CLI + editor)*

- **`add-action --mixin sequential`** — async_redux 28.3.1's `Sequential`,
  a FIFO queue per key: actions run one at a time, in dispatch order. The
  catalogue carries its knobs (`sequentialKeyParams`, `discardQueueOnError`)
  and its incompatibilities (`Debounce`, `UnlimitedRetryCheckInternet`),
  which the package asserts at runtime but the analyzer does not see — so
  `add-action` refusing the pair up front is the only refusal a release
  build gets. The catalogue test now reads those pairs off the package's
  `_incompatible<A, B>` calls as well as its collision markers. *(CLI)*

- **The graph names an orphan folder's actions as a gap.** An action's
  substate is the folder it sits in, and nothing checked that `AppState`
  still composes it, so `frx graph --json` emitted actions of a substate no
  consumer could find — the Map threw on its first draw. Such an action now
  stands on its own and comes with an `orphan-substate` entry in
  `unresolved` naming the folder and the two ways out. *(CLI)*

### Changed

- **The template requires async_redux ≥ 28.4.** `business` and `app` pin
  `^28.4.0`: the mixin catalogue, the skills and the audit now describe
  28.4's behaviour — every hook chains, `Sequential` exists — and a project
  resolving an older 28.x would be told things that were not true of it.
  The template's own `WaitingAction` marks both hooks `@mustCallSuper`, as
  async_redux's are from 28.4, so an action that writes its own `after()`
  and forgets `super` hears it from the analyzer where it is written, not
  only from `doctor`. Verified on a project created from the template:
  build, analyze, tests, `doctor`, and an action scaffolded
  `-k waiting -m sequential -m nonReentrant`. *(template)*

- **No mixin frx offers ends the `after()` chain any more.** async_redux
  28.3.1 made `NonReentrant`, `Throttle` and `Fresh` chain to `super.after()`,
  and the catalogue test — which reads that off the package — said so.
  `swallowsAfter` is false for every mixin; `WaitingAction` is still emitted
  last, and the `action-mixin-order` audit still reads the flag, so both fire
  again the day a mixin stops chaining. *(CLI, with async_redux ≥ 28.3.1)*

- **The build tasks are a Dart program.** `tools/Makefile` is
  `tools/tool/xtask.dart` — `dart run tool/xtask.dart install --profile
  Flutter`, `… version 0.3.6`, `… check`, the same targets under the same
  names. The Makefile bumped versions with perl (because `sed -i` differs
  between BSD and GNU), listed VSCode profiles through python, and ran on
  neither of the platforms the CI's Windows leg exists for; the tasks are in
  the project's language now, with its `args` and its tests. `PROFILE` and
  `CODE` in the environment still stand in for the options. *(repo)*

- **The Map page has tests that run it.** `map.test.ts` pinned what the
  script says; a jsdom suite now pins what it does — the wires a picture
  yields, the focus, the pane, the folds, the gaps and what a refresh
  remembers. Two regressions that the text tests let through were caught by
  hand in a browser; these would have caught them.

- **The Map's pane reads as relations, not as lines.** Hovering `memory`
  listed fifty entries, twenty of them beginning `MemoryConnector ·`. Each
  row across is now said once, with the actions and selectors behind its
  line under it, and a trigger they all share — a page whose every dispatch
  runs through one callback — said once beside the row. The unresolved edges
  at the foot of the page are grouped the same way, by reason: seventeen
  gaps were two sentences, each repeated. Lines that change state are drawn
  over lines that only read it, so the answer to "who changes this" is never
  under a grey line in the bundle.

- **Less work on the paths that run all the time.** The code-lens provider
  compiled its five path patterns from `LAYOUT` on every edit of every Dart
  file, and searched the document's text twice for one class; the patterns are
  now built once with the root, and the text is read once, and only when a
  lens needs it.
  The Map's crossing count is an inversion count over a Fenwick tree instead
  of a comparison of every pair, the sweep no longer flattens every subtree
  or re-indexes the facing column on every pass, and it stops at the pass that
  changes nothing — the same orderings, in a sixth of the time on this
  repository's shape and a fortieth at three thousand lines. (The facing
  column is still indexed once per pass; what stopped is indexing it again
  for every subtree.) The Map page reads each row's rectangle once
  per redraw and attaches its wires in one append (it re-laid the page out
  once per line), and lights a hovered row from the adjacency it recorded
  while drawing rather than by asking the DOM for every wire. The tree
  computes what each substate owns once per read instead of once per row.
  The installed binary's `--version` is remembered while the file is the same
  one, so a refresh spawns two processes, not four. Process output is decoded
  once, and a machine read — the graph, the audit, a plan preview — logs its
  size to the channel rather than its hundred kilobytes of payload.

## 0.3.5

### Fixed

- **`frx which <name>` exits 1 when nothing is wired under that name.** It
  printed "is not a wired frx substate or page" and exited 0, which read as
  success to anything that does not parse English — an agent gating a rename on
  it, a script's `&&`. Now `grep`'s convention: 1 is "no", not "broken", and
  `--json` still prints `{kind: null}` on it. The editor's rename provider reads
  the JSON and ignores the code. *(CLI)*

- **A doctor finding about a declaration lands on its line, not on line 1.**
  Findings carried a file and nothing finer, so the Problems panel put every
  squiggle at the top of the file — a route with no connector, a duplicate
  getter, a `with` clause in the wrong order, all on line 1 of a router or a
  facade hundreds of lines long. `--json` findings now carry 1-based `line` and
  `column` when the check read a declaration (route entries, `AppState` fields,
  change-log entries, getters, mixin clauses and hooks, misplaced declarations,
  view-model fields, a NUL byte), and the extension anchors the diagnostic
  there. Findings about a whole file — a missing part, a stale export — carry
  neither, and the human report appends `path:line:column` only where there is
  one. Additive: a consumer that predates the two fields reads the shape it
  always did.

- **The stale-skills finding names the command that fits.** It said "written by
  0.3.2" and stopped, and for the case that actually happened — the tree and the
  binary both said 0.3.4 and disagreed, because one was a build between
  releases — it read as a contradiction. Three cases now, each with its remedy:
  written by an older frx (`frx update-skills`), by a newer one (`frx upgrade`,
  or `update-skills` to write them back down), or by another build of the same
  version (one side is between releases; which command depends on which side
  you are keeping). *(CLI)*

- **The template shipped seven selectors nothing read, with doctor green.**
  `frx graph` listed `canEnterApp`, `SelectSession.isAvailable`/`token` and four
  per-slice `isWaiting` getters under "nothing reaches", and nothing gated on
  that list. `canEnterApp` and the four `isWaiting` are gone — the barrier folds
  off `isBusy`, which is why they had no reader — and the auth guard and
  `run_env` now decide on `session.isAvailable` through the facade instead of
  spelling `state.session.token != null` twice, so the session selectors have
  the reader they were written for. The graph reports nothing unreached. *(template)*

- **The README command map had drifted.** `add-package` and `update-skills`
  had been on the CLI for releases and were not in the table. Both are, and
  `readme_command_map_test` now reads the table against the runner the way
  `skills_freshness_test` reads the skills. *(CLI)*

- **A command with no `frx` to run comes back at once.** When neither the
  binary nor a `dart` to `dart run` it with could be found, the "could not find
  the `frx` CLI" notification offered *Install frx* and *Open Settings*, and the
  command waited for the answer. A notification with buttons stays up until it
  gets one, so every command's promise stayed open until a click — nothing a
  person would notice, but the integration test runs `frx.doctor` on a runner
  that has neither, and timed out at 60s. The notification still offers both and
  acts on the pick; the command no longer waits on it.

- **The CLI on Windows.** The suite's first run there found three things a
  user would have met. The agent-hooks check looked for the platform separator
  in a hook command, which on Windows is `\`, so every hook read as a bare
  name and a missing script was never reported — the fail-open the check
  exists to catch. Paths built from the source constants kept the `/` the
  constant was written with and gained `\` from every join after it, and went
  into graph JSON and findings that way. And a diff header carried `\`, which
  `git apply` does not read. All three are fixed, and the suite compares paths
  as paths rather than as spellings; the Windows leg stays informational until
  a run comes back green. *(CLI)*

### Added

- **`frx graph --fail-on-orphans`** exits 1 when the "nothing reaches" list is
  not empty — a gate for CI, and the template's own CI runs it. Kept out of
  `doctor` on purpose: frx's own `add-action -k waiting` writes an `isWaiting`
  nothing reads yet, and a check that fired on the tool's own output would be
  noise. *(CLI)*

- **The extension warns when it and the CLI are not the pair that shipped
  together.** Compared by major.minor once per session on resolve; a CLI that
  is behind gets an "Upgrade frx" action that runs `frx upgrade` from the
  editor, one that is ahead is told to update the extension. The failure it
  names was quiet: an extension a minor ahead offers a `--kind` the binary
  rejects, and the user saw "FRX failed (exit 64)".

- **The extension checks for a new frx release once a day.** `frx upgrade
  --check --json` already answered the question with an exit code written for
  gating; the editor is the one surface open every day that never asked it.
  Installed binaries only, at most once per 24 hours, and never a word on
  failure — offline, endpoint down and a binary too old to know `--check` all
  look the same from here.

- **A real-VS-Code integration suite** (`npm run test:integration`, on
  `@vscode/test-electron`) — activation in the monorepo, every contributed
  command registered in the running host, `frx.doctor` end to end. The unit
  suite runs against a hand-written `vscode` stub and could not say any of
  that; CI now runs both.

- **The one-line installer wires shell completions in.** A `# frx completions`
  line in the profile it also puts `PATH` into (zsh, bash), or
  `~/.config/fish/completions/frx.fish`; `--no-modify-path` leaves both alone,
  and a re-run adds nothing twice. `frx completions` existed; nothing sourced
  it. *(CLI)*

- **The CLI suite runs on Windows in CI**, informationally for now
  (`continue-on-error` until a run comes back green), with a `.gitattributes`
  that keeps every checkout LF so the byte-comparing tests compare bytes and
  not line endings. The binary shipped for three platforms and the suite had
  only ever run on one. *(CLI)*

### Changed

- **The FRX Map's page script and styles are files, not a template string.**
  `media/map/map.js` and `map.css`, loaded by URI under the same nonce CSP; the
  picture crosses as a JSON block. Eight hundred lines of JavaScript sat inside
  a TypeScript string behind two levels of escaping that nothing checked — a
  lone `\n` in it became a real newline in the emitted script and the page
  stopped parsing, with nothing anywhere saying why. The unit suite now parses
  the script as JavaScript.

- **`frx new` reads its answers through the console**, so the wizard has tests:
  a scripted conversation in, the echoed command line and its effect out. It
  read `stdin.readLineSync()` directly and was the one command with none. *(CLI)*

- **`discover.ts`'s installer directories are kept in step by a test**, which
  reads `install.sh` and `install.ps1` for their defaults, rather than "by hand".

- **Version bumped to 0.3.5 right after the 0.3.4 tag** — see the stale-skills
  entry for what a working tree that still says 0.3.4 costs.

## 0.3.4

### Fixed

- **`graph` no longer calls a selector dead because its reader holds the facade
  in a variable.** The chain rule counted `chats.unreadTotal` when the receiver
  heads the chain — how a class mixing in `Selectors` reaches one — and refused
  any segment in front of it except the literal `select` of the spine that no
  longer exists. A file that does `final s = _Reader(state); s.chats.unreadTotal`
  was therefore read, scanned and not counted, so a selector only it reads came
  back on the list frx uses to say "you can delete this". On a real project that
  was the application's tray icon, and the one false positive left in the list.
  A receiver is now judged by *type*: a class with `Selectors` in its `with`
  clause is the facade, and so is a variable, field or parameter holding one, or
  the type where the facade is built in place. Not "any receiver" — a substate's
  field and its selector are spelled the same, so that would have read
  `state.session.token` as a selector and hidden every genuinely dead one behind
  the substate it reads. Measured on the same project: five edges gained, none
  lost. *(CLI)*

- **`remove --kind selector` takes the imports the getter was the last reason
  for.** The splice pruned only the imports a table knew about, so a getter's
  own went on standing: the action file behind
  `_state.wait.isWaitingForType<LoadContactsAction>()`, and a package that
  supplied one return type. Two `unused_import`s in a file under the placement
  guard, repaired by the hand edit the command exists to avoid — and a facade
  imports one write-layer file per waiting getter, so this is the ordinary case.
  Which imports are still needed is now read rather than looked up: a URI
  resolves to a file, a file declares names and hands on what it exports, and a
  name in the surviving source keeps the import. Three things it takes to be
  right rather than merely safe — uses are read off the tree, so a word in prose
  is not one; a type is not an identifier on that tree; and a name can have two
  suppliers, so an import goes only when every name it still answers for is
  answered by an import that stays, which is `unused_import`'s own rule.
  Anything unreadable keeps the import. The same pass runs when a whole
  substate's selectors are unwired. Replayed against a real cleanup of nine
  selectors, the import list frx leaves is now the one that was fixed by hand.
  *(CLI)*

## 0.3.3

### Fixed

- **A generated waiting action could raise the wait barrier and never lower
  it.** `add-action -k waiting -m nonReentrant` wrote `with WaitingAction,
  NonReentrant`, and Dart runs one `after()` per class — the last mixin's.
  `NonReentrant.after()` releases its own lock without calling `super.after()`,
  so the barrier stayed up: the action finished and
  `isWaitingForType<T>()` remained true for the rest of the session, leaving
  every widget that reads it disabled. The file compiled, analyzed clean and
  passed its tests. `add-action` now emits `WaitingAction` last, and the
  template's own `WaitingAction` chains `super` in both hooks — reversing the
  order alone would only have moved the loss to the reentrancy lock, which the
  regression test pins. *(CLI + template)*

- **`graph` no longer calls a dispatched action an orphan.** The orphan list is
  the one place frx says "you can delete this", and it was reading dispatches
  out of the routed page walk, which draws an edge only where a dispatch is
  written as a named argument of `_Vm(...)`. Four ordinary shapes fell outside
  it: `onInit:` on the `StoreConnector`, a callback built in `builder:`, any
  connector no route registers (the `MaterialApp.builder` tree), and
  `StoreProvider.dispatch(context, X)` — whose action is the *second* argument,
  so the `BuildContext` was read as the thing dispatched. Two more came from
  the action reader: it took cascades from `reduce()` only, so a dispatch in
  `before()` / `after()` / a mixin's required override was invisible, and it
  *assigned* rather than appended per `reduce()` it met, so in a file with two
  action classes the second erased the first's. Dispatches are now swept from
  every file of the app's own packages — the rule the selector half of the same
  reader already applied, and states in a comment. Measured on a real project:
  eleven reported orphan actions, none of them dead. *(CLI)*

### Added

- **`graph` says when a whole connector is dead, instead of listing its
  actions.** A connector now has a node and a `builds` edge, so "no file
  constructs it" is a verdict frx can reach: on a real project six of eleven
  reported orphan actions were dispatched only from a `SettingsConnector` that
  nothing builds. Composition is matched on the class name rather than on a
  `*_connector.dart` import, because the file that constructs the app's root
  widget is not itself a connector — resolving through the import pattern
  called `AppConnector` unbuilt. In-degree, not reachability from a root: frx
  does not know which widget the root is, and being wrong about that would
  report a live screen as dead. *(CLI)*
- **`doctor` reports two selectors with one body.** What is left after
  `add-selector` correctly declines a taken name and the reader is added by
  hand under another: both are right, and together they are one fact under two
  names that the next change has to find twice. A warning, and
  character-for-character — two getters that compute the same thing differently
  are a judgement call frx has no business making. *(CLI)*
- **`remove --kind selector`.** `add-selector` had no inverse, and
  `selectors.dart` is under the placement guard, so the way out was a hand edit
  to a file frx complains about being hand-edited. Takes the address `graph` and
  `doctor` print (`SelectTheme.isWaiting`) or the bare name with `--state`, and
  refuses while another getter on the facade reads it. *(CLI + extension)*
- **`list-mixins` lists the mixins the project declares**, with the hooks each
  overrides and whether it passes the chain on — `WaitingAction` is the mixin in
  this architecture that must go last, and the command whose job is to say what
  combines with what could not see it. `--root` had been accepted and ignored;
  this is what it is for. *(CLI)*
- **The mixin-order rule is no longer only about `WaitingAction`.** An action
  that overrides `after()` without `super` in front of `NonReentrant` leaks the
  reentrancy key just as surely, with no barrier involved. Which hooks a mixin
  overrides is now derived from the async_redux source alongside the rest.
  *(CLI)*

- **`doctor` reports a `WaitingAction` whose cleanup never runs.** Three shapes:
  a `with` clause placing it before `nonReentrant` / `throttle` / `fresh`, an
  action overriding `before()` / `after()` without `super` (a class member beats
  the whole `with` clause), and a project `WaitingAction` declaration that does
  not chain — that file belongs to the project, so generating the clause
  correctly is not enough on its own. Errors, and not silenceable: they name
  async_redux's own mixins doing what its own source says they do. *(CLI)*
- **`list-mixins` says which mixins end the `after()` chain**, as a third note
  beside `implies` and `excludes`, and as `swallowsAfter` in `--json`. The set
  is derived from the async_redux source by the test suite rather than
  transcribed. *(CLI)*

### Changed

- **The docs say what actually enforces an excluded mixin pair**, after
  measuring rather than reading: `dart analyze` reports
  `private_collision_in_mixin_application`, and the compiler does not — the pair
  builds, so a test file the gate rejects still runs and async_redux's `assert`
  throws on the first dispatch of a debug build. An intermediate version of this
  note claimed the collision did not apply at all; it does. Pinned by
  `business/test/mixin_exclusion_test.dart`, since `tools` cannot import
  async_redux to check it. *(CLI, docs only)*

## 0.3.2

### Fixed

- **A transition subclass was not read as a route at all.** auto_route spells a
  transition by subclassing — a sheet over the screen behind it is
  `CustomRoute(opaque: false)`, and `MaterialRoute` / `CupertinoRoute` /
  `AdaptiveRoute` pick a platform transition — and `AppRouter` was matched on
  the base class name alone. A screen registered as any of the four was
  invisible to every reader at once: `list-routes` left it out, `doctor`
  reported its connector as unregistered, `remove` could not find it, and
  `flow --md` deleted its generated document as a page that had gone.
  `RedirectRoute` and `NamedRouteDef` carry no page, so they are still not
  screens. *(CLI)*

### Changed

- **The analyzer no longer walks the build output or the platform folders.**
  `build/`, `android/`, `ios/`, `web/`, `windows/`, `macos/` and `linux/` are
  excluded in every package the template ships, and `add-package` writes the
  same set into a package it creates. *(CLI)*

## 0.3.1

### Added

- **`frx upgrade`** replaces the installed binary with the newest release —
  same redirect, same `checksums.txt` check as `install.sh`, done from the
  binary itself. `--check` reports without installing and exits 1 when an
  upgrade exists, so it can gate a command. It is the only part of frx that
  opens a socket: no background check, nothing appended to unrelated output.
  *(CLI)*

### Fixed

- **The upgrade compared versions for inequality, not order,** so a source
  build made after a version bump but before its tag was published was told to
  upgrade backwards. A pinned `--version` still installs in either direction —
  naming a version is how you go back to one. *(CLI)*
- **A mirror that labels `.tar.gz` with `Content-Encoding: gzip`** made every
  upgrade fail as "tampered with", because Dart inflates what `curl` stores
  verbatim. *(CLI)*
- **Failure paths that left a mess:** a missing `tar` crashed with a stack
  trace instead of a sentence, a failed staging copy left a truncated binary
  beside the real one, and on Windows a failed swap could leave the install
  directory with no `frx.exe` and nothing saying where it went. *(CLI)*

## 0.3.0

### Fixed

- **`frx flow` lost whole regions.** A dispatch was found only where it was
  written inside the subtree of a `_Vm(...)` argument, so a callback built by a
  member of the same factory — the shape a list row takes the moment it needs
  one — was invisible, and a region with no interaction gets no lane and leaves
  the diagram. Measured on one page: six of eleven regions missing. The walk now
  follows calls and tear-offs into the file's own functions, and refuses to
  follow a name that anything nearer binds. *(CLI)*
- **What the map does not draw is now said.** Dispatches no use case accounts
  for are counted and reported — in `--json`, in the diagram, in the exported
  markdown and in the terminal — instead of being dropped. `frx flow` and the
  markdown export also stop claiming a page "has no dispatching callbacks" when
  the truth is that none could be followed. *(CLI)*
- **`frx doctor`'s equality rule was switched off by an unrelated element.** Any
  entry in `super(equals: [...])` that was not a bare field name — an integer, a
  string, another object's `hashCode` — made the whole list unreadable, and an
  unreadable list reports nothing. Only a spread genuinely hides membership now;
  everything else is read, and a field compared only through something derived
  from it (`ids.length`) is reported as that rather than as absent. *(CLI)*

### Added

- **A one-line install for the CLI.** `install.sh` (macOS, Linux) and
  `install.ps1` (Windows) download the release for the running platform, verify
  it against the release's `checksums.txt`, and put `frx` in `~/.frx/bin`
  (`%LOCALAPPDATA%\frx\bin`). No Dart SDK required — the binary is
  self-contained, template included.
- **Native binaries per platform**, attached to every GitHub release: macOS
  arm64 and x64, Linux x64 and arm64, Windows x64. The Linux ones are built
  inside Dart's own `dart:stable` image — Debian bookworm, glibc 2.36 — rather
  than on the runner, whose glibc is always the newest thing GitHub hosts and
  would refuse to start on anything a year behind. Debian 12, Ubuntu 24.04 and
  Fedora 38 upwards; below that, build from source with `dart install`.
- **The extension finds an installed binary in `~/.frx/bin`.** It already
  searched `PATH` and `dart install`'s directory as *files* rather than spawning
  a bare name; the installer's directory joins them, because the `PATH` line it
  adds to your shell profile is exactly what a Dock- or Start-menu-launched
  editor never reads. `dart install`'s directory is still searched first: on a
  machine with both, the locally built binary belongs to somebody working on frx
  itself.

### Changed

- **"Could not find the frx CLI" now leads with the download.** It used to say
  `dart install .` in `tools/`, which is a dead end for anyone who arrived from
  the Marketplace and has no checkout.

## 0.2.0

- Everything up to this point. The extension was distributed as a `.vsix` from
  the repository; this is the first version prepared for the Marketplace, with
  the icon, categories and workspace-trust declaration a listing needs. See the
  [commit history](https://github.com/pro100andrey/flutter_redux_templates/commits/main/tools/vscode)
  for what came before.
