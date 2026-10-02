// Indexed access for tests: `noUncheckedIndexedAccess` types `items[i]` as
// possibly undefined, and a test that reads a missing item should fail by name.

/** The item at `index`; a missing one throws, so the test fails instead of reading `undefined`. */
export function nth<T>(items: readonly T[], index: number): T {
  const item = items[index];
  if (item === undefined) throw new RangeError(`no item at index ${index}`);
  return item;
}
