// Node has the WebAssembly global, but TypeScript declares its namespace only in the DOM and web-worker
// libraries, which the host check scope must not load (REQ-006). Shiki's declarations name these members
// for the loader options of its Oniguruma engine; the host runs the JavaScript regex engine instead.

declare namespace WebAssembly {
  /** A value an import object may hold. */
  type ImportValue = unknown;
  /** An instantiated module. */
  interface Instance {
    readonly exports: Record<string, unknown>;
  }
  /** What instantiating a byte source resolves to. */
  interface WebAssemblyInstantiatedSource {
    instance: Instance;
    module: unknown;
  }
}
