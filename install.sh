#!/bin/bash
echo ">>> stopping catepod"
kill `ps ax |grep catepod |awk -F . '{print $1}'|awk '{print $1}'` &> 0
#killall catepod &> /dev/null
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
perl catepod /etc/catepod.jsn
echo ">>> done."
killall hlds_run
killall hlds_i686
