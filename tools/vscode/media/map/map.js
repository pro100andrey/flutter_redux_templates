// FRX Map — the page's own script.
//
// Runs inside the webview, against the picture `map.ts` folded out of the
// wiring graph and handed over in the `#picture` JSON block. It used to live
// inside a template literal in map.ts, which put it behind two levels of
// escaping that TypeScript checked neither of: a lone `\n` in a string became
// a real newline in the emitted script and the whole page stopped parsing,
// with nothing anywhere saying why. As a file it is one level, and
// `map.test.ts` parses it as JavaScript.
//
// Plain script, no modules: the webview loads it by URI under a CSP that
// allows exactly this file, by nonce.
const vscode = acquireVsCodeApi();
/** The picture, handed over as a JSON block so a value can never be code. */
const DATA = JSON.parse(document.getElementById('picture').textContent);
/** What a relation does to state, by its kind. */
const CHANGES = new Set(['dispatches', 'writes', 'restores']);
const READS = new Set(['uses', 'reads']);
/** A row with more of them than this starts folded — see fold(). */
const FOLD_OVER = 3;
const boxes = new Map();
/** Every node by id — rows, and the actions and selectors a row owns. */
const nodes = new Map();
/** A row's builder, by the nesting drawn. */
const builderOf = new Map();
(function index(list, builder) {
  for (const n of list) {
    nodes.set(n.id, n);
    if (builder) builderOf.set(n.id, builder);
    index(n.owned || [], null);
    index(n.built || [], n.id);
  }
})(DATA.actors.concat(DATA.state), null);

// What the page remembers across a refresh: which rows are folded and
// which is pinned. Rebuilding the page is how it refreshes, and losing the
// fold you just made to see the refreshed picture would be the page
// undoing your last action.
const remembered = vscode.getState() || {};
const folded = new Set(remembered.folded || []);
let pinned = remembered.pinned && nodes.has(remembered.pinned) ? remembered.pinned : null;
function remember() {
  vscode.setState({ folded: [...folded], pinned });
}

function open(n) {
  if (n && n.file) vscode.postMessage({ type: 'open', file: n.file, line: n.line, column: n.column });
}

function nodeEl(n) {
  const el = document.createElement('div');
  el.className = 'node k-' + n.kind;
  el.dataset.id = n.id;
  // The head is the row's own content; what it builds comes after, inside
  // the same box, so the focus rule can dim one without the other.
  const head = document.createElement('div');
  head.className = 'head';
  el.appendChild(head);
  const t = document.createElement('div');
  t.className = 't';
  t.textContent = n.title;
  if (n.file) t.addEventListener('click', () => open(n));
  else t.style.cursor = 'default';
  const s = document.createElement('div');
  s.className = 's';
  s.textContent = n.subtitle;
  head.append(t, s);

  // Actions and selectors arrive as a count and expand on demand — the whole
  // reason the view stays readable as the app grows.
  if (n.owned && n.owned.length) {
    const wrap = document.createElement('div');
    wrap.className = 'owned';
    const actions = n.owned.filter((o) => o.kind === 'action').length;
    const selectors = n.owned.length - actions;
    const list = document.createElement('ul');
    list.hidden = true;
    for (const o of n.owned) {
      const li = document.createElement('li');
      li.textContent = o.title;
      li.title = o.kind;
      li.addEventListener('click', () => open(o));
      list.appendChild(li);
    }
    let shown = false;
    const label = () =>
      (shown ? '▾ ' : '▸ ') +
      [actions ? actions + (actions === 1 ? ' action' : ' actions') : null,
       selectors ? selectors + (selectors === 1 ? ' selector' : ' selectors') : null]
        .filter(Boolean).join(' · ');
    const count = document.createElement('div');
    count.className = 'count';
    count.textContent = label();
    count.addEventListener('click', () => {
      shown = !shown;
      list.hidden = !shown;
      count.textContent = label();
      draw();
    });
    wrap.append(count, list);
    head.appendChild(wrap);
  }
  // What it builds folds the same way, for the same reason: a screen with
  // ten regions is one row of the overview and ten of the detail. A row
  // with many regions starts folded — the overview is what a reader
  // arrives for — and the choice is remembered.
  if (n.built && n.built.length) {
    if (!remembered.folded && n.built.length > FOLD_OVER) folded.add(n.id);
    const count = n.built.length;
    const toggle = document.createElement('div');
    toggle.className = 'regions';
    const label = () =>
      (folded.has(n.id) ? '▸ ' : '▾ ') + count + (count === 1 ? ' region' : ' regions');
    toggle.textContent = label();
    toggle.addEventListener('click', () => {
      if (folded.has(n.id)) folded.delete(n.id);
      else folded.add(n.id);
      el.classList.toggle('folded', folded.has(n.id));
      toggle.textContent = label();
      remember();
      draw();
    });
    head.appendChild(toggle);
    const built = document.createElement('div');
    built.className = 'built';
    for (const b of n.built) built.appendChild(nodeEl(b));
    el.appendChild(built);
    el.classList.toggle('folded', folded.has(n.id));
  }
  boxes.set(n.id, el);
  return el;
}

