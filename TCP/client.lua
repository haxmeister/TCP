-- Vendetta Online TCP client wrapper.
-- Uses only VO's native TCPSocket and ordinary Lua tables (no metatables).
-- Copyright (c) 2022 Joshua S. Day. MIT license; see LICENSE.
-- The native TCPSocket interface was documented by Andy Sloane (a1k0n).

TCP = TCP or {}
TCP.Client = TCP.Client or {}
TCP.Client._active = TCP.Client._active or {} -- prevent active sockets from being collected

local function report(message)
    local text = '[TCP] ' .. tostring(message)
    if type(log_print) == 'function' then log_print(text) else print(text) end
end

local function notify(self, name, ...)
    local callback = self[name]
    if type(callback) ~= 'function' then return end
    local ok, err = pcall(callback, self, ...)
    if not ok then report(name .. ' callback failed: ' .. tostring(err)) end
end

local function would_block(err)
    if err == 11 or err == 35 or err == 10035 then return true end
    if err == nil then return false end
    local description = string.upper(tostring(err))
    return string.find(description, 'BLOCK', 1, true) ~= nil
        or string.find(description, 'AGAIN', 1, true) ~= nil
end

local function clear_queue(self)
    self.queue = {}
    self.head, self.tail, self.offset = 1, 0, 1
    self.pendingBytes = 0
end

local function stop(self, reason, is_error)
    if self.state == 'disconnected' then return end
    local was_connected = self.state == 'connected'
    local socket = self.socket
    self.state = 'disconnected'
    self.generation = self.generation + 1
    self.socket = nil
    self.writeCallback = nil
    self.flushing = false
    clear_queue(self)
    self.input = ''
    TCP.Client._active[self] = nil

    if socket then
        pcall(function() socket:SetReadHandler(nil) end)
        pcall(function() socket:SetWriteHandler(nil) end)
        local ok, err = pcall(function() socket:Disconnect() end)
        if not ok then report('native Disconnect failed: ' .. tostring(err)) end
    end
    if is_error then notify(self, 'onError', reason) end
    if was_connected then notify(self, 'onDisconnect', reason) end
end

local function flush(self)
    if self.state ~= 'connected' or self.flushing then return end
    self.flushing = true
    local socket = self.socket
    local generation = self.generation
    local budget = self.writeBudget
    while self.state == 'connected' and self.generation == generation
          and self.head <= self.tail and budget > 0 do
        local chunk = self.queue[self.head]
        local remaining = string.sub(chunk, self.offset)
        local piece = string.sub(remaining, 1, math.min(budget, 65536))
        local ok, sent = pcall(function() return socket:Send(piece) end)
        if not ok or type(sent) ~= 'number' or sent < -1 or sent > #piece then
            self.flushing = false
            stop(self, 'send failed: ' .. tostring(sent), true)
            return
        end
        -- Native Send may return -1 for either would-block or a hard error.
        if sent == -1 then
            local error_ok, socket_error = pcall(function() return socket:GetSocketError() end)
            if error_ok and socket_error ~= nil and socket_error ~= 0
               and not would_block(socket_error) then
                self.flushing = false
                stop(self, 'send failed: ' .. tostring(socket_error), true)
                return
            end
            break -- would block (or no usable native error); retry on write readiness
        end
        if sent == 0 then break end
        self.pendingBytes = self.pendingBytes - sent
        budget = budget - sent
        if sent == #remaining then
            self.queue[self.head] = nil
            self.head = self.head + 1
            self.offset = 1
        else
            self.offset = self.offset + sent
            if sent < #piece then break end -- partial send; wait for the next write event
        end
    end
    self.flushing = false
    if self.state ~= 'connected' or self.generation ~= generation then return end
    if self.head > self.tail then
        clear_queue(self)
        socket:SetWriteHandler(nil)
    else
        socket:SetWriteHandler(self.writeCallback)
    end
end

local function received(self, data, generation)
    if self.mode == 'raw' then
        notify(self, 'onData', data)
        return
    end
    self.input = self.input .. data
    while self.state == 'connected' and self.generation == generation do
        local newline = string.find(self.input, '\n', 1, true)
        if not newline then break end
        local line = string.sub(self.input, 1, newline - 1)
        self.input = string.sub(self.input, newline + 1)
        if string.sub(line, -1) == '\r' then line = string.sub(line, 1, -2) end
        if #line > self.maxLineBytes then
            stop(self, 'received line exceeds maxLineBytes', true)
            return
        end
        notify(self, 'onLine', line)
    end
    -- A trailing CR may be followed by LF in the next read.
    -- maxLineBytes limits the decoded line, not its CRLF terminator.
    if self.state == 'connected' and self.generation == generation then
        local pending = #self.input
        if pending > self.maxLineBytes and not
           (pending == self.maxLineBytes + 1 and
            string.sub(self.input, -1) == '\r') then
            stop(self, 'received line exceeds maxLineBytes', true)
        end
    end
