// --- Content section folding (#44 P2) ---------------------------------------
//
// Fold state keyed by heading id, preserved across re-renders (re-applied after
// each render, like VS Code folding survives edits). A heading's section is every
// following block up to the next heading of the same or a higher level; folding
// hides those blocks. Reachable from the document fold control and (P2 part 2) the
// sticky-row twistie, kept in sync. The height change is absorbed by re-running the
// existing layout refresh - the minimap and scroll-sync logic itself is untouched,
// only its refresh is triggered. This file holds the fold state and the pure
// section logic; fold.ts applies it, refresh.ts re-measures after it.

import { content } from '../page/content.ts';

/** Ids of the folded headings; survives re-renders. */
export const foldedIds = new Set<string>();

/**
 * The top-level content blocks currently folded away, maintained by applyFolds.
 * Everything that needs "is this element visible?" reads THIS instead of
 * offsetParent: offsetParent is a layout read, so asking for it right after the
 * fold's class writes forced a synchronous full-document layout inside the click
 * handler. The click path now only writes and lets the browser lay out once.
 */
export const hiddenBlocks = new Set<Element>();

/**
 * Whether an element sits inside a folded-away block: walk up to the top-level
 * block that owns it (a direct child of #content - that is what a fold hides).
 * Pure DOM traversal, no layout read. A nested heading (inside a list or a
 * blockquote) resolves through its ancestors, which is what the offsetParent read
 * used to cover.
 */
export function isInHiddenBlock(el: Element): boolean {
  if (!hiddenBlocks.size) return false;
  let node: Element | null = el;
  while (node && node !== content) {
    if (hiddenBlocks.has(node)) return true;
    node = node.parentElement;
  }
  return false;
}

/** The fields of a content block the pure section logic reads. */
export interface SectionBlock {
  /** Heading level 1-6, 0 for a non-heading block. */
  readonly level: number;
  readonly id: string;
}

/** A direct child of #content with its heading level (0 = non-heading) and id. */
export interface ContentBlock extends SectionBlock {
  readonly el: Element;
}

/**
 * Which blocks are hidden given the folded heading ids: a block is hidden iff it
 * sits inside a folded heading's section, with nesting handled by a level stack (a
 * folded ancestor hides a folded descendant's blocks too). The folded heading
 * itself stays visible (it carries the collapsed chevron). Pure; unit-tested.
 */
export function computeFoldHidden(
  blocks: readonly SectionBlock[],
  folded: ReadonlySet<string>,
): boolean[] {
  const hidden = new Array<boolean>(blocks.length);
  const stack: number[] = []; // levels of folded headings whose section we are currently inside
  for (const [i, block] of blocks.entries()) {
    const level = block.level;
    if (level > 0) {
      while (stack.length && (stack.at(-1) ?? 0) >= level) stack.pop();
      hidden[i] = stack.length > 0;
      if (folded.has(block.id)) stack.push(level);
    } else {
      hidden[i] = stack.length > 0;
    }
  }
  return hidden;
}

/**
 * Whether the heading at index i is foldable: it has a following block before the
 * next heading of the same or a higher level (an empty section is not foldable).
 * Pure; unit-tested.
 */
export function isFoldable(
  blocks: readonly SectionBlock[],
  i: number,
): boolean {
  const next = blocks[i + 1];
  const own = blocks[i];
  return !!next && !!own && !(next.level > 0 && next.level <= own.level);
}

/**
 * The direct children of a root (defaults to #content) as {el, level (0 =
 * non-heading), id} in order. Takes a root so the render path can post-process an
 * off-DOM incoming tree the same way before morphing it in.
 */
export function contentBlocks(root?: Element): ContentBlock[] {
  const scope = root || content;
  const kids = scope.children ? [...scope.children] : [];
  return kids.map((el) => {
    const m = /^H([1-6])$/.exec(el.tagName || '');
    return { el, level: m ? Number(m[1]) : 0, id: el.id };
  });
}

/**
 * Map a heading id to the id navigation should actually land on. A folded-away
 * heading is display:none - its rect is 0, so scrolling to it walked the view
 * upward on every click (#44 P2). Such an id is redirected to the section header
 * it visually collapsed into: the outermost folded ancestor that is itself still
 * visible. A visible id (or one that is not a content heading) is returned
 * unchanged. Reads the live fold set; the block scan is unit-tested via
 * contentBlocks/computeFoldHidden.
 */
export function visibleFoldAnchor(id: string): string {
  if (!id) return id;
  const blocks = contentBlocks();
  const idx = blocks.findIndex((b) => b.id === id);
  if (idx < 0) return id; // not a direct content heading -> leave as-is
  const hidden = computeFoldHidden(blocks, foldedIds);
  if (!hidden[idx]) return id; // already visible
  for (let i = idx - 1; i >= 0; i--) {
    const b = blocks[i];
    if (b && b.level > 0 && !hidden[i] && foldedIds.has(b.id)) return b.id;
  }
  return id;
}

/**
 * Prepend a fold control to every foldable heading (idempotent: skips one that
 * already has it, so a re-render does not stack controls).
 */
export function injectFoldToggles(root?: Element): void {
  const blocks = contentBlocks(root);
  for (const [i, b] of blocks.entries()) {
    if (b.level === 0 || !isFoldable(blocks, i)) continue;
    if (b.el.querySelector?.('.mw-fold-toggle')) continue;
    const t = document.createElement('span');
    t.className = 'mw-fold-toggle codicon codicon-chevron-right';
    t.setAttribute('role', 'button');
    t.setAttribute('aria-hidden', 'true');
    t.dataset.foldId = b.id;
    if (b.el.insertBefore) b.el.insertBefore(t, b.el.firstChild);
  }
}

/** Hide or show one content block (or its minimap clone) as folded away. */
export function setBlockHidden(el: Element | undefined, hidden: boolean): void {
  if (el?.classList) el.classList.toggle('mw-fold-hidden', hidden);
}
