// Preloaded into every test process (`node --import ./tests/setup.ts --test ...`): registers the
// module hooks before the first test file resolves its imports, so a static `import 'vscode'`
// in src/ already reaches the mock, and the webview modules load without a bundler. The
// bundler's build id is stood in by a fixed global.
import './helpers/build-id.ts';
import './helpers/vscode-hooks.ts';
import './helpers/webview-hooks.ts';
