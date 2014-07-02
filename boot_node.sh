#!/bin/bash

#   This file is part of Greenginecode.
#   Copyright (c) 2012, Remy Dernat, CNRS
#   Greenginecode is free software. This software is governed 
#   by the CeCILL license under French law and abiding 
#   by the rules of distribution of free software.
#   As a counterpart to the access to the source code 
#   and  rights to copy,modify and redistribute granted 
#   by the license, users are provided only with a 
#   limited warranty and the software's author, the 
#   holder of the economic rights, and the successive 
#   licensors  have only  limited liability.See the 
#   files license-en.txt or license-fr.txt for more 
#   details.

is_rocks_cl=`which rocks`
ether_wake=`which ether-wake 2> /dev/null`
etherwake=`which etherwake 2> /dev/null`
if [[ ! $etherwake ]];then
	if [[ $ether_wake ]];then
		etherwake=$ether_wake
	else
		echo "No ether-wake command. Script could not run...";
		exit 2
	fi;
fi;

args=("$@")
usage="usage : boot_node.sh node-name"

if [ "$1" == "-h" ] || [ "$1" == "--help" ];then
	echo $usage;
elif [[ $1 ]]; then
	for node in ${args[*]}
	do
		if [[ $is_rocks_cl ]];then
			mac=`rocks list host interface |grep -w $node|grep "private" |awk '{print $4}'`
			myhost=`echo $HOSTNAME | cut -f1 -d"."`
			iface=`rocks list host interface |grep -w $myhost|grep "private" |awk '{print $3}'`
		else
			#try to determine MAC adress through arp table
			mac=`arp |grep -w $node |awk '{print $3}'`
			#iface=`arp |grep -w $node |awk '{print $5}'`
			iface="eth0"
		fi;
		echo "Booting $node on interface $iface with 'ether-wake $mac -i $iface'"
		$etherwake $mac -i $iface
	done
else
	echo $usage
fi;
