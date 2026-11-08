-- Simple TCP example for Vendetta Online.
-- Copy this simple/ folder and TCP/ into the game's plugins/ folder.
-- Start the Perl echo server: perl examples/echo_server.pl

local TCP = dofile("../TCP/client.lua")
local conn

local function connect()
    if conn then conn:Disconnect() end

    conn = TCP.Connect("127.0.0.1", 54000, {
        -- The server sends lines. Newline is the default delimiter.
        onConnect = function()
            print("[TCP simple] Connected!")
        end,

        onMessage = function(message)
            print("[TCP simple] " .. message)
        end,

        onError = function(reason)
            print("[TCP simple] Error: " .. reason)
        end
    })

    if conn then
        conn:SendMessage("hello from simple plugin")
    end
end

local function close()
    if conn then
        conn:Disconnect()
        conn = nil
    end
end

RegisterUserCommand("tcpsimple", connect)
RegisterUserCommand("tcpsimpleclose", close)
print("[TCP simple] Use /tcpsimple and /tcpsimpleclose")
