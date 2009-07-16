#!/bin/bash
echo ">>> stopping catepod"
killall catepod &> /dev/null
echo ">>> compilling catepod"
perltidy -b -l 120 catepod && rm catepod.bak
perl -c catepod || (echo "catepod didn't compile"; exit)
echo ">>> installing catepod to system"
cp catepod /usr/bin/ -vv
cp Catepod/ /usr/lib/perl5/5.10.0 -vvr
cp catepod.jsn /etc/ -vv
echo ">>> done, starting daemon"
catepod /etc/catepod.jsn
echo ">>> done."
