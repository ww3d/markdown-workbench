// Local declaration for morphdom 2.7.8. Its index.d.ts says `export default`, but the
// package has no "type": "module", so under `module: nodenext` TypeScript reads that
// file as CommonJS and types the default import as the module object (not callable).
// The bundler takes the package's ESM build, whose default export is the function,
// and the test hook stands in the same shape; this declaration states the part the
// render path calls. It wins over the package types (ambient declaration).
declare module 'morphdom' {
  interface MorphDomOptions {
    /** Morph only the children of `fromNode`, keep the node itself. */
    childrenOnly?: boolean;
  }
  /** Morph `fromNode` into the shape of `toNode` in place; returns the morphed node. */
  export default function morphdom(
    fromNode: Node,
    toNode: Node | string,
    options?: MorphDomOptions,
  ): Node;
}
