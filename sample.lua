-- usage example

local client = TCP.client.new()

client:set_line_terminator("\n")
client:on_connect(somefunction)
client:on_disconnect(somefunction)
client:on_message(somefunction)
client:connect(host, port)
client:disconnect()
