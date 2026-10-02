// The markdownWorkbench.tables.* settings, read at command time. Every value has
// a defensive fallback to its default: right after an in-place update the
// contributed schema may be inactive and get() returns undefined
// (docs/DECISIONS.md #17).

import * as vscode from 'vscode';

/** What Enter does at the end of a body row. */
export type EnterBehavior = 'newRow' | 'nextRowSameColumn';

/** Whether cell widths are counted with East Asian ambiguous characters narrow or wide. */
export type AmbiguousWidth = 'narrow' | 'wide';

/** The `markdownWorkbench.tables.*` settings, one field per setting. */
export interface TablesSettings {
  readonly enabled: boolean;
  readonly enterBehavior: EnterBehavior;
  readonly tabSelectsCell: boolean;
  readonly tabAddsRow: boolean;
  readonly arrowNavigation: boolean;
  readonly autoAlign: boolean;
  readonly maxAlignedWidth: number;
  readonly ambiguousWidth: AmbiguousWidth;
  readonly cellLineBreak: string;
  readonly createFromPipe: boolean;
  readonly continueCheckboxes: boolean;
  readonly suggestNumericAlign: boolean;
  readonly previewSort: boolean;
  readonly pasteAsTable: boolean;
  readonly validate: boolean;
}

/** The resolved settings plus the two values the formatter reads under other names. */
export interface TablesConfig extends TablesSettings {
  readonly ambiguousWide: boolean;
  readonly maxWidth: number;
}

/** Default of every setting; `package.json` declares the same values. */
const DEFAULTS: TablesSettings = Object.freeze({
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

type BooleanKey = {
  [K in keyof TablesSettings]: TablesSettings[K] extends boolean ? K : never;
}[keyof TablesSettings];

// A value of the default's type, else the default.
function flag(cfg: vscode.WorkspaceConfiguration, key: BooleanKey): boolean {
  const value = cfg.get<unknown>(`tables.${key}`, DEFAULTS[key]);
  return typeof value === 'boolean' ? value : DEFAULTS[key];
}

function enterBehavior(cfg: vscode.WorkspaceConfiguration): EnterBehavior {
  const value = cfg.get<unknown>(
    'tables.enterBehavior',
    DEFAULTS.enterBehavior,
  );
  return value === 'newRow' || value === 'nextRowSameColumn'
    ? value
    : DEFAULTS.enterBehavior;
}

function ambiguousWidth(cfg: vscode.WorkspaceConfiguration): AmbiguousWidth {
  const value = cfg.get<unknown>(
    'tables.ambiguousWidth',
    DEFAULTS.ambiguousWidth,
  );
  return value === 'narrow' || value === 'wide'
    ? value
    : DEFAULTS.ambiguousWidth;
}

function maxAlignedWidth(cfg: vscode.WorkspaceConfiguration): number {
  const value = cfg.get<unknown>(
    'tables.maxAlignedWidth',
    DEFAULTS.maxAlignedWidth,
  );
  return typeof value === 'number' && Number.isInteger(value) && value >= 0
    ? value
    : DEFAULTS.maxAlignedWidth;
}

function cellLineBreak(cfg: vscode.WorkspaceConfiguration): string {
  const value = cfg.get<unknown>(
    'tables.cellLineBreak',
    DEFAULTS.cellLineBreak,
  );
  return typeof value === 'string' ? value : DEFAULTS.cellLineBreak;
}

/**
 * The resolved table settings plus the derived `ambiguousWide` flag. Every value
 * falls back to its default when unset, of the wrong type or outside its enum.
 */
function tablesConfig(): TablesConfig {
  const cfg = vscode.workspace.getConfiguration('markdownWorkbench');
  const width = ambiguousWidth(cfg);
  const maxWidth = maxAlignedWidth(cfg);
  return {
    enabled: flag(cfg, 'enabled'),
    enterBehavior: enterBehavior(cfg),
    tabSelectsCell: flag(cfg, 'tabSelectsCell'),
    tabAddsRow: flag(cfg, 'tabAddsRow'),
    arrowNavigation: flag(cfg, 'arrowNavigation'),
    autoAlign: flag(cfg, 'autoAlign'),
    maxAlignedWidth: maxWidth,
    ambiguousWidth: width,
    cellLineBreak: cellLineBreak(cfg),
    createFromPipe: flag(cfg, 'createFromPipe'),
    continueCheckboxes: flag(cfg, 'continueCheckboxes'),
    suggestNumericAlign: flag(cfg, 'suggestNumericAlign'),
    previewSort: flag(cfg, 'previewSort'),
    pasteAsTable: flag(cfg, 'pasteAsTable'),
    validate: flag(cfg, 'validate'),
    ambiguousWide: width === 'wide',
    maxWidth,
  };
}

export { tablesConfig, DEFAULTS };
