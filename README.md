# TCP for Vendetta Online

A small, nonblocking TCP client wrapper for Vendetta Online plugins. It uses the game's native `TCPSocket` directly. No LuaSocket, metatables, or background threads are required.

The goal is to make socket connections **predictable**: explicit connect and disconnect, proper partial-write buffering, complete incoming lines, and clear callbacks. This is a replacement for the earlier implementation, **not a drop-in compatibility release**.

## Install

To run the included test, copy the **`TCP` and `test` directories directly from this repository** into Vendetta Online's `plugins` directory. No renaming or editing is required:

```text
plugins/
├── TCP/
│   └── client.lua
└── test/
    └── main.lua
```

When VO loads `test/main.lua` on startup, `dofile()` resolves relative to that plugin's directory. Other plugins can use the shared library using the sibling directory path:

```lua
local TCPClient = dofile('../TCP/client.lua')

local conn = TCPClient.New({
    host = '127.0.0.1',
    port = 54000,
    onConnect = function(client)
        print('Connected!')
        client:SendLine('hello')
    end,
    onLine = function(client, line)
        print('Received: ' .. line)
    end,
    onDisconnect = function(client, reason)
        print('Disconnected: ' .. reason)
    end,
    onError = function(client, reason)
        print('TCP error: ' .. reason)
    end
})

conn:Connect()      -- starts async connect; onConnect runs when established
-- conn:SendLine('hi')
-- conn:Send('raw bytes')
-- conn:Disconnect() -- explicitly closes the native socket
```

## Contract

- `New(options)` requires `host` (string) and `port` (number). It **does not** connect automatically.
- `Connect([host, port])` returns `true` if the **asynchronous attempt started**. A successful connection is announced only by `onConnect(client)`.
- `Send(data)` queues *exact bytes*, with no newline added. `SendLine(line)` adds CRLF. Both return `true` if accepted into the queue, or `nil, reason`.
- Incoming `line` mode (default) buffers data until LF, stripping one trailing CR; `onLine(client, line)` fires for each complete line. `onMessage` is accepted as an alias for `onLine` when migrating old code.
- `mode = 'raw'` uses `onData(client, chunk)` instead, preserving binary bytes. **TCP chunks are not application messages**; your protocol must define its own framing.
- `Disconnect()` calls VO's native `TCPSocket:Disconnect()`, disables handlers, drops queued bytes, and ignores callbacks from replaced sockets.
- `onError(client, reason)` handles connection/transport errors. `onDisconnect(client, reason)` fires once when an **established** connection closes, including manual close. A failed connection attempt only calls `onError`.
- No automatic reconnect yet. Call `Connect()` again when appropriate; the old connection is explicitly disconnected first.
- `state` is `'disconnected'`, `'connecting'`, or `'connected'`. `pendingBytes` shows queued bytes.
- Optional limits: `maxPendingBytes` (default 1048576), `maxLineBytes` (default 65536 decoded bytes per line, excluding CRLF), `writeBudget` (default 65536 bytes per flush). When the queue is full, `Send()` rejects the entire new write instead of dropping part of it.

Callbacks are invoked safely; callback errors are written to VO's log (or `print` when `log_print` is unavailable). They are not silently swallowed.

## Try it in Vendetta

Run `perl examples/echo_server.pl` from a terminal at the root of this repository. Copy the repository's ready-made **`TCP/`** and **`test/`** folders straight into Vendetta's `plugins/` folder; `test/main.lua` already contains the correct `dofile('../TCP/client.lua')` line. Restart or reload the game interface. In-game commands:

- `/tcptestconnect` — open a connection
- `/tcptestsend hello` — send a line
- `/tcptestclose` — explicitly disconnect
- `/tcptestreconnect` — replace connection, checking for duplicates server-side
- `/tcpteststress` — send 256 KiB; expect `stress ok 262144` from the server
- `/tcptestlimits` — verify an 8-byte queue accepts 8 bytes and rejects byte 9

The echo server reports active connections and sends multiple lines to test buffering. It accepts a `STRESS 262144` header followed by exactly 262144 bytes, then sends an acknowledgment. Basic connect/send/receive, rapid reconnect without observed server-side overlap, clean peer closure, and refused connection were observed in the November 2026 Linux VO client. The `/tcpteststress` and `/tcptestlimits` commands also passed in the live Linux VO client: the server acknowledged 262144 bytes and the client correctly rejected the ninth byte of an eight-byte pending queue. Forced native partial writes under congestion remain unverified in-game; the mock edge-case tests exercise the code paths deterministically.

**Path note:** the relative path shown above is for a plugin loaded normally from `plugins/test/main.lua`. If running `dofile()` manually in the game console, the working directory may differ; console examples often use `plugins/TCP/client.lua` instead.

For automated checks outside Vendetta, run `lua tests/mock_socket.lua` and `lua tests/edge_cases.lua` from the repository root. These simulate partial sends, would-block, queue and line limits, and callback reentrancy, but do **not** prove native VO behavior under congestion. Syntax-check the Perl server with `perl -c examples/echo_server.pl`.

## Scope and credits

This is a TCP transport wrapper, **not TLS or MySQL**. A localhost TLS gateway could be built on top later.

Original VO `TCPSocket` API and early Lua wrapper by Andy Sloane (a1k0n). Repository's original implementation by Joshua S. Day (haxmeister), 2022. MIT license; see `LICENSE`.
