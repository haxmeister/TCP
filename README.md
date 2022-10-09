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
local client = TCP.client.new {
    ['host'] = "111.11.111.11", -- a string
    ['port'] = 1111 -- a number
}
```
where the host and port are required, there are also optional parameters that allows you to initialize everything at once with the following available parameters:
```
attemptsMax  = <number>   --- maximum number of times it will try to reconnect
reconTime    = <number>   --- number of seconds before it attempts to reconnect
onMessage    = <function> --- when message received
onDisconnect = <function> --- when disconnected
onConnect    = <function> --- when connected
onReconnect  = <function> --- when a reconnect attempt starts-receives attempt number
onGiveup     = <function> --- when all reconnect attempts are exhausted
onFail       = <function> --- when a connection attempt fails
```
for example:

```lua
dofile("../TCP/client.lua")

local client = TCP.client.new {
    ['host']         = "111.11.111.11",
    ['port']         = 1111,
    ['onConnect']    = somefunction,
    ['onDisconnect'] = somefunction,
    ['onMessage']    = somefunction
}
```

or you may initialize all the optional parameters after the object has been created
for example:
```lua
dofile("../TCP/client.lua")

local client = TCP.client.new()
client['onConnect'] = somefunction
```
now we can call the methods in our code to put it to work for us
for example:
```lua
client:Connect(host,port)
client:Send("some message to send")
client:Disconnect()
```
### Notes
This library assumes the industry standard line ending of /r/n on incoming messages currently
The Send() method does not append /r/n at the end of the string before sending it over the connection. This must be implemented by the user according to expected behaviour by the listener.
