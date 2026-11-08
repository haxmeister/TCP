-- Standard Lua tests with a fake Vendetta Online TCPSocket.
local sockets, logs = {}, {}
log_print = function(msg) logs[#logs+1] = msg end
function TCPSocket()
    local sock = {sent = {}, sends = {}, recv = {}, disconnects = 0, peer = nil}
    function sock:SetReadHandler(fn) self.onRead = fn end
    function sock:SetWriteHandler(fn) self.onWrite = fn end
    function sock:Connect(host, port) self.host, self.port = host, port; return 1 end
    function sock:GetPeerName() return self.peer end
    function sock:GetSocketError() return self.error end
    function sock:Disconnect() self.disconnects = self.disconnects + 1 end
    function sock:Send(data)
        local step = table.remove(self.sends, 1)
        local n = step or #data
        if n > 0 then self.sent[#self.sent+1] = string.sub(data, 1, n) end
        return n
    end
    function sock:Recv()
        local next = table.remove(self.recv, 1)
        return next[1], next[2]
    end
    function sock:connected()
        self.peer = '127.0.0.1:54000'
        assert(self.onWrite)
        self.onWrite()
    end
    sockets[#sockets+1] = sock
    return sock
end
local TCP = dofile('TCP/client.lua')
local function make(opts)
    opts = opts or {}
    return TCP.Connect('127.0.0.1', 54000, opts)
end
local function eq(actual, expected)
    assert(actual == expected, 'got ' .. tostring(actual) .. ' expected ' .. tostring(expected))
end

local connected, lines, disconnected, errors = 0, {}, {}, {}
local c = make({onConnect=function() connected=connected+1 end,
 onMessage=function(line) lines[#lines+1]=line end,
 onDisconnect=function(why) disconnected[#disconnected+1]=why end,
 onError=function(err) errors[#errors+1]=err end})
eq(c.state,'connecting')
assert(c:SendMessage('hello'))
local first=sockets[#sockets]
first:connected(); eq(c.state,'connected'); eq(connected,1)
eq(table.concat(first.sent),'hello\n'); eq(c.pendingBytes,0)
first.recv={{'ab',nil}}; first.onRead(); eq(#lines,0)
first.recv={{'c\nnext\npartial',nil}}; first.onRead(); eq(#lines,2);eq(lines[1],'abc');eq(lines[2],'next')
assert(c:Send('ping')); eq(c.input,'partial')
first.recv={{' end\n',nil}}; first.onRead(); eq(lines[3],'partial end')
first.sends={2,-1,3}
assert(c:Send('12345'));eq(c.pendingBytes,3)
assert(first.onWrite); first.onWrite();eq(c.pendingBytes,3)
first.onWrite();eq(c.pendingBytes,0)
eq(table.concat(first.sent),'hello\nping12345')

local stale_read = first.onRead
local stale_write = c.writeCallback
c:Disconnect();eq(first.disconnects,1);eq(c.state,'disconnected');eq(#disconnected,1)
assert(c:Reconnect())
local second=sockets[#sockets]
stale_read();stale_write();eq(c.state,'connecting')
second:connected();eq(c.state,'connected');eq(connected,2)
assert(c:SendMessage('again'));eq(table.concat(second.sent),'again\n')
c:Disconnect();eq(second.disconnects,1);eq(#disconnected,2)

assert(c:Reconnect())
local third=sockets[#sockets]
third.error='connection refused';third.onWrite()
eq(c.state,'disconnected');eq(#errors,1);eq(#disconnected,2);eq(third.disconnects,1)

local data_seen
local raw = make({mode='raw',onData=function(_,data) data_seen=data end})
local rs=sockets[#sockets]; rs:connected()
rs.recv={{'\0\1x\n',nil}};rs.onRead();eq(data_seen,'\0\1x\n')
raw:Disconnect()

local overflow_error
local small = make({maxMessageBytes=3,onError=function(e) overflow_error=e end})
local ss=sockets[#sockets];ss:connected();ss.recv={{'1234',nil}};ss.onRead()
eq(small.state,'disconnected');assert(overflow_error:find('maxMessageBytes',1,true))

local bad = make({onMessage=function() error('expected test failure') end})
local bs=sockets[#sockets];bs:connected();bs.recv={{'line\n',nil}};bs.onRead()
eq(bad.state,'connected');assert(#logs>0)
bad:Disconnect()

local eof = make()
local es=sockets[#sockets];es:connected();es.recv={{'',nil}};es.onRead();eq(eof.state,'disconnected')
local closed_count, closed_reason, close_errors = 0, nil, 0
local clean = make({
    onDisconnect = function(reason) closed_count=closed_count+1; closed_reason=reason end,
    onError = function() close_errors=close_errors+1 end
})
local cs=sockets[#sockets];cs:connected()
cs.recv={{nil, 0}};cs.onRead()
eq(clean.state,'disconnected')
eq(closed_count,1);eq(closed_reason,'peer closed connection');eq(close_errors,0)
eq(cs.disconnects,1)

print('PASS: mocked VO socket transport, reconnect, lines, raw, bounds and errors')
