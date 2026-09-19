// The one collection operation this extension keeps writing by hand.
//
// Grouping into a `Map` of arrays — rows by file, neighbours by node, actions
// by substate — was spelled out in seven places across four files, in two
// different shapes, and a test had pinned the exact text of one of them.
// `Map.groupBy` covers the cases that group a whole list by one key and none of
// the ones that push one item under two keys, so the primitive is the push.

/** Append `value` to the list under `key`, starting the list if there is none. */
export function pushInto<K, V>(into: Map<K, V[]>, key: K, value: V): void {
  const list = into.get(key);
  if (list) list.push(value);
  else into.set(key, [value]);
}
