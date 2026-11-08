# TCP for Vendetta Online

TCP helps your Vendetta Online plugin talk to a server.

It keeps track of data that is still being sent or received. Your plugin can work with full messages instead of small pieces of data.

This library uses the TCP socket built into Vendetta Online. You do not need another Lua library.

## Install

Copy the **TCP** folder from this repo into the game's `plugins` folder.

```text
plugins/
├── TCP/
│   └── client.lua
└── myplugin/
    └── main.lua
```

Your plugin can load TCP with:

```lua
local TCP = dofile("../TCP/client.lua")
```

You only need one copy of TCP. Many plugins can use it.

## Connect and send a message

```lua
local TCP = dofile("../TCP/client.lua")

local conn = TCP.Connect("127.0.0.1", 54000, {
    delimiter = "\r\n",

    onConnect = function()
        print("Connected!")
    end,

    onMessage = function(message)
        print("Received: " .. message)
    end,

    onError = function(reason)
        print("TCP error: " .. reason)
    end
})

if conn then
    conn:SendMessage("Hello!")
end
```

`TCP.Connect()` starts the connection. It returns a client right away. The connection may still be starting. `onConnect` runs when it is ready.

You can send a message while the connection starts. TCP will keep it in a queue until it can send it.

To close the connection:

```lua
conn:Disconnect()
```

TCP does **not** reconnect on its own. You can call `conn:Connect()` again when needed.

## Pick where messages end

A **delimiter** is a set of bytes that marks the end of a message. The default is `"\n"`.

You can choose a different delimiter when you connect:

| Delimiter | What it means |
| --- | --- |
| `"\n"` | New line (the default) |
| `"\r\n"` | Windows-style or network text line |
| `"\0"` | Zero byte |
| `"|"` | Pipe character |
| `"\r\n\r\n"` | Two empty line breaks |

The delimiter is plain text or bytes, not a Lua pattern. It can be split across two socket reads. TCP will still find the full message.

`onMessage(message)` gets the message **without** its delimiter.

### Three ways to send

```lua
conn:SendMessage("hello")  -- adds the chosen delimiter
conn:Send("hello")         -- sends exactly "hello"
conn:SendLine("hello")     -- always adds \r\n (old API)
```

`SendMessage()` will not accept text that already contains the delimiter. Use `Send()` if you need to send those bytes yourself.

All three send methods return `true` when the data is placed in the send queue. If the queue is full or the socket is closed, they return `nil` and a reason.

## Get raw data instead

Not every server uses message endings. Some send bytes in another format.

Use `mode = "raw"` to get data as it arrives:

```lua
local TCP = dofile("../TCP/client.lua")

local conn = TCP.Connect("127.0.0.1", 54000, {
    mode = "raw",

    onData = function(data)
        print("Got " .. #data .. " bytes")
    end
})
```

In raw mode, TCP calls `onData(data)`. It does not call `onMessage()`.

One data chunk may hold part of a message, one full message, or many messages. This is how TCP works. Your plugin must split raw data if it needs full messages.

`Send()` still sends raw bytes in either mode.

## Callbacks

You can add these functions to `TCP.Connect()`:

| Name | When it runs |
| --- | --- |
| `onConnect()` | The connection is ready |
| `onMessage(message)` | A full message arrives |
| `onData(data)` | Raw bytes arrive in raw mode |
| `onDisconnect(reason)` | A connection that was open closes |
| `onError(reason)` | A connection or socket error happens |

You can leave out callbacks you do not need.

A failed connection calls `onError`. It does not call `onConnect`.

## Try the small example

The `simple` folder has a short plugin you can read and run. Copy `TCP` and `simple` into your game's `plugins` folder. No file names need to change.

Start the test server with `perl examples/echo_server.pl`. In the game, type `/tcpsimple` to connect and send one message. Type `/tcpsimpleclose` to close it.

## Test it in the game

The `test` folder is a full plugin. You do not need to rename any files.

1. Copy both `TCP` and `test` into the game's `plugins` folder.
2. In a terminal, run `perl examples/echo_server.pl` from this repo.
3. Start Vendetta Online.
4. In the game, enter `/tcptestconnect`.
5. Try `/tcptestsend hello`, `/tcpteststress`, and `/tcptestlimits`.
6. Use `/tcptestclose` when finished.

The test plugin has extra commands because it checks for socket bugs. **You do not need that code in your own plugin.**

## If you used the old API

The old `New()` API still works:

```lua
local TCP = dofile("../TCP/client.lua")

local conn = TCP.New({
    host = "127.0.0.1",
    port = 54000,
    onLine = function(client, line)
        print(line)
    end
})

conn:Connect()
```

The old callbacks receive the client first. The new `TCP.Connect()` callbacks only receive the message or reason. This makes small plugins easier to write.

`New()` can also use `delimiter = "..."` and `SendMessage()`.

## Limits and notes

Messages are limited to 65,536 bytes by default. The send queue can hold up to 1 MiB. You can change these limits with `maxLineBytes` and `maxPendingBytes` if needed.

This library does not add TLS or encryption. Do not send passwords or other private data over an untrusted plain TCP connection.

This work builds on the Vendetta Online TCP socket API and early Lua code by **Andy Sloane (a1k0n)**. The TCP repo was started by **Joshua S. Day (haxmeister)**.

See [LICENSE](LICENSE) for the MIT license.

### Tests for developers

Run these from the repo root using Lua or `texlua`:

```sh
texlua tests/mock_socket.lua
texlua tests/edge_cases.lua
texlua tests/delimiters.lua
perl -c examples/echo_server.pl
```

The Lua tests use a fake socket. They do not replace tests inside Vendetta Online.
