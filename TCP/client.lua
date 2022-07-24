--[[
Author:   Joshua S. Day (haxmeister) haxmeister@hotmail.com

Website:  www.haxmeister.com

License:  free for use/copy/modification/and redistribution
          with latest MIT license 2022 https://mit-license.org/

Addendum: nerd cred required, please mention the name of the authors
          who's code you have modified if you make your own mod

Credits:  Andy Sloane (a1k0n)

Purpose:  This is a re-write of the original socket abstraction
          that was written by Andy Sloane, a1k0n, one of the Vendetta
          Online developers over at Guild Software
          http://www.guildsoftware.com/company.html
          it is meant to abstract plugin writers from the minutia of
          writing buffering code for their socket connected plugins

NOTE:     This is not a drop in replacement for the original due to a changed interface!
]]

declare ("TCP", TCP or {})
TCP.Client = {}
function TCP.Client.New(argTable) -- accepts a table
    local object = {}
    object['socket']       = TCPSocket()
    object['timer']        = Timer()
    object['connected']    = false
    object['host']         = argTable['host']
    object['port']         = argTable['port']
    object['attemptsMax']  = argTable['attemptsMax'] or 5
    object['reconnect']    = argTable['reconnect'] or true
    object['attempts']     = 0
    object['reconTime']    = argTable['reconTime'] or 10 --seconds
    object['inBuf']        = ''
    object['outBuf']       = {}
    object['onMessage']    = argTable['onMessage']   or function() end --- when message received
    object['onDisconnect'] = argTable['onDisconnect']or function() end --- when disconnected
    object['onConnect']    = argTable['onConnect']   or function() end --- when connected
    object['onReconnect']  = argTable['onReconnect'] or function() end --- when a reconnect attempt starts-receives attempt number
    object['onGiveup']     = argTable['onGiveup']    or function() end --- when all reconnect attempts are exhausted
    object['onFail']       = argTable['onFail']      or function() end --- when a connection attempt fails
    object['debugging']    = false
    --------------------SOCKET METHODS-----------------------
    --object:Connect(host,port)
    --object:Disconnect()
    --object:Listen() -- listen on a port (servers)
    --object:Accept() -- returns new connection object (servers)
    --object:SetConnectHandler(fn) -- when a new incoming connection (servers)
    --object:SetReadHandler(fn)
    --object:SetWriteHandler(fn) -- buffer ready for writing or connection completes?
    --object:Send(string) -- returns num of bytes sent
    --object:Recv() -- returns the message, and error code
    --object:GetSocketError() --returns string "error"
    --object:GetPeerName() -- returns string "host:port"

    function object:Send(line)
        assert(type(line) == "string", "send is supposed to receive a string but instead got: "..type(line))
        self:debugMsg("object:send() received - "..line)
        if not self:_ConnStatus() then
            self:debugMsg("can't send if not connected, clearing send buffer")
            self.outBuf = {}
            return
        end
        -- add the line to the out buffer for sending
        -- (this will add the line to the tail or bottom of the queue
        table.insert(self.outBuf, line)
        self.socket:SetWriteHandler(function() self:WriteHandler() end)
        self:WriteHandler()
    end

    function object:ConnectionHandler()
        self:debugMsg("TCP connection handler")
        local isconnected, err = self:_ConnStatus()
        if isconnected then
            self.attempts = 0
            self:debugMsg("TCP connection handler setting write handler to write handler")
            self.socket:SetWriteHandler(function() self:WriteHandler() end)
            self:debugMsg("TCP connection handler setting read handler to readHandler")
            self.socket:SetReadHandler(function() self:ReadHandler() end)
            self:onConnect()
        else
            self:debugMsg("TCP connection handler says connection bad, now onfail and disconnect handler")
            self:onFail(err)
            self:Disconnect()
            self:DisconnectHandler()
        end
    end

    function object:WriteHandler()
        self:debugMsg("TCP writehandler")

        if (not next(self.outBuf) ) then
            self:debugMsg("outbuf empty nothing to write")
            self.socket:SetWriteHandler(nil)
            return
        end

        local chars_sent = self.socket:Send( self.outBuf[1] )

        -- if it failed to send the message at all, we find out here
        if  (chars_sent == -1) then
            local err = self.socket:GetSocketError() or chars_sent
            -- could have been an EWOULDBLOCK but we can't tell
            self:debugMsg("writeHandler failed to send message with err: "..tostring(err))
            -- schedule this function to try again when the the buffer is ready
            self.socket:SetWriteHandler(function() self:WriteHandler() end)

        -- if it sent the string but only sent a portion of it, we find out here
        elseif (chars_sent < string.len( self.outBuf[1] ) ) then
            self:debugMsg("writeHandler sent partial string")
            -- because only a portion of this line has been seent,
            -- we will remove the portion of the line that was sent and
            -- leave the rest to be sent when the loop comes back around
            self.outBuf[1] = string.sub(self.outBuf[1], chars_sent+1, -1)

            -- schedule to try again when the the buffer is ready
            self.socket:SetWriteHandler(function() self:WriteHandler() end)
        else
            self:debugMsg("writeHandler successfuly sent - "..self.outBuf[1])

            -- we land here because it appears the entire line was sent
            -- so lets remove that line from the top of the out buffer
            table.remove( self.outBuf,1 )
            -- schedule this function to run again to send the next line
            self.socket:SetWriteHandler(function() self:WriteHandler() end)
        end
    end

    function object:ReadHandler()
        self:debugMsg("TCP read handler")

        local msg, errcode = self.socket:Recv()

        if not msg then
            if not errcode then
                return
            end

            local err = self.socket:GetSocketError()
            self:debugMsg("TCP read handler found errcode: "..tostring(errcode).." and sock error: "..tostring(err))
            self:Disconnect()
            self:DisconnectHandler(err)
            return
        end

        self:_readToBuffer(msg)

        local match
        repeat
            self.inBuf,match = string.gsub(self.inBuf, "^([^\r\n]*)\r\n", function(line)
            pcall(self.onMessage,self, line)
            return ''
            end)
        until match==0
        return true
    end

    function object:DisconnectHandler()
        self:debugMsg("TCP disconnect handler")

        -- are we connected or not?
        local isconnected, err = self:_ConnStatus()
        if isconnected then
            self.connected = true
            return
        end
        -- we are disconnected supposedly but let's call this again to clear it out
        self:debugMsg("TCP disconnect handler calling Disconnect()")
        self:Disconnect()
        -- leave it we are not allowed to reconnect
        if not self.reconnect then return end

        -- reconnect loop attempts to maximum allowed
        self.timer:SetTimeout(self.reconTime * 1000,function()
                self:debugMsg("TCP reconnect timer callback")
                self.attempts = self.attempts + 1
                self:onReconnect(self.attempts)
                if self.timer:IsActive() then return end
                if self:_ConnStatus() then
                    self:debugMsg("TCP reconnect timer callback says connected ")
                    self.connected = true
                    self.timer:Kill()
                    return
                elseif self.attempts ~= self.attemptsMax then
                    self:debugMsg("TCP reconnect timer callback says more attempts available")
                    self:Disconnect()
                    self:Connect()
                    self.timer:SetTimeout(self.reconTime * 1000)
                    return
                else
                    self:debugMsg("TCP reconnect timer callback says out of tries")
                    self.timer:Kill()
                    self:Disconnect() -- for good measure??
                    self:onGiveup()
                    self.attempts = 0
                    return
                end
            end
        )
    end

    function object:Connect()
        self:debugMsg("TCP connect")
        if self.connected then
            self:Disconnect()
        end
        self:debugMsg("TCP connect setting write handler to connection handler")
        self.socket:SetWriteHandler(function() self:ConnectionHandler() end)
        --self:debugMsg("TCP connect setting read handler to readHandler")
        --self.socket:SetReadHandler(function() self:ReadHandler() end)
        local success, err = self.socket:Connect(self.host, self.port)

        if success then
            self:debugMsg("TCP connect call success")
            self.connected = true
            self:debugMsg("TCP waiting for connection to complete")
        end

        if err then
            self.connected = false
            self:debugMsg("TCP connect call fail with error "..err)
        end

        --self:debugMsg("TCP connect setting timer")
        --self.timer:SetTimeout(self.reconTime * 1000, function() self:DisconnectHandler() end)
    end

    function object:Disconnect()
        self:debugMsg("TCP disconnect")
        self.connected = false
        self.socket:Disconnect()
        self.socket = nil
        self.socket = TCPSocket()
        self:onDisconnect()
    end

    function object:_ConnStatus()
        local errormsg = self.socket:GetSocketError()
        local peer = self.socket:GetPeerName()
        local status

        if peer then
            self:debugMsg("---status connected to "..tostring(peer).." with errors "..tostring(errormsg))
            status = true
        end

        if errormsg then
            self:debugMsg("---status disconnected with errors "..tostring(errormsg))
            status = false
        end

        return status, errormsg
    end

    function object:_readToBuffer(msg)
        self.inBuf = self.inBuf..msg or msg
    end

    function object:debugMsg(msg)
        if self.debugging then
            print("[TCP] "..msg)
        end
    end

    function object:Debug(value)
        self.debugging = value
    end
    ------------------------INITIALIZE--------------------------

    return object
end








