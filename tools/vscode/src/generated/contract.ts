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
  'substate': ['value', 'search', 'table'],
  'action': ['sync', 'async', 'waiting'],
  'widget': ['field', 'choice', 'action', 'view', 'container'],
  'nav': ['push', 'replace', 'navigate'],
  'remove': ['substate', 'page', 'action', 'model', 'widget', 'connector', 'service'],
  'rename': ['substate', 'page'],
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

/**
 * What a non-zero `frx` exit means.
 *
 * The editor keys on both: `scaffold.ts` offers an overwrite
 * on FAILURE, `artifact.ts` raises a disambiguation picker on
 * USAGE. sysexits.h values, as a shell expects.
 */
export const EXIT = {
  usage: 64,
  failure: 70,
} as const;

/**
 * The optional workspace members `add-package` creates.
 *
 * `dir` is the argument the command takes and the folder it
 * writes; `summary` is the CLI's own one-liner for it.
 */
export const PACKAGES = [
  { dir: 'models', summary: 'Shared freezed models and converters' },
  { dir: 'http_client', summary: 'Dio + Retrofit API clients and interceptors' },
  { dir: 'storage', summary: 'Key-value persistence behind BaseKeyValueStorage' },
] as const;

/** One optional package's directory, as a union. */
export type PackageDir = (typeof PACKAGES)[number]['dir'];

/**
 * Where the conventional files live, slash-separated and
 * relative to the repo root.
 *
 * Join with the platform separator before touching disk.
 */
export const LAYOUT = {
  pages: 'ui/lib/pages',
  connectors: 'app/lib/connectors',
  redux: 'business/lib/redux',
  pageSuffix: '_page.dart',
  connectorSuffix: '_page_connector.dart',
  stateSuffix: '_state.dart',
} as const;

/**
 * What the CLI's `Casing` answers, for `naming.test.ts`.
 *
 * `naming.ts` re-implements the conversion because an
 * algorithm is not emittable as data. This is how the two
 * are held together: snake_case in, since that is what the
 * editor is ever handed.
 */
export const NAMING_CASES = [
  { input: 'my_profile', camel: 'myProfile', pascal: 'MyProfile', snake: 'my_profile' },
  { input: 'log_in', camel: 'logIn', pascal: 'LogIn', snake: 'log_in' },
  { input: 'a', camel: 'a', pascal: 'A', snake: 'a' },
  { input: 'theme', camel: 'theme', pascal: 'Theme', snake: 'theme' },
  { input: 'user2_fa', camel: 'user2Fa', pascal: 'User2Fa', snake: 'user2_fa' },
  { input: 'my__profile', camel: 'myProfile', pascal: 'MyProfile', snake: 'my_profile' },
  { input: 'log_in_with_email', camel: 'logInWithEmail', pascal: 'LogInWithEmail', snake: 'log_in_with_email' },
] as const;
