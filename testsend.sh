#!/bin/bash

#-game cstrike -ip 85.214.43.91 +map de_dust2 +maxplayers 12 -port 27015  -tickrate 125 
echo '{"command":"start", "game":"counter-strike-source", "port":27000, "install":false, "params":["-game", "cstrike", "-ip", "85.214.43.91", "+map", "de_dust2", "+maxplayers", "12", "-tickrate", "33"]}' > /tmp/gswi/socket
