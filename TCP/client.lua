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
          writing buffering code for their tcp connected plugins

NOTE:     This is not a drop in replacement for the original due to a changed interface!
]]

-- A table to contain our awesomeness
declare ("TCP", TCP or {})
TCP.client = {}
--creates a new tcp client with buffering built in
function TCP.client.new(args)
    args = args or {}

    --------------------- PRIVATE VARIABLES --------------------------

    local tcp            = TCPSocket() --- The underlying socket object
    local in_buffer      = ''          --- a string of incoming text
    local out_buffer     = {}          --- a list of lines waiting to be sent

    --------------------- PUBLIC VARIABLES ---------------------------

    local self = {
        ['debug']     = args['debug']     or false,
        ['line_end']  = args['line_end']  or "\n",
        ['onMsg']     = args['onMsg']     or function() end, --- when message received
        ['onDis']     = args['onDis']     or function() end, --- when disconnected
        ['onCon']     = args['onCon']     or function() end, --- when connected
        ['host']      = args['host']      or false,
        ['port']      = args['port']      or false
    }

    -- lets type check the arguments here to catch early errors
    assert(type(self['debug'])    == "boolean", "debug parameter to new() requires a boolean but received "..type(self['debug']))
    assert(type(self['line_end']) == "string", "line_end parameter to new() requires a string but received "..type(self['line_end']))
    assert(type(self['onMsg'])    == "function", "onMsg parameter to new() requires a function but received "..type(self['onMsg']))
    assert(type(self['onDis'])    == "function", "onDis parameter to new() requires a function but received "..type(self['onDis']))
    assert(type(self['onCon'])    == "function", "onCon parameter to new() requires a function but received "..type(self['onCon']))
    assert(type(self['host'])     == "string", "host parameter to new() requires a string but received "..type(self['host']))
    assert(type(self['port'])     == "number", "port parameter to new() requires a number but received "..type(self['port']))

    ------------------ PRIVATE FUNCTION PROTOTYPES ---------------------

    local msg_received
    local write_line_from_out_buffer
    local debugMsg
 
    ---------------------------- METHODS -------------------------------

    -- connects as a client to the given host and port
    -- returns true if successful, false if not
    function self:connect()
        -- one connection per object please
        -- so lets make sure we disconnect if we are already connected
        if (self:is_connected()) then
            debugMsg("connect called but already connected")
            return true
        end
        -- callback when data is available for reading. Disables callback if fn is nil.
        tcp:SetReadHandler(msg_received)

        -- callback when output buffer space is available for writing,
        -- or when the connection completes. Disables callback if fn is nil.
        tcp:SetWriteHandler(write_line_from_out_buffer)

        -- attempt to connect to host and port
        local success,err = tcp:Connect(self['host'], self['port'])

        -- if we can't connect then return false
        if not success then
            err = err or '' -- make sure it isn't nil before sending debug msg
            debugMsg("failed to connect - "..err)
            return false
        else
            -- we made it here so we must be connected
            -- lets check to see for sure because sometimes the
            -- underlying Connect function lies
            if self:is_connected() then
                debugMsg("connected successfully ")
                -- call the users callback function for on_connect
                self:onCon()
            else
                -- looks like it lied to us
                return false
            end

            -- we made it to the end so must have been successful
            return true
        end
    end

    -- turns on debugging messages
    function self:debug(value)
        assert(type(value) == "boolean", "debug function is supposed to receive a boolean (true or false) but instead got: "..type(value))
        self.debug = value
    end

    -- disconnects the client
    function self:disconnect()
        debugMsg("attempting to disconnect..")
        repeat
            tcp:Disconnect()
        until self:is_connected() == false
        debugMsg("disconnected successfully")

        self:onDis()
    end

    -- checks for peer name as a way to see if we are connected or not
    -- returns true if the connection appears valid
    function self:is_connected()
        local peer = tcp:GetPeerName()
        if (peer ~= nil)then
            debugMsg("is_connected says: still connected to peer "..peer)
            return true
        else
            return false
        end
    end

    -- set the callback function that will be executed when this client
    -- establishes a connection
    function self:on_connect(callback)
        assert(type(callback) == "function", "on_connect is supposed to receive a function but instead got: "..type(callback))

        -- save the user's callback function in the object
        self.onCon = callback
    end

    -- set the callback function that will be executed when a connected
    -- client is disconnected, or this client disconnects
    function self:on_disconnect(callback)
        assert(type(callback) == "function", "on_disconnect is supposed to receive a function but instead got: "..type(callback))

        -- save the user's callback function in the object
        self.onDis = callback
    end

    -- set the callback function that will be executed when a message
    -- recieved on the socket and do the work of buffering incoming messages
    function self:on_message(callback)
        assert(type(callback) == "function", "on_message is supposed to receive a function but instead got: "..type(callback))

        -- save the user's callback function in the object
        self.onMsg = callback
    end

    -- send a line to the connection
    function self:send(line)
        assert(type(line) == "string", "send is supposed to receive a string but instead got: "..type(line))
        debugMsg("send method received - "..line)

        -- if we got here but are not connected then
        -- the user forgot to connect or lost connection
        if not self:is_connected() then
            return
        end

        -- add the line to the out buffer for sending
        -- (this will add the line to the tail or bottom of the queue
        table.insert(out_buffer, line)

        -- now let's try sending the line
        write_line_from_out_buffer()
    end

    -- sets the string that will be used to determine how to distinguish
    -- different messages in the queue, this defaults to \n
    function self:set_line_terminator(arg)
        assert(type(arg) == "string", "line terminator must be a string but instead got: "..type(arg))
        self.line_end = arg
    end

    -- sets the host and port to a different number
    function self:set_host_port(host, port)
        assert(type(host) == 'string', "set_host_port requires a string for the host address but received: "..type(host))
        assert(type(port) == 'number', "set_host_port requires a number for the port but instead received: "..type(port))
        self.host = host
        self.port = port
    end
    --------------------- PRIVATE FUNCTIONS --------------------------

    -- prints debug messages if debug is set to true
    debugMsg = function(msg)
        if self.debug == true then
            --print(debug.getinfo(1).name..": "..msg)
            msg = msg or ''
            print("Client debug: "..msg)
        end
    end

    -- internal callback for when a message is received on the socket
    msg_received = function()

        -- attempt to receive from socket
        local msg, errcode = tcp:Recv()

        -- check if the message was empty or absent
        if (msg) then

            -- message received, lets add it to the buffer
            in_buffer = in_buffer..msg or msg
        else
            if (errcode) then
                debugMsg("caught error code on recv socket: "..errcode)

                -- fetch the error message from the socket
                local err = tcp:GetSocketError()
                debugMsg(err)
                -- we disconnect since we have errors receiving
                self:disconnect(err)

                -- exit the function, because of erors or because we're done.
                return
            end
        end

        -- now lets loop through buffer and call the on_message callback
        -- for every portion we extract that ends with the line terminator
        local match
        repeat
            in_buffer, match = string.gsub( in_buffer, "^([^"..self['line_end'].."]*)"..self['line_end'],

                -- we found text in the buffer that ends with the delimiter
                function(line)  -- take the captured text in the "line" argument
                    -- send the captured text to the on_message callback
                    -- and trap any errors for safety
                    pcall(self.onMsg, self, line)
                    return ''
                end
            )
        -- do it again until there's no more complete lines
        until match==0

    -- all done for now!
    end

    -- tries to send the next line in the out buffer
    -- re-schedules itself to run asyncronously when it fails to complete
    write_line_from_out_buffer = function()

        -- if we got here but are not connected then let's avoid
        -- an error on the underlying layer by bailing out now
        if not self:is_connected() then
            return
        end

        -- check if the out_buffer is empty (no lines to send)
        if (not next(out_buffer) ) then
            debugMsg ("out buffer is now empty")
            -- nothing to send, we are done so let's
            -- remove the buffer check from the loop
            tcp:SetWriteHandler(nil)
            return
        end

        -- try to send the next line in the "out buffer"
        local chars_sent = tcp:Send( out_buffer[1] )

        -- if it failed to send the message at all, we find out here
        if  (chars_sent == -1) then
            local err = tcp:GetSocketError() or chars_sent
            -- could have been an EWOULDBLOCK but we can't tell
            debugMsg("failed to send message with code: "..err)
            -- schedule this function to try again when the the buffer is ready
            tcp:SetWriteHandler(write_line_from_out_buffer)

        -- if it sent the string but only sent a portion of it, we find out here
        elseif (chars_sent < string.len( out_buffer[1] ) ) then
            debugMsg("sent partial string")
            -- because only a portion of this line has been seent,
            -- we will remove the portion of the line that was sent and
            -- leave the rest to be sent when the loop comes back around
            out_buffer[1] = string.sub(out_buffer[1], chars_sent+1, -1)

            -- schedule this function to try again when the the buffer is ready
            tcp:SetWriteHandler(write_line_from_out_buffer)
        else
            debugMsg("successfuly sent - "..out_buffer[1])

            -- we land here because it appears the entire line was sent
            -- so lets remove that line from the top of the out buffer
            table.remove( out_buffer,1 )
            -- schedule this function to run again to send the next line
            tcp:SetWriteHandler(write_line_from_out_buffer)
        end
    end

    return self
end









