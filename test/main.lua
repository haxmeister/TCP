-- Ready-to-install Vendetta Online plugin: copy this entire test/ folder into plugins/.
-- Install the sibling TCP/ folder from this repository into plugins/ as well.
local TCP = dofile('../TCP/client.lua')
TCPTest = TCPTest or {}

function TCPTest.connect()
    if TCPTest.conn then TCPTest.conn:Disconnect() end
    local conn, err = TCP.Connect('127.0.0.1', 54000, {
        onConnect = function()
            print('[TCP test] connected')
        end,
        onMessage = function(line)
            print('[TCP test] received: ' .. line)
            if line == 'stress ok 262144' then
                print('[TCP test] PASS: server received all 262144 stress bytes')
            end
        end,
        onDisconnect = function(reason)
            print('[TCP test] disconnected: ' .. tostring(reason))
        end,
        onError = function(reason)
            print('[TCP test] error: ' .. tostring(reason))
        end
    })
    TCPTest.conn = conn
    if not conn then
        print('[TCP test] Connect failed: ' .. tostring(err))
    else
        conn:SendMessage('hello from VO')
    end
end

function TCPTest.send(_, args)
    if not TCPTest.conn then return print('[TCP test] not initialized') end
    local text = table.concat(args or {}, ' ')
    local ok, err = TCPTest.conn:SendMessage(text)
    if not ok then print('[TCP test] SendMessage failed: ' .. tostring(err)) end
end

-- Send a 256 KiB payload without printing the payload into game chat.
-- The Perl test server counts every byte and acknowledges only at completion.
function TCPTest.stress()
    local conn = TCPTest.conn
    if not conn or conn.state ~= 'connected' then
        print('[TCP test] connect first')
        return
    end
    local size = 262144
    local ok, err = conn:SendMessage('STRESS ' .. size)
    if not ok then print('[TCP test] stress header failed: ' .. tostring(err)); return end
    local chunk = string.rep('x', 8192)
    for i = 1, 32 do
        ok, err = conn:Send(chunk)
        if not ok then
            print('[TCP test] stress send failed at block ' .. i .. ': ' .. tostring(err))
            return
        end
    end
    print('[TCP test] stress payload accepted: ' .. size .. ' bytes; check server acknowledgment')
end

-- Limit check is deterministic: we queue data while connecting, before
-- any native writes have a chance to drain the queue.
function TCPTest.limits()
    local conn, err = TCP.Connect('127.0.0.1', 54000, {
        maxPendingBytes = 8,
        onConnect = function()
            print('[TCP test] limits connection completed')
            if TCPTest.limitsConn then TCPTest.limitsConn:Disconnect() end
        end,
        onError = function(reason)
            print('[TCP test] limits connection error: ' .. tostring(reason))
        end
    })
    TCPTest.limitsConn = conn
    if not conn then
        print('[TCP test] limits connect failed: ' .. tostring(err))
        return
    end
    local first = conn:Send('12345678')
    local second, why = conn:Send('9')
    if first and not second and why == 'outgoing buffer is full'
       and conn.pendingBytes == 8 then
        print('[TCP test] PASS: queued 8 bytes; rejected byte 9 without losing queued bytes')
    else
        print('[TCP test] FAIL: pending limit was not enforced')
    end
end


-- Check a real multi-byte delimiter on a separate test port.
function TCPTest.delimiter()
    if TCPTest.delimiterConn then TCPTest.delimiterConn:Disconnect() end
    local seen = {}
    local conn, err = TCP.Connect('127.0.0.1', 54001, {
        delimiter = '||',
        onConnect = function()
            print('[TCP delimiter] connected with || delimiter')
        end,
        onMessage = function(message)
            print('[TCP delimiter] received: ' .. message)
            seen[message] = true
            if seen.first and seen.second and seen['echo: hello'] then
                print('[TCP delimiter] PASS: received separate messages and echo with || delimiter')
                if TCPTest.delimiterConn then TCPTest.delimiterConn:Disconnect() end
            end
        end,
        onError = function(reason)
            print('[TCP delimiter] error: ' .. tostring(reason))
        end
    })
    TCPTest.delimiterConn = conn
    if not conn then
        print('[TCP delimiter] Connect failed: ' .. tostring(err))
        return
    end
    local ok, why = conn:SendMessage('hello')
    if not ok then print('[TCP delimiter] SendMessage failed: ' .. tostring(why)) end
end

function TCPTest.close()
    if TCPTest.conn then TCPTest.conn:Disconnect() end
end

RegisterUserCommand('tcptestconnect', TCPTest.connect)
RegisterUserCommand('tcptestsend', TCPTest.send)
RegisterUserCommand('tcptestclose', TCPTest.close)
RegisterUserCommand('tcpteststress', TCPTest.stress)
RegisterUserCommand('tcptestlimits', TCPTest.limits)
RegisterUserCommand('tcptestdelimiter', TCPTest.delimiter)
RegisterUserCommand('tcptestreconnect', TCPTest.connect)
print('[TCP test] /tcptestconnect /tcptestsend text /tcptestclose /tcptestreconnect /tcpteststress /tcptestlimits /tcptestdelimiter')
