# TCP
TCP libraries for the Vendetta Online plugin system

## USAGE

```lua
local client = TCP.client.new(<table>)
```
where the <table> is an optional parameter that allows you to initialize everything at once with the following available parameters:
```
debug = <boolean>
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

client.set_line_terminator("\n")
client.on_connect(somefunction)
client.on_disconnect(somefunction)
client.on_message(somefunction)
```
now we can call the methods in our code to put it to work for us
for example:
```lua
client.connect(host,port)
client.send("some message to send")
client.disconnect()
```
