// The markdownWorkbench.tables.* settings, read at command time. Every value has
// a defensive fallback to its default: right after an in-place update the
// contributed schema may be inactive and get() returns undefined
// (docs/DECISIONS.md #17).

import * as vscode from 'vscode';

const DEFAULTS = Object.freeze({
  enabled: true,
  enterBehavior: 'newRow',
  tabSelectsCell: true,
  tabAddsRow: true,
  arrowNavigation: true,
  autoAlign: true,
  maxAlignedWidth: 100,
  ambiguousWidth: 'narrow',
  cellLineBreak: '<br>',
  createFromPipe: true,
  continueCheckboxes: true,
  suggestNumericAlign: true,
  previewSort: true,
  pasteAsTable: true,
  validate: true,
});

const ENUMS = {
  enterBehavior: ['newRow', 'nextRowSameColumn'],
  ambiguousWidth: ['narrow', 'wide'],
};

// A value of the default's type (and, for enums, one of the allowed values), else
// the default.
function checked(key, value) {
  const d = DEFAULTS[key];
  if (typeof value !== typeof d) return d;
  if (ENUMS[key] && !ENUMS[key].includes(value)) return d;
  if (key === 'maxAlignedWidth' && !(Number.isInteger(value) && value >= 0))
    return d;
  return value;
}

/**
 * The resolved table settings plus the derived `ambiguousWide` flag.
 * @returns {typeof DEFAULTS & { ambiguousWide: boolean, maxWidth: number }}
 */
function tablesConfig() {
  const cfg = vscode.workspace.getConfiguration('markdownWorkbench');
  const out = {};
  for (const key of Object.keys(DEFAULTS))
    out[key] = checked(key, cfg.get(`tables.${key}`, DEFAULTS[key]));
  out.ambiguousWide = out.ambiguousWidth === 'wide';
  out.maxWidth = out.maxAlignedWidth;
  return out;
}

export { tablesConfig, DEFAULTS };