function fill(id, list) {
  const rows = document.querySelector('#' + id + ' .rows');
  if (!list.length) {
    const e = document.createElement('div');
    e.className = 'node empty';
    e.textContent = 'none';
    rows.appendChild(e);
    return;
  }
  for (const n of list) rows.appendChild(nodeEl(n));
}

/**
 * Size each column to its widest row, so nothing wraps and nothing spills.
 *
 * A fixed width was right for two flat columns of short names and wrong
 * for everything since: a name three levels deep has lost 72px to indents
 * before it starts, and a narrow panel had flex squeezing the columns
 * until a count broke across two lines. The width is a property of the
 * content — the longest name at its own indent — so it is measured, once,
 * before the first draw. Expanding a row changes heights, not this.
 *
 * The text is measured as text (a Range around it), not as its block: a
 * block is as wide as its container whatever it holds, which is exactly
 * the number that says nothing. The insets on either side are what the
 * enclosing boxes take at that depth, read off the flow layout — with
 * every row unfolded and every list of actions and selectors shown, so
 * neither a fold nor an expand changes the width. The lists count: they
 * start hidden, and a hidden name has no width to measure, so a column
 * sized without them held its heads and spilled an action name past its
 * edge the moment a reader expanded the row.
 */
function fit() {
  const wasFolded = [...document.querySelectorAll('.node.folded')];
  for (const el of wasFolded) el.classList.remove('folded');
  const wasHidden = [...document.querySelectorAll('.owned ul')].filter((ul) => ul.hidden);
  for (const ul of wasHidden) ul.hidden = false;
  for (const id of ['actors', 'state']) {
    const col = document.getElementById(id);
    col.style.width = '';
    const rect = col.getBoundingClientRect();
    let widest = 0;
    const range = document.createRange();
    // Each line's own block gives its insets: a name in a list sits
    // further in than the head above it, behind the list's rule.
    for (const line of col.querySelectorAll('.t, .s, .count, .regions, .owned li')) {
      const box = line.getBoundingClientRect();
      const insets = (box.left - rect.left) + (rect.right - box.right);
      range.selectNodeContents(line);
      widest = Math.max(widest, insets + range.getBoundingClientRect().width);
    }
    // A little air after the longest line; bounded so one absurd name
    // cannot take the panel, and so an empty column still looks like one.
    col.style.width = Math.min(480, Math.max(160, Math.ceil(widest) + 6)) + 'px';
  }
  for (const ul of wasHidden) ul.hidden = true;
  for (const el of wasFolded) el.classList.add('folded');
}

/** The row an id is drawn on: itself, or the folded row it is under. */
function shownAs(id) {
  let at = id;
  let builder = builderOf.get(at);
  while (builder !== undefined) {
    if (folded.has(builder)) at = builder;
    builder = builderOf.get(builder);
  }
  return at;
}

/**
 * The lines to draw: the picture's edges, each end moved to the row it is
 * shown on, and lines that now join the same two rows merged. What a folded
 * region did to state is still there, on its builder — the same fold that
 * puts an action's edges on its substate. A line with both ends on one row
 * is a region relating to its own builder, which the fold has said already.
 */
function lines() {
  const byPair = new Map();
  for (const e of DATA.edges) {
    const from = shownAs(e.from), to = shownAs(e.to);
    if (from === to) continue;
    const key = from < to ? from + '|' + to : to + '|' + from;
    let line = byPair.get(key);
    if (!line) {
      line = { from, to, side: e.side, kinds: new Set(), edges: [] };
      byPair.set(key, line);
    }
    line.edges.push(e);
    for (const r of e.relations) line.kinds.add(r.kind);
  }
  return [...byPair.values()];
}

