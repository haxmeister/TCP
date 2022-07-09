# TCP
TCP libraries for the Vendetta Online plugin system
### TODO: 
* implement line terminator seeding functionality
* add more and better error messages and checking
## REQUIREMENTS
This library requires no external libraries and is a layer directly on top of the built-in TCP function in Vendetta Online's plugin system. By using this interface instead of the built-in function, you gain proper buffering for your TCP connections.
## INSTALLATION
Drop the TCP folder into your vendetta online plugins folder
## USAGE

```lua
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
