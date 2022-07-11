# TCP
TCP libraries for the Vendetta Online plugin system
### TODO: 
Waiting on recommendations suggestions
## REQUIREMENTS
This library requires no external libraries and is a layer directly on top of the built-in TCP function in Vendetta Online's plugin system. By using this interface instead of the built-in function, you gain proper buffering for your TCP connections.
## INSTALLATION
Drop the TCP folder into your vendetta online plugins folder and call it using `dofile("../TCP/client.lua")`. This will make the library available to all your plugins using the same approach
## USAGE

```lua
dofile("../TCP/client.lua")
local client = TCP.client.new(<table>)
```
where the \<table\> is an optional parameter that allows you to initialize everything at once with the following available parameters:
```
debug    = <boolean>
line_end = <string>
onCon    = <function>
onDis    = <function>
onMsg    = <function>
```
for example:

```lua
dofile("../TCP/client.lua")

local client = TCP.client.new {
    ['debug']    = true,
    ['line_end'] = "\n",
    ['onCon']    = somefunction,
    ['onDis']    = somefunction,
    ['onMsg']    = somefunction
}
```

or you may initialize all the parameters after the object has been created
for example:
```lua
dofile("../TCP/client.lua")

local client = TCP.client.new()

client:set_line_terminator("\n")
client:on_connect(somefunction)
client:on_disconnect(somefunction)
client:on_message(somefunction)
```
now we can call the methods in our code to put it to work for us
for example:
```lua
client:connect(host,port)
client:send("some message to send")
client:disconnect()
```