end

function TCP.Client.New(options)
    assert(type(options) == 'table', 'TCP.Client.New expects an options table')
    assert(type(options.host) == 'string', 'host must be a string')
    assert(type(options.port) == 'number', 'port must be a number')
    local self = {
        host = options.host, port = options.port,
        mode = options.mode or 'line',
        onConnect = options.onConnect,
        onDisconnect = options.onDisconnect,
        onError = options.onError,
        onLine = options.onLine or options.onMessage,
        onData = options.onData,
        maxLineBytes = options.maxLineBytes or 65536,
        maxPendingBytes = options.maxPendingBytes or 1048576,
        writeBudget = options.writeBudget or 65536,
        state = 'disconnected', generation = 0,
        flushing = false, socket = nil
    }
    assert(self.mode == 'line' or self.mode == 'raw', 'mode must be line or raw')
    assert(self.maxLineBytes > 0 and self.maxPendingBytes > 0 and self.writeBudget > 0,
           'buffer limits must be positive')
    clear_queue(self)
    self.input = ''

    function self:Send(data)
        if self.state ~= 'connected' and self.state ~= 'connecting' then
            return nil, 'not connected'
        end
        if type(data) ~= 'string' then return nil, 'Send expects a string' end
        if #data == 0 then return true end
        if self.pendingBytes + #data > self.maxPendingBytes then
            return nil, 'outgoing buffer is full'
        end
        self.tail = self.tail + 1
        self.queue[self.tail] = data
        self.pendingBytes = self.pendingBytes + #data
        if self.state == 'connected' then flush(self) end
        return true
    end

    function self:SendLine(line)
        if type(line) ~= 'string' then return nil, 'SendLine expects a string' end
        if string.find(line, '\n', 1, true) then return nil, 'line contains newline' end
        return self:Send(line .. '\r\n')
    end

    function self:Disconnect()
        stop(self, 'local disconnect', false)
    end

    function self:Connect(host, port)
        if host ~= nil then assert(type(host) == 'string', 'host must be a string') end
        if port ~= nil then assert(type(port) == 'number', 'port must be a number') end
        if host ~= nil then self.host = host end
        if port ~= nil then self.port = port end
        if self.state ~= 'disconnected' then
            local previous_generation = self.generation
            stop(self, 'replaced', false)
            -- onDisconnect may itself start another connection.
            if self.generation ~= previous_generation + 1
               or self.state ~= 'disconnected' then
                return nil, 'connection changed during onDisconnect'
            end
        end
        self.generation = self.generation + 1
        local generation = self.generation
        local socket = TCPSocket()
        self.socket = socket
        self.state = 'connecting'
        clear_queue(self)
        self.input = ''
        TCP.Client._active[self] = true

        local function current()
            return self.generation == generation and self.socket == socket
        end
        local function on_read()
            if not current() or self.state ~= 'connected' then return end
            local ok, data, err = pcall(function() return socket:Recv() end)
            if not ok then
                stop(self, 'receive failed: ' .. tostring(data), true)
            elseif data == nil then
                -- Old VO API reports nil,nil for 'nothing available'.
                -- EAGAIN/WOULDBLOCK may also appear as numeric errno.
                if err == 0 then
                    stop(self, 'peer closed connection', false)
                elseif err ~= nil and not would_block(err) then
                    stop(self, 'receive failed: ' .. tostring(err), true)
                end
            elseif data == '' then
                stop(self, 'peer closed connection', false)
            else
                received(self, data, generation)
            end
        end
        local function on_write()
            if not current() then return end
            if self.state == 'connecting' then
                local ok, peer = pcall(function() return socket:GetPeerName() end)
                if not ok or not peer then
                    local err_ok, err = pcall(function() return socket:GetSocketError() end)
                    stop(self, 'connect failed: ' .. tostring(err_ok and err or peer), true)
                    return
                end
                self.state = 'connected'
                socket:SetReadHandler(on_read)
                notify(self, 'onConnect')
            end
            if current() and self.state == 'connected' then flush(self) end
        end
        self.writeCallback = on_write
        socket:SetWriteHandler(on_write)
        local ok, success, err = pcall(function() return socket:Connect(self.host, self.port) end)
        if not ok or not success then
            stop(self, 'connect failed: ' .. tostring(ok and err or success), true)
            return nil, err or success
        end
        return true -- connect *started*, not yet completed
    end

    return self
end

return TCP.Client
