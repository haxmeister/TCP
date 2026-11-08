-- Copy this to plugins/tcp-test/main.lua (adjust dofile if needed).
local Client = dofile('plugins/TCP/client.lua')
TCPTest = TCPTest or {}

function TCPTest.connect()
    if TCPTest.conn then TCPTest.conn:Disconnect() end
    TCPTest.conn = Client.New({
        host = '127.0.0.1', port = 54000,
        onConnect = function(conn)
            print('[TCP test] connected')
            conn:SendLine('hello from VO')
        end,
        onLine = function(conn, line)
            print('[TCP test] received: ' .. line)
        end,
        onDisconnect = function(conn, reason)
            print('[TCP test] disconnected: ' .. tostring(reason))
        end,
        onError = function(conn, reason)
            print('[TCP test] error: ' .. tostring(reason))
        end
    })
    local ok, err = TCPTest.conn:Connect()
    if not ok then print('[TCP test] Connect failed: ' .. tostring(err)) end
end

function TCPTest.send(_, args)
    if not TCPTest.conn then return print('[TCP test] not initialized') end
    local text = table.concat(args or {}, ' ')
    local ok, err = TCPTest.conn:SendLine(text)
    if not ok then print('[TCP test] SendLine failed: ' .. tostring(err)) end
end

function TCPTest.close()
    if TCPTest.conn then TCPTest.conn:Disconnect() end
end

RegisterUserCommand('tcptestconnect', TCPTest.connect)
RegisterUserCommand('tcptestsend', TCPTest.send)
RegisterUserCommand('tcptestclose', TCPTest.close)
RegisterUserCommand('tcptestreconnect', TCPTest.connect)
print('[TCP test] /tcptestconnect /tcptestsend text /tcptestclose /tcptestreconnect')
