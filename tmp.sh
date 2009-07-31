#!/bin/bash

export PLUG="/home/gameserver/29000/cstrike/addons/metamod/plugins.ini"

echo "nunU" > $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG
echo "nunU" >> $PLUG

cat $PLUG
sh testsend.sh
cat $PLUG
sh 2test.sh
cat $PLUG