/**
 * Where along its row each end of each line attaches.
 *
 * A slot per line end, spread along the row's edge so two lines never leave
 * one point, ordered by where the far end lands so a row's fan does not
 * cross itself. By the far end's height on the page rather than its row
 * number: the rows are placed, and a fold changes which rows there are.
 */
function slotsOf(drawn, rectOf) {
  const ends = new Map();
  drawn.forEach((line, index) => {
    for (const node of [line.from, line.to]) {
      const of = ends.get(node);
      if (of) of.push(index);
      else ends.set(node, [index]);
    }
  });
  const centre = (id) => {
    const r = rectOf(id);
    return r.top + r.height / 2;
  };
  const slots = drawn.map(() => ({}));
  for (const [node, indices] of ends) {
    const ordered = indices
      .map((index, arrival) => {
        const line = drawn[index];
        return { index, arrival, y: centre(line.from === node ? line.to : line.from) };
      })
      .sort((a, b) => a.y - b.y || a.arrival - b.arrival);
    ordered.forEach(({ index }, slot) => {
      const end = drawn[index].from === node ? 'from' : 'to';
      slots[index][end] = { slot, of: ordered.length };
    });
  }
  return slots;
}

/** The ids of a row and everything nested under it. */
function idsUnder(n) {
  return [n.id].concat((n.built || []).flatMap(idsUnder));
}

/**
 * Place the shorter column's rows level with what they relate to.
 *
 * Two columns of very different length — thirty-four rows facing nine — put
 * every line on a long diagonal into a short stack, and the lines bundled
 * into a rope beside the taller column. The order was right; the heights
 * were not. Each top-level row of the shorter column is set at the mean
 * height of the rows across from it, kept in order and apart, so a line
 * runs level to the row it names. The taller column stays in flow: it is
 * what the page scrolls by.
 *
 * Runs on every draw, because expanding or folding a row changes the
 * heights it is measured against. Positions are absolute inside the
 * column's own row container, so the measured widths — and so the heights
 * — are those of the flow layout.
 */
function place() {
  const cols = ['actors', 'state'].map((id) => ({
    rows: document.querySelector('#' + id + ' .rows'),
    nodes: DATA[id],
  }));
  for (const c of cols) c.rows.classList.remove('placed');
  const natural = cols.map((c) => c.rows.getBoundingClientRect().height);
  // The shorter column moves. Neither, when the two are within a row of
  // each other: then placing gains nothing and the picture stays a list.
  const shorter = natural[0] < natural[1] ? 0 : natural[1] < natural[0] ? 1 : -1;
  if (shorter < 0 || !cols[shorter].nodes.length) return;
  const moving = cols[shorter];
  const facing = cols[1 - shorter].rows.getBoundingClientRect();

  const centreOf = (id) => {
    const box = boxes.get(shownAs(id));
    if (!box) return null;
    const r = box.getBoundingClientRect();
    return r.top + r.height / 2 - facing.top;
  };
  const wanted = [];
  const GAP = 10;
  let cursor = 0;
  for (const n of moving.nodes) {
    const ids = new Set(idsUnder(n));
    const ys = [];
    for (const e of DATA.edges) {
      if (e.side !== 'across') continue;
      const far = ids.has(e.from) ? e.to : ids.has(e.to) ? e.from : null;
      if (far === null) continue;
      const y = centreOf(far);
      if (y !== null) ys.push(y);
    }
    const box = boxes.get(n.id);
    const height = box.getBoundingClientRect().height;
    // A row with nothing across from it follows the row before it, so the
    // edgeless tail the ordering sank stays a tail.
    const centre = ys.length ? ys.reduce((a, b) => a + b, 0) / ys.length : cursor + height / 2;
    const top = Math.max(cursor, centre - height / 2);
    wanted.push({ box, top, height });
    cursor = top + height + GAP;
  }
  moving.rows.classList.add('placed');
  for (const w of wanted) w.box.style.top = w.top + 'px';
  moving.rows.style.height = (cursor - GAP) + 'px';
}

/**
 * Where a line meets a row: spread along the row's own edge by its slot, so
 * two relations never leave from the same point.
 *
 * Centred on the box's middle, not on a fixed offset from its top. Sizing the
 * fan from the box height while centring it near the top put the first anchor
 * *above* the box — 28px above it, for an expanded substate with eight
 * relations, across the gap and into the row before.
 *
 * boardTop is passed in rather than measured here: this runs twice per line,
 * inside a loop that is appending to the DOM, and reading a rect forces layout.
 */
