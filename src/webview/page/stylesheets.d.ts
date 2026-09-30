// Every webview module imports its own stylesheet for the side effect only (the
// bundler collects them into dist/webview.css); TypeScript needs to know that such
// an import resolves. No binding is exported - the import has no value.
declare module '*.css';
