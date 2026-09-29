// "Save As" on the candidate (REQ-59, docs/DECISIONS.md #48): for a scheme
// that is neither `file` nor `vscodeUserData` VS Code opens its simplified
// dialog inside the window, which resolves the default target through our
// FileSystemProvider. The case checks that the target it asks for is the
// candidate URI under our scheme, that nothing reaches the disk, and cancels.
// A second case takes the dialog's "Show Local" path to a local target.

const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vscode = require('vscode');
const h = require('./harness');
const { schemeBackups } = require('../guard/scenario');

const OPS = [
  'stat',
  'readDirectory',
  'readFile',
  'writeFile',
  'createDirectory',
  'delete',
  'rename',
];
const WRITES = ['writeFile', 'createDirectory', 'delete', 'rename'];
const calls = [];

// The test runner shares the extension's vscode API object, so wrapping the
// registration (before the extension activates) records every call VS Code
// makes into the page provider, without a test hook in src/.
const register = vscode.workspace.registerFileSystemProvider;
vscode.workspace.registerFileSystemProvider = function (scheme, provider, o) {
  if (scheme === h.SCHEME) {
    for (const op of OPS) {
      const orig = provider[op];
      provider[op] = function (uri, ...rest) {
        calls.push({ op, uri: uri.toString() });
        return orig.call(this, uri, ...rest);
      };
    }
  }
  return register.call(this, scheme, provider, o);
};

// name -> content of every file in the workspace copy.
function snapshot(dir) {
  const out = {};
  for (const e of fs.readdirSync(dir, { recursive: true, withFileTypes: true }))
    if (e.isFile()) {
      const full = path.join(e.parentPath ?? e.path, e.name);
      out[path.relative(dir, full)] = fs.readFileSync(full, 'utf8');
    }
  return out;
}

h.test(
  'Save As on the candidate asks for a target under the candidate scheme and writes nothing',
  async () => {
    await h.openFixture('notes.md');
    const { candidateUri } = await h.compare(
      '## Usage\n\nRun it three times.\n',
    );
    await vscode.commands.executeCommand(
      'workbench.action.compareEditor.focusPrimarySide',
    );
    const disk = snapshot(process.env.MDWB_WORKSPACE);
    const backups = schemeBackups(process.env.MDWB_USER_DATA_DIR);
    calls.length = 0;
    const pending = vscode.commands.executeCommand(
      'workbench.action.files.saveAs',
    );
    // The dialog lists the default target's folder once it has resolved it.
    await h.waitFor(
      () => calls.some((c) => c.op === 'readDirectory'),
      'the Save As dialog to read the candidate folder',
      10000,
    );
    await h.sleep(200); // lets the dialog finish resolving before the cancel
    const seen = calls.map((c) => `${c.op} ${c.uri}`);
    h.measure(`saveAsProviderCalls(${vscode.version})`, seen);
    await vscode.commands.executeCommand('workbench.action.closeQuickOpen');
    await pending;
    const folder = candidateUri.with({
      path: path.posix.dirname(candidateUri.path),
    });
    assert.ok(
      calls.every((c) => c.uri.startsWith(`${h.SCHEME}:`)),
      `a call outside the scheme: ${seen.join(', ')}`,
    );
    assert.ok(
      calls.some((c) => c.op === 'stat' && c.uri === candidateUri.toString()),
      `no stat of the candidate ${candidateUri}: ${seen.join(', ')}`,
    );
    assert.ok(
      calls.some(
        (c) => c.op === 'readDirectory' && c.uri === folder.toString(),
      ),
      `no listing of the candidate folder ${folder}: ${seen.join(', ')}`,
    );
    assert.deepStrictEqual(
      calls.filter((c) => WRITES.includes(c.op)),
      [],
      'no write into the provider',
    );
    assert.deepStrictEqual(snapshot(process.env.MDWB_WORKSPACE), disk);
    assert.deepStrictEqual(
      schemeBackups(process.env.MDWB_USER_DATA_DIR),
      backups,
    );
    assert.ok(h.clipboardDiffTab(), 'the diff stays open after the cancel');
  },
);

// "Show Local" in the dialog above runs the same save as this command: Save As
// restricted to the local file system (simpleFileDialog.ts, onDidCustom and
// SaveLocalFileCommand). With the simplified dialog for local files too, the
// case can accept the proposed local target in the window.
const SAVE_LOCAL = 'workbench.action.files.saveLocalFile';

h.test(
  'Save As via "Show Local" writes the candidate to the accepted local target, and nothing else',
  async () => {
    const dialogs = vscode.workspace.getConfiguration('files');
    await dialogs.update(
      'simpleDialog.enable',
      true,
      vscode.ConfigurationTarget.Global,
    );
    let written;
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-local-'));
    await dialogs.update(
      'dialog.defaultPath',
      target,
      vscode.ConfigurationTarget.Global,
    );
    try {
      await h.openFixture('notes.md');
      const { candidateUri } = await h.compare(
        '## Usage\n\nRun it four times.\n',
      );
      const text = Buffer.from(
        await vscode.workspace.fs.readFile(candidateUri),
      ).toString('utf8');
      await vscode.commands.executeCommand(
        'workbench.action.compareEditor.focusPrimarySide',
      );
      const disk = snapshot(process.env.MDWB_WORKSPACE);
      const pending = vscode.commands.executeCommand(SAVE_LOCAL);
      await h.sleep(1500); // the local dialog resolves its proposed target
      assert.deepStrictEqual(
        snapshot(process.env.MDWB_WORKSPACE),
        disk,
        'nothing is written before the target is accepted',
      );
      await vscode.commands.executeCommand(
        'workbench.action.acceptSelectedQuickOpenItem',
      );
      const settled = await Promise.race([
        pending.then(() => true),
        h.sleep(10000).then(() => false),
      ]);
      if (!settled)
        await vscode.commands.executeCommand('workbench.action.closeQuickOpen');
      assert.ok(settled, 'the local Save As finished after the accept');
      written = await h.waitFor(
        () => {
          const [name] = fs.readdirSync(target);
          return name && vscode.Uri.file(path.join(target, name));
        },
        'the saved local file',
        10000,
      );
      h.measure(
        `showLocalTarget(${vscode.version})`,
        path.basename(written.fsPath),
      );
      assert.strictEqual(fs.readFileSync(written.fsPath, 'utf8'), text);
      assert.deepStrictEqual(
        snapshot(target),
        { [path.basename(written.fsPath)]: text },
        'exactly the accepted target is new in its folder',
      );
      assert.deepStrictEqual(
        snapshot(process.env.MDWB_WORKSPACE),
        disk,
        'nothing else is written',
      );
    } finally {
      for (const key of ['simpleDialog.enable', 'dialog.defaultPath'])
        await dialogs.update(key, undefined, vscode.ConfigurationTarget.Global);
      fs.rmSync(target, { recursive: true, force: true });
      await vscode.commands.executeCommand('workbench.action.closeAllEditors');
      if (written) fs.rmSync(written.fsPath, { force: true });
    }
  },
);
