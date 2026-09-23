import 'package:args/args.dart';

import '../ast/source_index.dart';
import '../engine/write_path.dart';
import '../model/removable_artifact.dart';
import '../model/target_resolver.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'remove/field_removal.dart';
import 'remove/file_removal.dart';
import 'remove/leftovers.dart';
import 'remove/page_removal.dart';
import 'remove/selector_removal.dart';
import 'remove/substate_removal.dart';
import 'writing_command.dart';

/// Removes an artifact: deletes its files and unwires whatever registered it —
/// the inverse of the `add-*` command that made it.
///
/// Destructive, so it previews the plan by default and only touches the disk
/// with `--apply`.
///
/// Two kinds of target, resolved differently on purpose. A substate and a page
/// are *wired*: they are found by what the project declares (an `AppState`
/// field, an `AppRouter` route) and removing one is mostly an unwiring job. The
/// rest — action, model, widget, connector, service — are file sets in known
/// places whose `add-*` wired nothing central, so they are found on disk and
/// removing one is about deleting the whole set: a widget's preview in the
/// mirror tree, a service's dispatcher beside it, a model's `.freezed.dart`.
///
/// That set is the reason this command grew. Across six traced builds the agent
/// reached for raw `rm` sixty-odd times — for actions, models and connectors it
/// could not ask `remove` for — and `rm` deletes the file it was given and
/// leaves the rest of the set behind.
///
/// Each kind's plan is its own mixin under `remove/`; what is here is the
/// surface — the options, and deciding which kind the name is.
class RemoveCommand extends WritingCommand
    with
        FileRemoval,
        SelectorRemoval,
        FieldRemoval,
        SubstateRemoval,
        PageRemoval {
  /// The name is looked up, not written: whatever the artifact is called
  /// already, it is called.
  @override
  bool get createsNames => false;

  @override
  String get name => 'remove';

  @override
  String get description =>
      'Remove an artifact: delete its files and unwire it (AST).';

  @override
  String get invocation => 'frx remove <name> [--kind <kind>] --apply';

  @override
  List<String> get aliases => ['rm'];

  /// No `--dry-run`: a destructive command previews by *default* and writes on
  /// `--apply`, which is a difference in stance rather than in spelling.
  ///
  /// No `--force` either — not because it has none, but because the one it has
  /// is not the base's. Declared below, where its own meaning is.
  @override
  WriteFlags get flags => const WriteFlags(
    dryRun: false,
    force: false,
    diff: true,
    buildRunner: true,
  );

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: [
          'substate',
          'page',
          'field',
          'selector',
          for (final k in RemovableKind.values) k.flag,
        ],
        help: 'Force the target kind (default: auto-detect).',
      )
      // Only `action` and `field` can legitimately exist twice under one name,
      // because the substate folder is part of their address — and a field
      // named `value` is in every slice `add-substate` made with its default
      // kind. Every other kind lives in one directory, so a duplicate there is
      // a naming collision to fix rather than a target to disambiguate.
      ..addOption(
        'state',
        abbr: 's',
        help:
            'For --kind action / field: the substate that owns it, when the '
            'name is used under more than one.',
      )
      // `--apply`, not `--force`: for the scaffolders `--force` means
      // "overwrite what is there", and spelling "actually do it" the same way
      // made `add-page --force` and `remove --force` opposites. `--force` stays
      // accepted so existing scripts keep working, but it is not the name — and
      // that is why it is declared here rather than taken from the base, whose
      // `--force` is the other meaning.
      ..addFlag(
        'apply',
        abbr: 'a',
        negatable: false,
        help:
            'Apply the removal (delete files + unwire). Without it the plan is '
            'only previewed.',
      )
      ..addFlag('force', abbr: 'f', negatable: false, hide: true);
  }

  /// The file kinds by their `--kind` spelling.
  static final Map<String, RemovableKind> _fileKinds = {
    for (final k in RemovableKind.values) k.flag: k,
  };

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async =>
      // One snapshot for the whole plan. Auto-detection asks every state file
      // whether it declares the name, then the failure path asks again; and
      // the resolvers list `redux/` and `ui/lib` for each kind they try.
      // Outside a scope each of those lookups reads and parses on its own.
      inSourceIndex(() => withLeftovers(_plan(repo, results), repo));

  WritePlan _plan(FrxWorkspace repo, ArgResults results) {
    final forced = results['kind'] as String?;
    final state = results['state'] as String?;
    final apply = applying(results);

    // Before `requireName()`, which is the whole reason this branch is first:
    // the address `graph` and `doctor` print is `SelectTheme.isWaiting`, and
    // the name validator rejects the dot. Pasting what the tool just told you
    // is the case worth supporting, so the raw argument is read there and
    // [removeSelector] decides what it means.
    if (forced == 'selector') {
      return removeSelector(repo, state: state, apply: apply);
    }

    final name = requireName();

    final onDisk = RemovableResolver(repo);

    // A field is addressed by its substate and its name, never by a class, so
    // it is asked for rather than detected — see [FieldRemoval]. Answered
    // before the wiring sources are located, because a field lives entirely in
    // `business`: a project with no router can still lose one.
    if (forced == 'field') {
      return removeField(name, repo, state: state, apply: apply);
    }

    // Forced to a file kind: there is no wiring to consult, so the wiring
    // sources are never located — a project missing `app_router.dart` can still
    // delete a model.
    if (_fileKinds[forced] case final kind?) {
      final found = onDisk.resolve(kind, name, state: state);
      if (found == null) {
        if (onDisk.blocked != null) {
          usageException(onDisk.blocked!);
        }
        refuse(notFound(kind, name, state));
      }
      return removeFiles(found, apply: apply, repo: repo);
    }

    // The substates declaring a field of this name, asked at most once: the
    // auto-detection counts them as a collision, and the failure path names
    // them — both on the same run, when the name is a field and nothing else.
    List<Casing>? owners;
    List<Casing> fieldOwners() =>
        owners ??= substatesWithField(repo, name.camel);

    // Locate each source independently and resolve the kind: removing a
    // substate shouldn't require a router (or vice versa), so a project missing
    // one file can still remove the other kind.
    final resolver = TargetResolver.locate(results['root'] as String?);

    // Auto-detection has to see both worlds. Without this, `remove ArchiveTask`
    // reports "nothing named that is wired" for an action the project plainly
    // has, and the reflex it teaches is `rm` — which is the habit this command
    // grew to replace.
    if (forced == null) {
      final wired = [
        if (resolver.isSubstate(name)) 'substate',
        if (resolver.isPage(name)) 'page',
      ];
      final matched = <RemovableArtifact>[];
      for (final kind in RemovableKind.values) {
        final found = onDisk.resolve(kind, name, state: state);
        if (found != null) {
          matched.add(found);
        }
        // An ambiguity inside one kind is still an ambiguity; surfacing it here
        // beats reporting "nothing found" for a name that matched twice.
        if (onDisk.blocked != null) {
          usageException(onDisk.blocked!);
        }
      }

      // A field is not *resolved* by auto-detection — it is asked for, see
      // [FieldRemoval] — but it does count as a collision. Without this,
      // `add-field log_in tags:String?` plus a `Tags` model made
      // `remove tags --apply` delete the model and never mention the field: an
      // ambiguity resolved by a rule, which this command's own doctrine says is
      // still an ambiguity and under `--apply` is unrecoverable.
      final kinds = [
        ...wired,
        if (fieldOwners().isNotEmpty) 'field',
        ...matched.map((a) => a.kind.flag),
      ];
      if (kinds.length > 1) {
        usageException(
          '"${name.pascal}" matches ${kinds.length} kinds '
          '(${kinds.join(', ')}). '
          'Disambiguate with --kind ${kinds.join('|')}.',
        );
      }

      if (matched.length == 1) {
        return removeFiles(matched.single, apply: apply, repo: repo);
      }
    }

    final resolution = resolver.resolve(name, forced: forced);
    if (!resolution.ok) {
      // The resolver already decides which failure is the user's usage and
      // which is the project's shape; the two exit codes are its answer, and
      // this maps them to the two ways a command has of saying so.
      if (resolution.code == 64) {
        usageException(resolution.error!);
      }
      // Before refusing, ask the one kind auto-detection does not reach. "Not a
      // wired substate or page" is a true sentence about a name that is plainly
      // *there* as a field, and the reflex it teaches is the hand edit the
      // guard refuses — after which there is nothing left to try.
      final holders = fieldOwners();
      if (holders.isNotEmpty) {
        final owner = holders.length == 1
            ? 'substate "${holders.single.snake}"'
            : 'substates ${holders.map((o) => o.snake).join(', ')}';
        refuse(
          '${resolution.error!}\n'
          '  "${name.camel}" is a field of $owner '
          '— remove it with `frx remove ${name.camel} --kind field'
          '${holders.length == 1 ? '' : ' --state <substate>'}`.',
        );
      }
      refuse(resolution.error!);
    }

    return switch (resolution.kind!) {
      .substate => removeSubstate(
        name,
        resolver.appState ??
            refuse('Could not locate app_state.dart to remove a substate.'),
        repo,
        apply: apply,
      ),
      .page => removePage(
        name,
        resolver.routes ??
            refuse('Could not locate app_router.dart to remove a page.'),
        apply: apply,
      ),
    };
  }
}
