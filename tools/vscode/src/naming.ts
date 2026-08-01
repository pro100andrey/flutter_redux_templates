// Casing conversions the extension applies to frx's snake_case folder names and
// generated PascalCase class names. Pure string logic (no vscode / fs), so it's
// unit-testable on its own and mirrors the CLI's `Casing` util — the extension
// keeps its naming rules in one place instead of re-spelling them per provider.

/** `my_profile` → `myProfile` (the AppState field for a substate folder). */
export function camelOf(snake: string): string {
  return snake
    .split('_')
    .filter(Boolean) // a stray `__` must not yield an empty segment
    .map((w, i) => (i === 0 ? w : w[0].toUpperCase() + w.slice(1)))
    .join('');
}

/** `my_profile` → `MyProfile` (matches how frx names generated classes). */
export function pascalOf(snake: string): string {
  return snake
    .split('_')
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join('');
}

/** `LogInRoute` → `LogIn` when `suffix` trails, else the string unchanged. */
export function stripSuffix(str: string, suffix: string | null | undefined): string {
  return suffix && str.endsWith(suffix) ? str.slice(0, -suffix.length) : str;
}

/**
 * Strip the affix `frx which` reported, turning a freshly-typed token back into
 * a base name: drop a trailing `suffix` and/or a leading `prefix` when present.
 * Never collapses to empty.
 */
export function stripAffix(
  name: string,
  suffix: string | null | undefined,
  prefix: string | null | undefined,
): string {
  let base = name;
  if (suffix && base.endsWith(suffix)) base = base.slice(0, -suffix.length);
  if (prefix && base.startsWith(prefix)) base = base.slice(prefix.length);
  return base || name;
}
