// AUTO-GENERATED — DO NOT EDIT.
// Produced by `cd tools && make contract`.
//
// The CLI is the author of everything here: the `--kind` sets
// come off each command's own ArgParser, the marker off
// FrxWorkspace, the fix ids off the sealed Fix hierarchy. Edit
// the Dart and re-run; contract_freshness_test.dart fails on a
// stale copy, so `make check` and CI catch it.

/**
 * The file `frx` keys on to decide where a project begins.
 *
 * Slash-separated, as the CLI states it. Join it with the
 * platform separator before touching the filesystem.
 */
export const MARKER_PATH = 'app/lib/navigation/app_router.dart';

/** Every `--kind` the CLI accepts, by the artifact it makes. */
export const KINDS = {
  substate: ['value', 'search', 'table'],
  action: ['sync', 'async', 'waiting'],
  widget: ['field', 'choice', 'action', 'view', 'container'],
  nav: ['push', 'replace', 'navigate'],
  remove: ['substate', 'page', 'action', 'model', 'widget', 'connector', 'service'],
  rename: ['substate', 'page'],
} as const;

/** The values one `--kind` accepts, as a union. */
export type Kind<K extends keyof typeof KINDS> = (typeof KINDS)[K][number];

/**
 * The remedies `frx doctor --fix` can apply.
 *
 * The wire values the editor keys its quick-fixes on —
 * additive only, since an older extension has to keep
 * working against a newer CLI.
 */
export const FIX_IDS = ['build_runner', 'orphan', 'flow-docs'] as const;

export type FixId = (typeof FIX_IDS)[number];
