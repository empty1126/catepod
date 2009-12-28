#!/bin/bash
echo ">>> stopping catepod"
killall catepod &> /dev/null
echo ">>> compilling catepod"
perltidy -b -l 120 catepod && rm catepod.bak
perl -c catepod || (echo "catepod didn't compile"; exit)
echo ">>> done, give rights to gameserver"
chown -R gameserver:gameserver /home/Catepod/
chown -R gameserver:gameserver /home/gameserver/
echo ">>> done, installing catepod to system"
cp catepod /usr/bin/ -vv
cp Catepod/ "/usr/lib/perl5/" -vvr
cp catepod.jsn /etc/ -vv
echo ">>> done, starting daemon"
screen -d -m -S catepod ./catepod /etc/catepod.jsn
echo ">>> done."
killall hlds_run
killall hlds_amd
