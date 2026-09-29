// markdown-it-front-matter 0.2.4 (the latest release) ships declarations written against @types/markdown-it 10:
// they import `markdown-it/lib` for `MarkdownIt.PluginWithOptions`, a path markdown-it 15 no longer has. This
// module supplies that one type, so the package's own declarations resolve; nothing imports it at run time.
// parser.ts references this file, so every check scope that reaches the plugin loads it.

declare module 'markdown-it/lib' {
  import type { MarkdownIt as Instance } from 'markdown-it';

  namespace MarkdownIt {
    /** A plugin taking one optional option value, as `md.use(plugin, options)` passes it. */
    type PluginWithOptions<T = unknown> = (md: Instance, options?: T) => void;
  }
  export default MarkdownIt;
}
