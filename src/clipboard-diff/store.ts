// In-memory file system behind the clipboard diff's virtual pages (candidate
// and selection baseline). Registered as a FileSystemProvider so the pages are
// editable and swappable like files, while writeFile only ever fills a Map -
// nothing reaches the disk (docs/DECISIONS.md #48).

import * as vscode from 'vscode';

/** URI scheme of every virtual page of the clipboard diff. */
const SCHEME = 'markdown-workbench-clipboard';

/** A stored page: its bytes and file times. */
interface StoredFile {
  data: Uint8Array;
  ctime: number;
  mtime: number;
}

/** The virtual pages of every clipboard diff, keyed by URI path. */
class CandidateStore implements vscode.FileSystemProvider {
  readonly files = new Map<string, StoredFile>();
  private readonly emitter = new vscode.EventEmitter<
    vscode.FileChangeEvent[]
  >();
  readonly onDidChangeFile = this.emitter.event;

  /** Stores `text` under `uri` (a page this extension creates). */
  put(uri: vscode.Uri, text: string): void {
    const now = Date.now();
    this.files.set(uri.path, {
      data: Buffer.from(text, 'utf8'),
      ctime: now,
      mtime: now,
    });
  }

  /** Current text of a page, or undefined. */
  textOf(uri: vscode.Uri): string | undefined {
    const f = this.files.get(uri.path);
    return f ? Buffer.from(f.data).toString('utf8') : undefined;
  }

  /** Whether a page is stored under `uri`. */
  has(uri: vscode.Uri): boolean {
    return this.files.has(uri.path);
  }

  /** Frees a page's content. */
  release(uri: vscode.Uri): void {
    this.files.delete(uri.path);
  }

  /** Frees every page (deactivate). */
  clear(): void {
    this.files.clear();
  }

  // --- FileSystemProvider ------------------------------------------------------

  watch(): vscode.Disposable {
    return new vscode.Disposable(() => {});
  }

  stat(uri: vscode.Uri): vscode.FileStat {
    const f = this.files.get(uri.path);
    if (f)
      return {
        type: vscode.FileType.File,
        ctime: f.ctime,
        mtime: f.mtime,
        size: f.data.byteLength,
      };
    if (this.isDirectory(uri.path))
      return { type: vscode.FileType.Directory, ctime: 0, mtime: 0, size: 0 };
    throw vscode.FileSystemError.FileNotFound(uri);
  }

  private isDirectory(path: string): boolean {
    const prefix = path.endsWith('/') ? path : `${path}/`;
    for (const p of this.files.keys()) if (p.startsWith(prefix)) return true;
    return path === '/';
  }

  readDirectory(uri: vscode.Uri): [string, vscode.FileType][] {
    const prefix = uri.path.endsWith('/') ? uri.path : `${uri.path}/`;
    const out = new Map<string, vscode.FileType>();
    for (const p of this.files.keys()) {
      if (!p.startsWith(prefix)) continue;
      const rest = p.slice(prefix.length);
      const slash = rest.indexOf('/');
      out.set(
        slash === -1 ? rest : rest.slice(0, slash),
        slash === -1 ? vscode.FileType.File : vscode.FileType.Directory,
      );
    }
    return [...out];
  }

  createDirectory(): void {
    // Directories are implicit in the file paths.
  }

  readFile(uri: vscode.Uri): Uint8Array {
    const f = this.files.get(uri.path);
    if (!f) throw vscode.FileSystemError.FileNotFound(uri);
    return f.data;
  }

  // Memory only. The mtime always grows, so VS Code never reports a save
  // conflict for two saves within the same millisecond. `content` is the
  // buffer VS Code hands over for this write; it is kept, not copied (every
  // keystroke saves, so a copy would cost the page size per keystroke).
  writeFile(
    uri: vscode.Uri,
    content: Uint8Array,
    options: { readonly create: boolean; readonly overwrite: boolean },
  ): void {
    const f = this.files.get(uri.path);
    if (!f && !options.create) throw vscode.FileSystemError.FileNotFound(uri);
    if (f && options.create && !options.overwrite)
      throw vscode.FileSystemError.FileExists(uri);
    const now = Date.now();
    this.files.set(uri.path, {
      data: content,
      ctime: f ? f.ctime : now,
      mtime: f ? Math.max(now, f.mtime + 1) : now,
    });
    this.emitter.fire([
      {
        type: f ? vscode.FileChangeType.Changed : vscode.FileChangeType.Created,
        uri,
      },
    ]);
  }

  delete(uri: vscode.Uri): void {
    if (!this.files.delete(uri.path))
      throw vscode.FileSystemError.FileNotFound(uri);
    this.emitter.fire([{ type: vscode.FileChangeType.Deleted, uri }]);
  }

  rename(
    oldUri: vscode.Uri,
    newUri: vscode.Uri,
    options: { readonly overwrite: boolean },
  ): void {
    const f = this.files.get(oldUri.path);
    if (!f) throw vscode.FileSystemError.FileNotFound(oldUri);
    if (this.files.has(newUri.path) && !options.overwrite)
      throw vscode.FileSystemError.FileExists(newUri);
    this.files.delete(oldUri.path);
    this.files.set(newUri.path, f);
    this.emitter.fire([
      { type: vscode.FileChangeType.Deleted, uri: oldUri },
      { type: vscode.FileChangeType.Created, uri: newUri },
    ]);
  }
}

export { CandidateStore, SCHEME };