function anchorY(box, anchor, boardTop) {
  const half = Math.max(0, box.height / 2 - 4);
  const step = anchor.of > 1 ? Math.min(12, (2 * half) / (anchor.of - 1)) : 0;
  const middle = box.top - boardTop + box.height / 2;
  return middle + (anchor.slot - (anchor.of - 1) / 2) * step;
}

/** The row the pointer is on, or null. Held, because a redraw has to restore it. */
let focused = null;
/** What the picture is about right now: the hovered row, else the pinned one. */
const current = () => focused || pinned;

/**
 * Dim everything the current row is not attached to.
 *
 * The cheapest large win in legibility: it changes nothing about what the
 * picture contains, and lets a reader isolate one row's relations without
 * following a line through the ones that cross it.
 *
 * Attached is direct — the rows this one relates to, and the wires between.
 * Not the transitive neighbourhood: "what does this touch" is the question a
 * reader hovers to ask, and following it further is what the graph command's
 * inbound walk is for. Read off the wires as drawn, so a folded row is
 * attached to whatever its regions' lines now reach.
 *
 * Re-applied after every redraw, not only on hover. Expanding a row rebuilds
 * every wire from scratch, and the pointer never leaves the row while you do
 * it — so nothing would fire, and the picture would sit there with the
 * focused row's own relations dimmed along with the rest.
 */
function applyFocus() {
  const board = document.getElementById('board');
  const on = current();
  for (const [id, box] of boxes) box.classList.toggle('pinned', id === pinned);
  if (!on) {
    board.classList.remove('focusing');
    for (const box of boxes.values()) box.classList.remove('lit');
    for (const wire of wires) wire.classList.remove('lit');
    describe(null);
    return;
  }
  // What the row touches was written down when the wires were drawn; this
  // runs on every row the pointer crosses, and used to ask the DOM for every
  // wire each time to find the handful that matter.
  const at = touching.get(on) || { wires: new Set(), rows: new Set() };
  for (const wire of wires) wire.classList.toggle('lit', at.wires.has(wire));
  for (const [id, box] of boxes) box.classList.toggle('lit', id === on || at.rows.has(id));
  board.classList.add('focusing');
  describe(on);
}

/**
 * Say in words what the row's lines mean.
 *
 * The picture gives the shape; this gives the specifics a line cannot carry:
 * which action, through which callback, which selector. Grouped by what the
 * relation does and which way it runs — "changed by" is the first question
 * on arriving at a substate, and it heads the list. Every entry opens the
 * thing it names: the action or selector when the fold hid one, else the
 * row across.
 */
function describe(id) {
  const pane = document.getElementById('pane');
  pane.innerHTML = '';
  pane.classList.toggle('idle', !id);
  if (!id) {
    const hint = document.createElement('div');
    hint.className = 'hint';
    hint.textContent = 'Hover a row to see what its lines mean; click to pin it, Esc to let go.';
    pane.appendChild(hint);
    return;
  }
  const n = nodes.get(id);
  const h = document.createElement('h3');
  h.textContent = n.title;
  h.addEventListener('click', () => open(n));
  const kind = document.createElement('div');
  kind.className = 'kind';
  kind.textContent = n.kind + (n.file ? ' · ' + n.file.split(/[\\/]/).slice(-2).join('/') : '');
  pane.append(h, kind);

  const groups = new Map();
  const add = (group, entry) => {
    const list = groups.get(group) || [];
    list.push(entry);
    groups.set(group, list);
  };
  for (const e of DATA.edges) {
    const far = e.from === id ? e.to : e.to === id ? e.from : null;
    if (far === null) continue;
    for (const r of e.relations) {
      const out = (e.from === id) !== r.reversed;
      const what = r.through ? nodes.get(r.through) : null;
      const entry = { far: nodes.get(far), what, via: r.via, kind: r.kind };
      if (CHANGES.has(r.kind)) add(out ? 'Changes' : 'Changed by', entry);
      else if (READS.has(r.kind)) add(out ? 'Reads' : 'Read by', entry);
      else add(out ? r.kind : r.kind + ' ← from', entry);
    }
  }
  const builder = builderOf.get(id);
  if (builder) add('Built by', { far: nodes.get(builder), what: null, via: '', kind: 'builds' });
  for (const b of n.built || []) add('Builds', { far: b, what: null, via: '', kind: 'builds' });

  const order = ['Changed by', 'Changes', 'Read by', 'Reads'];
  const named = [...groups.keys()].sort(
    (a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99),
  );
  for (const group of named) {
    const h4 = document.createElement('h4');
    h4.textContent = group;
    if (group === 'Changes' || group === 'Changed by') h4.className = 'changes';
    const ul = document.createElement('ul');
    for (const entry of groups.get(group)) {
      const li = document.createElement('li');
      // The row across, then the action or selector behind the line when
      // the fold hid one, then what triggers it.
      li.textContent = entry.far.title + (entry.what ? ' · ' + entry.what.title : '');
      if (entry.via) {
        const via = document.createElement('span');
        via.className = 'via';
        via.textContent = ' ' + entry.via;
        li.appendChild(via);
      }
      li.addEventListener('click', () => open(entry.what || entry.far));
      ul.appendChild(li);
    }
    pane.append(h4, ul);
  }
}

