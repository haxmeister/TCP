# TCP
TCP libraries for the Vendetta Online plugin system

## USAGE
```lua
local client = TCP.client.new()

client.set_line_terminator("\n")
client.do_on_connect(somefunction)
client.do_on_disconnect(somefunction)
client.do_on_message(somefunction)
client.connect(host,port)
client.send("some message to send")
client.disconnect()

--optional full initialization at once:

local client = TCP.client.new {
    ['line_end'] = "\n",
    ['on_connect'] = somefunction,
    ['on_disconnect'] = somefunction,
    ['on_message'] = somefunction
}

client.connect(host,port)
client.send("some message")
client.disconnect()
```
