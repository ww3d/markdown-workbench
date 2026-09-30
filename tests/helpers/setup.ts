// Preloaded into every test process (`node --import ./tests/helpers/setup.ts --test ...`): registers the
// module hooks before the first test file resolves its imports, so a static `import 'vscode'`
// in src/ already reaches the mock, and the webview modules load without a bundler. The
// bundler's build id is stood in by a fixed global.
import './build-id.ts';
import './vscode-hooks.ts';
import './webview-hooks.ts';