function focusOnHover() {
  const board = document.getElementById('board');
  // One listener on the board, resolving to the innermost row under the
  // pointer — a row nested in another is inside its builder's box, and a
  // per-row enter/leave pair would light the builder on the way in and
  // let go of everything on the way out. Moving into the gap between rows
  // resolves to no row, which is the letting go — unless a row is pinned,
  // which is what pinning is for. A line is not a row: crossing one keeps
  // the focus, so its own tooltip can be read.
  board.addEventListener('mouseover', (event) => {
    if (event.target.closest('svg')) return;
    const row = event.target.closest('.node');
    const id = row && boxes.has(row.dataset.id) ? row.dataset.id : null;
    if (id === focused) return;
    focused = id;
    applyFocus();
  });
  // Away from the panel entirely — clicking a title opens a file over it,
  // and a hidden webview is retained rather than unloaded, so the board
  // would come back still dimmed.
  board.addEventListener('pointerleave', () => {
    focused = null;
    applyFocus();
  });
  // And off the board without the pointer moving: scrolling slides the
  // rows out from under it, and the browser then says where the pointer
  // is by a mouseover on whatever is there now — which is not the board,
  // so the board's own listeners never hear of it.
  document.addEventListener('mouseover', (event) => {
    if (focused && !board.contains(event.target)) {
      focused = null;
      applyFocus();
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      focused = null;
      applyFocus();
    }
  });
  // A click on a row's own surface pins it: the focus stays when the pointer
  // goes, so the pane can be read and the picture scrolled with one row's
  // relations held lit. The title, counts and lists keep their own clicks.
  board.addEventListener('click', (event) => {
    if (event.target.closest('.t, .count, .regions, .owned li, svg')) return;
    const row = event.target.closest('.node');
    const id = row && boxes.has(row.dataset.id) ? row.dataset.id : null;
    if (!id) return;
    pinned = pinned === id ? null : id;
    remember();
    applyFocus();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !pinned) return;
    pinned = null;
    remember();
    applyFocus();
  });
}

/** The wires as drawn, in order, for the focus to light without asking the DOM. */
let wires = [];
/** By row id: the wires that touch the row, and the rows at their far ends. */
let touching = new Map();

/**
 * Redraw the wires against the current layout (expanding a node moves it).
 *
 * Reads before writes, in that order and once. Every box's rect is taken a
 * single time, and the paths are built off the document and attached in one
 * append at the end: reading a rect after a write to the document makes the
 * browser lay the page out again first, and the loop used to write a path
 * and then read the next line's two rects — a layout per line, on every
 * expand.
 */
