// --- Authoring menu (Alt+M) ----------------------------------------------------------------
const vscode = require('vscode');

async function authoringMenu() {
  const items = [
    { label: '$(bold) Bold', cmd: 'markdownWorkbench.formatBold' },
    { label: '$(italic) Italic', cmd: 'markdownWorkbench.formatItalic' },
    { label: '$(symbol-string) Code', cmd: 'markdownWorkbench.formatCode' },
    { label: '$(link) Link to web', cmd: 'markdownWorkbench.insertWebLink' },
    {
      label: '$(file) Link to file in workspace',
      cmd: 'markdownWorkbench.insertFileLink',
    },
    {
      label: '$(list-unordered) Bulleted list',
      cmd: 'markdownWorkbench.insertBulletedList',
    },
    {
      label: '$(list-ordered) Numbered list',
      cmd: 'markdownWorkbench.insertNumberedList',
    },
    {
      label: '$(checklist) Task list',
      cmd: 'markdownWorkbench.insertTaskList',
    },
    { label: '$(table) Insert table', cmd: 'markdownWorkbench.insertTable' },
    {
      label: '$(arrow-both) Distribute table',
      cmd: 'markdownWorkbench.distributeTable',
    },
    {
      label: '$(fold) Consolidate table',
      cmd: 'markdownWorkbench.consolidateTable',
    },
    {
      label: '$(sort-precedence) Sort selection ascending',
      cmd: 'markdownWorkbench.sortAscending',
    },
    {
      label: '$(sort-precedence) Sort selection descending',
      cmd: 'markdownWorkbench.sortDescending',
    },
    {
      label: '$(code) Insert language identifier',
      cmd: 'markdownWorkbench.insertLanguageIdentifier',
    },
  ];
  const pick = await vscode.window.showQuickPick(items, {
    placeHolder: 'Markdown authoring',
  });
  if (pick) vscode.commands.executeCommand(pick.cmd);
}

module.exports = { authoringMenu };
