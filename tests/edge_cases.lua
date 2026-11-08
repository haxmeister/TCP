-- Mock edge cases for VO's native nonblocking TCPSocket.
-- Run from the repository root: lua tests/edge_cases.lua
local sockets = {}
local errors_logged = {}
log_print = function(message) errors_logged[#errors_logged + 1] = message end

function TCPSocket()
    local sock = {
        writes = {}, output = '', read_queue = {}, peer = nil,
        closed = 0, connect_error = nil, send_error = nil
    }
    function sock:SetReadHandler(fn) self.on_read = fn end
    function sock:SetWriteHandler(fn) self.on_write = fn end
    function sock:Connect() return 1 end
    function sock:GetPeerName() return self.peer end
    function sock:GetSocketError() return self.send_error or self.connect_error end
    function sock:Disconnect() self.closed = self.closed + 1 end
    function sock:Send(data)
        local planned = table.remove(self.writes, 1)
        local count = planned or #data
        if count > 0 then
            if count > #data then count = #data end
            self.output = self.output .. string.sub(data, 1, count)
        end
        return count
    end
    function sock:Recv()
        local value = table.remove(self.read_queue, 1)
        return value[1], value[2]
    end
    function sock:establish()
        self.peer = '127.0.0.1:54000'
        assert(self.on_write)
        self.on_write()
    end
    sockets[#sockets + 1] = sock
    return sock
end

local Client = dofile('TCP/client.lua')
local function new(opts)
    opts = opts or {}
    opts.host, opts.port = '127.0.0.1', 54000
    return Client.New(opts)
end
local function eq(actual, expected, label)
    assert(actual == expected, (label or '') .. ': expected ' .. tostring(expected)
        .. ', got ' .. tostring(actual))
end
local function latest() return sockets[#sockets] end

-- Small write budget must preserve every byte over many write-ready callbacks.
local budget = new({writeBudget = 3})
assert(budget:Connect())
local b = latest(); b:establish()
assert(budget:Send('abcdefghij'))
eq(b.output, 'abc', 'first flush')
eq(budget.pendingBytes, 7)
assert(b.on_write)
b.on_write(); eq(b.output, 'abcdef'); eq(budget.pendingBytes, 4)
b.on_write(); eq(b.output, 'abcdefghi'); eq(budget.pendingBytes, 1)
b.on_write(); eq(b.output, 'abcdefghij'); eq(budget.pendingBytes, 0)
eq(b.on_write, nil, 'write notification disabled on empty queue')
budget:Disconnect(); eq(b.closed, 1)

-- Partial send followed by would-block and eventual completion.
local partial = new()
assert(partial:Connect())
local p = latest(); p:establish()
p.writes = {2, -1, 4}
p.send_error = 'EWOULDBLOCK'
assert(partial:Send('123456'))
eq(p.output, '12'); eq(partial.pendingBytes, 4)
p.on_write(); eq(partial.pendingBytes, 4)
p.on_write(); eq(p.output, '123456'); eq(partial.pendingBytes, 0)
partial:Disconnect()

-- The pending-byte limit must not accept a partial new application write.
local limited = new({maxPendingBytes = 8, writeBudget = 2})
assert(limited:Connect())
local l = latest()
assert(limited:Send('12345678'))
local accepted, reason = limited:Send('9')
eq(accepted, nil); eq(reason, 'outgoing buffer is full')
eq(limited.pendingBytes, 8)
l:establish()
eq(l.output, '12'); eq(limited.pendingBytes, 6)
accepted, reason = limited:Send('789')
eq(accepted, nil); eq(reason, 'outgoing buffer is full')
while l.on_write do l.on_write() end
eq(l.output, '12345678'); eq(limited.pendingBytes, 0)
assert(limited:Send('new'))
while l.on_write do l.on_write() end
eq(l.output, '12345678new')
limited:Disconnect()

-- A hard send error must close, rather than looping on writable callbacks.
local hard_errors, hard_disconnects = {}, 0
local broken = new({
    onError = function(_, reason) hard_errors[#hard_errors + 1] = reason end,
    onDisconnect = function() hard_disconnects = hard_disconnects + 1 end,
})
assert(broken:Connect())
local h = latest(); h:establish()
h.writes = {-1}; h.send_error = 'Broken pipe'
assert(broken:Send('X'))
eq(broken.state, 'disconnected')
eq(#hard_errors, 1); assert(string.find(hard_errors[1], 'Broken pipe', 1, true))
eq(hard_disconnects, 1); eq(h.closed, 1)

-- A string-valued 'would block' receive error is not a disconnect.
local would = new()
assert(would:Connect()); local w = latest(); w:establish()
w.read_queue = {{nil, 'EWOULDBLOCK'}}
w.on_read(); eq(would.state, 'connected')
would:Disconnect()

-- Reentrant onDisconnect may reconnect; the outer Connect must not leak
-- a third native socket.
local reentries = 0
local reentrant = new({onDisconnect = function(self)
    reentries = reentries + 1
    assert(self:Connect())
end})
assert(reentrant:Connect())
local old = latest(); old:establish()
local count_before = #sockets
local ok, why = reentrant:Connect()
eq(ok, nil)
eq(why, 'connection changed during onDisconnect')
eq(reentries, 1)
eq(#sockets, count_before + 1)
eq(old.closed, 1)
eq(reentrant.state, 'connecting')
reentrant.onDisconnect = nil
reentrant:Disconnect()

-- Old handlers cannot deliver messages after an active socket is replaced.
local messages = {}
local switched = new({onLine = function(_, line) messages[#messages+1] = line end})
assert(switched:Connect()); local stale = latest(); stale:establish()
local stale_read = stale.on_read
assert(switched:Connect()); local fresh = latest(); fresh:establish()
stale.read_queue = {{'old\n', nil}}
stale_read(); eq(#messages, 0)
fresh.read_queue = {{'new\n', nil}}
fresh.on_read(); eq(messages[1], 'new')
switched:Disconnect()

print('PASS: write budgets, partial writes, would-block, queue limits, hard errors, and reentrancy')
