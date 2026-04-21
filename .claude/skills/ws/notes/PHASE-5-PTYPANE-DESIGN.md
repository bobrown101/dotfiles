# Phase 5 design notes — embedded `PtyPane` (deferred)

**Current status (2026-04-20):** Phase 5 is **fullscreen `app.suspend()` + shell-out to `ws.py attach-claude`**. Working well, zero nested-redraw cost, ~10 lines of code in `ws_tui.py::_chord_attach`. This doc exists so a future session can pick up the embedded alternative *if* a real ergonomic complaint shows up in daily use. Do not implement pre-emptively.

## When to reach for this

Reach for the embedded pane only if one of these is actively painful during day-to-day use:

- Context-switching cost: losing visible workspace state (sidebar, serve log) every time you need to glance at claude
- Multi-claude awareness: wanting to see two workspaces' claudes side-by-side
- Tab-driven UI dreams: wanting `h`/`l` to rotate through Claude as a tab peer rather than `<space> c` to leave the TUI

If none of those bite, leave it fullscreen.

## The core constraint (read first, don't forget)

Embedding a terminal in a Textual pane is a **nested terminal emulator**. Claude's stdout is Rich/Textual ANSI bytes. To render those inside Textual, you parse them with `pyte` into a Screen buffer, walk the buffer each render frame, and ask Textual to re-paint every visible cell. Your outer Textual renderer then emits its own ANSI bytes to the real terminal.

Every visible glyph runs two terminal emulators. Rich content (spinners, syntax-highlighted diffs, progress bars) can push this above 10 frames/sec of redraw work. That cost does not exist in fullscreen mode. No Python TUI framework avoids it — it's intrinsic to embedding one pty in another's renderer. Going in with your eyes open matters more than any mitigation.

## Architectural shape (under the existing daemon)

```
ws_tui.py
  WsTuiApp
    TabPane "Claude"
      PtyPane(Widget)          ← new file or ~300 LOC in ws_tui.py
        ├─ socket.socket → ~/.ws-daemon.sock
        │   (fresh connection per attach; attach_claude RPC)
        ├─ pyte.Screen(cols, rows)
        │   pyte.ByteStream(screen)   ← feed bytes here
        ├─ @work(thread=True) reader: blocking sock.recv, post() as Message
        │   Message handler: stream.feed(data); self.refresh() (debounced)
        └─ on_key: VT byte sequences → sock.send
           on_resize: resize_claude RPC (new socket) + screen.resize(cols, rows)
           on_unmount: close socket (daemon ring buffer covers re-attach replay)
```

The daemon side is **already done**. `attach_claude` / `resize_claude` RPCs exist (commit `ed44e0e`) and are identical whether the client is the CLI or a widget. No daemon work needed for Phase 5-embedded.

## Implementation sketch

Gate behind `--experimental-pty` flag so the default path stays fullscreen.

