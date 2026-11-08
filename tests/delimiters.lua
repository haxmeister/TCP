-- Run from repo root: texlua tests/delimiters.lua (or lua).
-- Fake VO TCPSocket so we can test framing without the game.
local sockets = {}
function TCPSocket()
    local s = {sent = '', incoming = {}, closed = 0}
    function s:SetReadHandler(fn) self.onRead = fn end
    function s:SetWriteHandler(fn) self.onWrite = fn end
    function s:Connect() return 1 end
    function s:GetPeerName() return self.peer end
    function s:GetSocketError() return nil end
    function s:Send(bytes) self.sent = self.sent .. bytes; return #bytes end
    function s:Disconnect() self.closed = self.closed + 1 end
    function s:Recv() return table.remove(self.incoming, 1), nil end
    function s:ready()
        self.peer = 'localhost:54000'
        assert(self.onWrite); self.onWrite()
    end
    function s:feed(bytes)
        self.incoming[#self.incoming+1] = bytes
        assert(self.onRead); self.onRead()
    end
    sockets[#sockets+1] = s
    return s
end
local TCP = dofile('TCP/client.lua')
local function eq(a,b) assert(a==b, 'expected '..tostring(b)..', got '..tostring(a)) end
local function socket() return sockets[#sockets] end

local messages, connected, closed = {}, 0, 0
local c = TCP.Connect('127.0.0.1', 54000, {
    delimiter = '\r\n', maxMessageBytes = 3,
    onConnect = function() connected=connected+1 end,
    onMessage = function(msg) messages[#messages+1] = msg end,
    onDisconnect = function() closed=closed+1 end
})
assert(c); eq(c.state,'connecting')
assert(c:SendMessage('hi')) -- pending connection
local a=socket(); a:ready(); eq(connected,1); eq(a.sent,'hi\r\n')
a:feed('one\r'); eq(#messages,0)
a:feed('\ntwo\r\n\r\n'); eq(messages[1],'one'); eq(messages[2],'two'); eq(messages[3],'')
a:feed('abc\r'); eq(c.state,'connected')
a:feed('\n'); eq(messages[4],'abc')
local ok,err=c:SendMessage('bad\r\ntext')
eq(ok,nil); eq(err,'message contains delimiter')
assert(c:Send('raw\0bytes')); eq(a.sent,'hi\r\nraw\0bytes')
a:feed('abcd\r\n'); eq(c.state,'disconnected'); eq(closed,1); eq(a.closed,1)

local multi={}
local b=TCP.Connect('127.0.0.1',54000,{
    delimiter='abab', maxMessageBytes=4,
    onMessage=function(msg) multi[#multi+1]=msg end
})
local s=socket();s:ready()
s:feed('fooaba'); eq(#multi,0)
s:feed('bbarabab'); eq(multi[1],'foo'); eq(multi[2],'bar')
assert(b:SendMessage('end')); eq(s.sent,'endabab');b:Disconnect()

local nul={}
local n=TCP.Connect('127.0.0.1',54000,{
    delimiter='\0',onMessage=function(msg) nul[#nul+1]=msg end
})
local z=socket();z:ready();z:feed('hi\0bye\0')
eq(nul[1],'hi');eq(nul[2],'bye')
assert(n:SendMessage('ok'));eq(z.sent,'ok\0');n:Disconnect()

-- Raw mode returns the bytes unchanged.
local raw
local r=TCP.Connect('127.0.0.1',54000,{
    mode='raw',delimiter='|',onData=function(bytes)raw=bytes end
})
local rs=socket();rs:ready();rs:feed('a|b\0c');eq(raw,'a|b\0c');r:Disconnect()
local valid=pcall(function() TCP.Connect('x',1,{delimiter=''}) end)
eq(valid,false)
local default=TCP.Connect('127.0.0.1',54000)
local ds=socket();ds:ready()
assert(default:SendMessage('hey'));eq(ds.sent,'hey\n');default:Disconnect()

print('PASS: simple Connect API, literal delimiters, raw mode')
