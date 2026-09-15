import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import frx = require('../src/frx');

/// The CLI and the extension ship on one tag. What this pins is how the editor
/// tells when they have parted — a Marketplace update on a machine whose binary
/// was never re-installed, or the reverse.

test('the same major.minor is the same pair, whatever the patch', () => {
  assert.strictEqual(frx.compatibility('0.3.5', '0.3.5'), 'same');
  assert.strictEqual(frx.compatibility('0.3.9', '0.3.5'), 'same', 'a patch apart is the same contract');
  assert.strictEqual(frx.compatibility('0.3.5-dev', '0.3.5'), 'same', 'a prerelease suffix is not a difference');
  assert.strictEqual(frx.compatibility('v0.3.5', '0.3.5'), 'same', 'a leading v is spelling');
});

test('a CLI behind the extension is cli-older, whichever component moved', () => {
  assert.strictEqual(frx.compatibility('0.3.5', '0.4.0'), 'cli-older');
  assert.strictEqual(frx.compatibility('0.9.0', '1.0.0'), 'cli-older', 'a major bump outranks a higher minor');
});

test('a CLI ahead of the extension is cli-newer', () => {
  assert.strictEqual(frx.compatibility('0.4.0', '0.3.5'), 'cli-newer');
  assert.strictEqual(frx.compatibility('1.0.0', '0.9.0'), 'cli-newer');
});

test('a version nobody can parse claims nothing', () => {
  // A mismatch that cannot be shown should not be warned about.
  assert.strictEqual(frx.compatibility('unknown', '0.3.5'), 'same');
  assert.strictEqual(frx.compatibility('0.3.5', ''), 'same');
});

test('the extension version comes off the running extension, else its manifest, never a constant', () => {
  assert.strictEqual(
    frx.extensionVersion({ extension: { packageJSON: { version: '9.9.9' } }, extensionPath: '/nowhere' } as never),
    '9.9.9',
  );
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frx-ext-'));
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ version: '1.2.3' }));
  assert.strictEqual(frx.extensionVersion({ extensionPath: dir } as never), '1.2.3');
  assert.strictEqual(frx.extensionVersion({ extensionPath: '/nowhere' } as never), null);
  void vscode;
});