```python
# ws_tui.py (or a new ws_tui_pty.py that ws_tui imports conditionally)

import pyte                              # pin exact: "pyte==0.8.2"
from textual.widget import Widget
from textual.message import Message
from textual.geometry import Size
from rich.text import Text
from rich.segment import Segment

class _PtyBytes(Message):
    def __init__(self, data: bytes) -> None:
        self.data = data
        super().__init__()

class PtyPane(Widget, can_focus=True):
    DEFAULT_CSS = "PtyPane { height: 1fr; }"

    def __init__(self, name: str) -> None:
        super().__init__()
        self.ws_name = name
        self._sock: socket.socket | None = None
        self._screen: pyte.Screen | None = None
        self._stream: pyte.ByteStream | None = None
        self._pending_refresh: bool = False

    async def on_mount(self) -> None:
        size = self.size  # after mount, size is valid
        self._screen = pyte.Screen(max(size.width, 1), max(size.height, 1))
        self._stream = pyte.ByteStream(self._screen)
        self._sock = await asyncio.to_thread(self._connect_and_attach,
                                             size.width, size.height)
        if self._sock is None:
            return
        self._start_reader()

    def _connect_and_attach(self, cols: int, rows: int):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(str(WS_DAEMON_SOCKET))
        req = {"method": "attach_claude", "name": self.ws_name,
               "cols": cols, "rows": rows}
        s.sendall((json.dumps(req) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            buf += s.recv(65536)
        line, _, rest = buf.partition(b"\n")
        ack = json.loads(line)
        if not ack.get("ok"):
            s.close()
            return None
        if rest:
            # Post replay bytes as the first message so they feed into the screen
            # synchronously during mount. Order matters: replay before live.
            self.post_message(_PtyBytes(rest))
        return s

    @work(thread=True, exclusive=True)
    def _start_reader(self) -> None:
        sock = self._sock
        while sock is not None:
            try:
                chunk = sock.recv(65536)
            except OSError:
                break
            if not chunk:
                break
            self.post_message(_PtyBytes(chunk))

    async def on_pty_bytes(self, msg: _PtyBytes) -> None:
        self._stream.feed(msg.data)
        if not self._pending_refresh:
            self._pending_refresh = True
            # ~30 Hz: plenty for claude, cheap enough on the outer renderer
            self.set_timer(1 / 30, self._flush_refresh)

    def _flush_refresh(self) -> None:
        self._pending_refresh = False
        self.refresh()

    def render_line(self, y: int) -> Strip:
        # Walk pyte.Screen.buffer[y]; build Segments per character cell using
        # buffer[y][x].data / .fg / .bg / .bold / .italics / .underscore / .reverse.
        # The cursor cell (screen.cursor.{x,y}) renders with reversed fg/bg.
        # Return a Strip[Segment].
        ...

    async def on_resize(self, event) -> None:
        cols = max(event.size.width, 1)
        rows = max(event.size.height, 1)
        self._screen.resize(rows, cols)  # pyte takes (rows, cols)
        # Fresh socket to avoid interleaving control JSON with the raw stream
        await asyncio.to_thread(_resize_rpc, self.ws_name, cols, rows)
        self.refresh()

    def on_key(self, event) -> None:
        if self._sock is None:
            return
        data = _key_to_vt_bytes(event)
        if data:
            try:
                self._sock.sendall(data)
            except OSError:
                pass
            event.stop()

    async def on_unmount(self) -> None:
        s = self._sock
        self._sock = None
        if s is not None:
            try: s.close()
            except OSError: pass
        # Daemon keeps claude + ring buffer alive; next attach will replay.
```

`_key_to_vt_bytes` is the tedious part: arrow keys → `\x1b[A/B/C/D`, function keys, meta-combinations, etc. Crib from `pyte.modes` + any Python terminal-emulator widget for the table.

## Known sharp edges (hit these in this order)

1. **Replay ordering.** The daemon sends the ring-buffer replay *immediately after* the JSON ack, on the same socket, before any new live bytes. If you read the ack with `readline()` and buffer beyond the newline, don't drop the `rest` tail — the first message to `pyte.feed()` must be that tail.
2. **Rendering cost for line-heavy output.** Rich's diff-render helps, but you'll want a dirty-line tracker — only re-feed/re-render rows pyte marked dirty. Without this, a large log paste redraws the whole visible area per chunk.
3. **Focus model.** `PtyPane` must swallow almost every key event so claude gets them. Reserve exactly one outer key (spec: `<esc>`) for "return focus to sidebar", and handle it *before* the key-to-VT conversion. `<C-space>` was the original fallback for force-leader inside the pane; ship without it and only add if daily use demands it.
4. **pyte is inactive upstream.** Pin the exact version. 0.8.2 covers xterm 256-color + truecolor; don't rely on unreleased fixes.
5. **Scrollback.** `pyte.Screen` is fixed-height; there is no scrollback buffer. If a user needs to scroll history, they use fullscreen `ws.py attach-claude` in a real terminal. Document this.
6. **Simultaneous fullscreen + embedded attach is fine.** The daemon fan-outs PTY output to every attacher. If both a TUI pane and a fullscreen CLI are attached to the same workspace, both see output and both can type — last-writer-wins per keystroke. Confirmed working at the daemon layer already.

## What to delete from the fullscreen path when you land this

- Don't delete anything. Keep `_chord_attach` and `ws.py attach-claude`; the embedded pane goes behind `--experimental-pty`. Fullscreen is the known-good fallback for the "my embedded pane looks wrong" case and for real-terminal scrollback.

## First commit shape (if/when picking this up)

One commit that lands:
- `PtyPane` class
- `--experimental-pty` flag on `ws_tui.py`
- Wire into the `TabPane "Claude"` when the flag is on
- End-to-end verification: `<space> c` (when flag on) mounts the pane, attaches, shows replay, accepts keystrokes, resize reflows claude's inner TUI, tab away closes socket, tab back replays

Skip a `pyte` dep pin commit, skip a docs-only intro commit — all in one go.
