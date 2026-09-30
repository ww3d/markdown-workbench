// Heading-chain helpers shared by the scroll-spy, the TOC and the top bars: pure,
// allocation-free where they run on the scroll path.

/**
 * Ancestor chain of a heading = itself plus, walking upward, the nearest
 * preceding heading of each strictly smaller level. Returns indices root-first.
 * Handles level jumps (h1 -> h4): it simply takes the nearest shallower
 * heading, whatever its level. Pure; unit-tested.
 */
export function ancestorChain(
  levels: readonly number[],
  index: number,
): number[] {
  const own = levels[index];
  if (index < 0 || own === undefined) return [];
  const chain = [index];
  let minLevel = own;
  for (let i = index - 1; i >= 0 && minLevel > 1; i--) {
    const level = levels[i] ?? minLevel;
    if (level < minLevel) {
      chain.unshift(i);
      minLevel = level;
    }
  }
  return chain;
}

/** Small-array membership test, allocation-free (chains are <= 6 entries). */
export function includesIndex(arr: readonly number[], value: number): boolean {
  for (let k = 0; k < arr.length; k++) if (arr[k] === value) return true;
  return false;
}

/** Whether two index arrays differ; allocation-free (chains are <= 6 entries). */
export function indexArraysDiffer(
  a: readonly number[],
  b: readonly number[],
): boolean {
  if (a.length !== b.length) return true;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return true;
  return false;
}

/** Copy `from` into `into` in place (reuses the target array, no allocation). */
export function copyIndices(from: readonly number[], into: number[]): void {
  into.length = from.length;
  for (let i = 0; i < from.length; i++) into[i] = from[i] ?? 0;
}
