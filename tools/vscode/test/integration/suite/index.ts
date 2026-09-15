// The in-host entry point `@vscode/test-electron` calls: it finds the compiled
// `*.test.js` beside itself and runs them under mocha, which is the runner the
// host harness expects (it hands over control and waits on the returned
// promise; `node --test` has no such seam).
import * as fs from 'fs';
import * as path from 'path';

import Mocha = require('mocha');

export function run(): Promise<void> {
  const mocha = new Mocha({ ui: 'tdd', color: true, timeout: 60_000 });
  for (const file of fs.readdirSync(__dirname)) {
    if (file.endsWith('.test.js')) mocha.addFile(path.join(__dirname, file));
  }
  return new Promise((resolve, reject) => {
    try {
      mocha.run((failures) => (failures > 0 ? reject(new Error(`${failures} test(s) failed`)) : resolve()));
    } catch (error) {
      reject(error);
    }
  });
}
