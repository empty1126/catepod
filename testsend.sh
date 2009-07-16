#!/bin/bash

echo '{"command":"start", "path":"/home/gameserver/27000/" ,"game":"counter-strike-source", "port":27000, "install":false, "params":["-debug ", "-game ", "cstrike", "-ip ", "85.214.43.91 ", "+map ", "de_dust2 ", "+port ", "27000 ", "+maxplayers ", "12 ", "-tickrate ", "33"]}' > /tmp/gswi/socket
