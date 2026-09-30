// Preview readability config (#25 follow-up): text selection, the batch gesture,
// the row cursor and the table sort button.

import type { ConfigMessage } from '../protocol.ts';

/** The readability flags in effect. */
export interface PreviewCfg {
  readonly textSelection: boolean;
  readonly taskBatchSelect: 'checkbox' | 'row';
  readonly taskRowTextCursor: boolean;
  readonly previewSort: boolean;
}

/**
 * The flags in effect. Defaults reproduce #25: text is selectable, the batch
 * gesture lives on the checkbox, the row keeps the pointer hand. The host
 * overwrites these on every 'config' message.
 */
export let previewCfg: PreviewCfg = {
  textSelection: true,
  taskBatchSelect: 'checkbox',
  taskRowTextCursor: false,
  previewSort: true,
};

/**
 * Store the readability flags (safe defaults if a field is absent) and reflect
 * them as body classes the stylesheet keys off: mw-no-text-select locks
 * selection, mw-task-text-cursor swaps the row's pointer hand for a text
 * caret. The cursor swap only applies while text is selectable.
 */
export function applyPreviewCfg(cfg: ConfigMessage): void {
  previewCfg = {
    textSelection: cfg.textSelection !== false,
    taskBatchSelect: cfg.taskBatchSelect === 'row' ? 'row' : 'checkbox',
    taskRowTextCursor: cfg.taskRowTextCursor === true,
    previewSort: cfg.tables?.previewSort !== false,
  };
  document.body.classList.toggle('mw-preview-sort', previewCfg.previewSort);
  document.body.classList.toggle(
    'mw-no-text-select',
    previewCfg.textSelection === false,
  );
  document.body.classList.toggle(
    'mw-task-text-cursor',
    previewCfg.textSelection !== false && previewCfg.taskRowTextCursor === true,
  );
}
