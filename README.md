# TCP for Vendetta Online

TCP lets a Vendetta Online plugin send and receive data over a network.

It handles partial sends, incoming messages, and socket cleanup. It uses the game's built-in `TCPSocket`.

## Install

Copy the `TCP` folder into the game's `plugins` folder. Keep it next to your plugin:

```text
plugins/
├── TCP/
│   └── client.lua
└── myplugin/
    └── main.lua
```

In your plugin, load it like this:

```lua
local TCP = dofile("../TCP/client.lua")
```

## Connect

```lua
local TCP = dofile("../TCP/client.lua")

local conn = TCP.Connect("127.0.0.1", 54000, {
    onConnect = function()
        print("Connected!")
    end,

    onMessage = function(message)
        print("Received: " .. message)
    end,

    onError = function(reason)
        print("Error: " .. reason)
    end
})

if conn then
    conn:SendMessage("Hello!")
end
```

`TCP.Connect()` starts a connection and returns a client. The connection may still be starting. Your `onConnect` function runs when it is ready.

You can queue a message before the connection is ready. TCP will send it when it can.

## Send and close

```lua
conn:SendMessage("Hello!")  -- Adds the chosen delimiter
conn:Send("Hello!")         -- Sends these exact bytes
conn:Disconnect()           -- Closes the socket
```

`SendMessage()` and `Send()` return `true` when TCP accepts the data. If they cannot accept it, they return `nil, reason`.

To reconnect the same client after a disconnect, use:

```lua
conn:Reconnect()
```

Calling `Reconnect()` while connected closes the current socket before starting a new one. TCP does not reconnect by itself.

## Choose a message delimiter

A **delimiter** marks the end of a message. The default is `"\n"` (a new line).

Choose one when you connect:

```lua
local conn = TCP.Connect("127.0.0.1", 54000, {
    delimiter = "\r\n",
    onMessage = function(message)
        print(message)
    end
})
```

You can also use `"\0"`, `"|"`, or a longer string such as `"\r\n\r\n"`.

TCP treats the delimiter as exact bytes, not a Lua pattern. It waits for the full delimiter, even if the bytes arrive in separate reads.

`onMessage(message)` receives each complete message **without the delimiter**. If you choose `"\n"`, a `"\r"` before it stays in the message. Choose `"\r\n"` if that is what your server uses.

`SendMessage()` adds the same delimiter when sending. It rejects a message that already contains the delimiter.

## Receive raw bytes

If you do not want messages split by a delimiter, use raw mode:

```lua
local conn = TCP.Connect("127.0.0.1", 54000, {
    mode = "raw",

    onData = function(data)
        print("Got " .. #data .. " bytes")
    end
})
```

Raw mode sends each chunk of received data to `onData(data)`. It does not call `onMessage()`.

A chunk may contain part of one message or parts of many messages. TCP does not choose those boundaries.

`Send()` works the same way in both modes.

## Callbacks

| Callback | What it does |
| --- | --- |
| `onConnect()` | Runs when connected |
| `onMessage(message)` | Gives you one complete message |
| `onData(data)` | Gives you raw bytes in raw mode |
| `onDisconnect(reason)` | Runs when an open connection closes |
| `onError(reason)` | Reports a connection or socket error |

You can leave out any callback you do not need.

If a connection fails to start right away, `TCP.Connect()` returns `nil, reason`. It also calls `onError(reason)`.

## Ready-to-use examples

The `simple` folder is a small plugin you can read and run. The `test` folder checks more parts of the TCP client.

Copy `TCP` and either `simple` or `test` into your game's `plugins` folder. The folders already have their `main.lua` files.

From this repo, start the local test server:

```sh
perl examples/echo_server.pl
```

Then, in Vendetta Online, type `/tcpsimple` to try the small example. Type `/tcpsimpleclose` to close it.

The test plugin has these commands:

- `/tcptestconnect` — Connect
- `/tcptestsend hello` — Send a message
- `/tcptestreconnect` — Replace the connection
- `/tcptestclose` — Close the connection
- `/tcpteststress` — Send 256 KiB and check the reply
- `/tcptestlimits` — Check the send queue limit

## Limits

A message can hold up to 65,536 bytes by default. The send queue can hold up to 1 MiB.

You can set `maxMessageBytes`, `maxPendingBytes`, and `writeBudget` in the options table if needed.

TCP sends data over a plain connection. Do not send private information to servers you do not trust.

## Tests for developers

Run these commands from the repo folder:

```sh
texlua tests/mock_socket.lua
texlua tests/edge_cases.lua
texlua tests/delimiters.lua
perl -c examples/echo_server.pl
```

The Lua tests use a fake socket. Test new changes in Vendetta Online too.

## Credits and license

The Vendetta Online TCP socket API and early Lua examples were written by Andy Sloane (a1k0n). This repo was started by Joshua S. Day (haxmeister).

This project uses the MIT license. See [LICENSE](LICENSE).