function draw() {
  place();
  const svg = document.getElementById('wires');
  const boardEl = document.getElementById('board');
  const board = boardEl.getBoundingClientRect();
  // How far a same-column line may bulge into the margin: the margin is
  // narrower on a narrow panel, and a line past it runs off the page.
  const channel = parseFloat(getComputedStyle(boardEl).paddingLeft) - 8;
  // A line meets a column at the column's edge, not the row's: a nested row
  // is indented inside its builder's box, and a line into its own edge would
  // cut across the box that holds it.
  const colOf = (id) => document.getElementById(id).getBoundingClientRect();
  const actorsCol = colOf('actors'), stateCol = colOf('state');
  const edgeX = (id, side) =>
    (id.startsWith('substate:') ? stateCol : actorsCol)[side] - board.left;
  const rects = new Map();
  const rectOf = (id) => {
    let r = rects.get(id);
    if (!r) rects.set(id, (r = boxes.get(id).getBoundingClientRect()));
    return r;
  };
  const drawn = lines();
  const slots = slotsOf(drawn, rectOf);
  const fragment = document.createDocumentFragment();
  wires = [];
  touching = new Map();
  const touch = (id, wire, far) => {
    let at = touching.get(id);
    if (!at) touching.set(id, (at = { wires: new Set(), rows: new Set() }));
    at.wires.add(wire);
    at.rows.add(far);
  };
  drawn.forEach((line, i) => {
    const ra = rectOf(line.from);
    const rb = rectOf(line.to);
    const y1 = anchorY(ra, slots[i].from, board.top);
    const y2 = anchorY(rb, slots[i].to, board.top);

    let d;
    if (line.side === 'across') {
      // A curve, not a chord: two relations that leave one row a few pixels
      // apart and land far apart stay apart the whole way, instead of
      // converging into one stroke near each end.
      const leftFirst = !line.from.startsWith('substate:');
      const x1 = edgeX(line.from, leftFirst ? 'right' : 'left');
      const x2 = edgeX(line.to, leftFirst ? 'left' : 'right');
      const bend = (x2 - x1) * 0.45;
      d = 'M ' + x1 + ' ' + y1 +
          ' C ' + (x1 + bend) + ' ' + y1 +
          ', ' + (x2 - bend) + ' ' + y2 +
          ', ' + x2 + ' ' + y2;
    } else {
      // Out into the margin on its own side and back, rather than across the
      // canvas. The bulge grows with the vertical distance, so an edge that
      // spans many rows arcs wider than one between neighbours and the two
      // do not lie on top of each other.
      const left = line.side === 'left';
      const x1 = edgeX(line.from, left ? 'left' : 'right');
      const x2 = edgeX(line.to, left ? 'left' : 'right');
      const reach = Math.min(channel, 16 + Math.abs(y2 - y1) * 0.25) * (left ? -1 : 1);
      d = 'M ' + x1 + ' ' + y1 +
          ' C ' + (x1 + reach) + ' ' + y1 +
          ', ' + (x2 + reach) + ' ' + y2 +
          ', ' + x2 + ' ' + y2;
    }

    const wire = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    // Every kind the pair relates by, so a line that is navigation among
    // other things still draws dashed — and 'changes' when any of them
    // changes state, which is the colour.
    const kinds = [...line.kinds];
    const changes = kinds.some((k) => CHANGES.has(k));
    wire.setAttribute('class', 'wire ' + kinds.join(' ') + (changes ? ' changes' : ''));
    wire.dataset.from = line.from;
    wire.dataset.to = line.to;
    wire.setAttribute('d', d);
    const title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
    // One relation per line, so a bundled line's tooltip reads as a list.
    title.textContent = line.edges
      .flatMap((e) => e.relations.map((r) =>
        (r.reversed ? '← ' : '') + r.kind +
        (r.through && nodes.has(r.through) ? ' ' + nodes.get(r.through).title : '') +
        (r.via ? ' (' + r.via + ')' : '')))
      .join('\n');
    wire.appendChild(title);
    fragment.appendChild(wire);
    wires.push(wire);
    touch(line.from, wire, line.to);
    touch(line.to, wire, line.from);
  });
  svg.setAttribute('width', board.width);
  svg.setAttribute('height', board.height);
  svg.replaceChildren(fragment);
  applyFocus();
}

fill('actors', DATA.actors);
fill('state', DATA.state);
fit();
draw();
window.addEventListener('resize', draw);
focusOnHover();

// A diagram reads as exhaustive, so it says where its own edges stop.
if (DATA.gaps.length) {
  const box = document.createElement('div');
  box.className = 'gaps';
  const h = document.createElement('h2');
  h.textContent = '⚠ ' + DATA.gaps.length + ' unresolved edge(s)';
  box.appendChild(h);
  for (const g of DATA.gaps) {
    const what = document.createElement('div');
    const code = document.createElement('code');
    code.textContent = g.what;
    what.appendChild(code);
    box.appendChild(what);
    if (g.at) {
      const at = document.createElement('div');
      at.className = 'at';
      const file = document.createElement('code');
      file.textContent = g.at;
      at.appendChild(file);
      box.appendChild(at);
    }
    const why = document.createElement('p');
    why.className = 'why';
    why.textContent = g.why;
    box.appendChild(why);
  }
  document.getElementById('gaps').appendChild(box);
}

document.getElementById('refresh').addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
