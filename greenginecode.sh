#!/bin/bash
#set -x

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


#######################################################################
## Script to boot node when needed and shutdown node when you do not ##
## need to get it running.                                           ##
## required : - Wake On LAN enable on every node managed by the code ##
##            - cleanhalt.sh and boot_node.sh                        ##
## download : http://kimura.univ-montp2.fr/redmine/projects/cluster-tools/repository
## move these scripts in /sbin                                       ##
##            - Grid Engine on every node                            ##
#######################################################################
## NB: If you have rocks cluster but rebooting a node will reinstall ##
## it, see configuration in FAQ (from general documentation) for     ##
## rocks cluster :                                                   ##
## http://www.rocksclusters.org/roll-documentation/base/[version]/faq-configuration.html#DISABLE-REINSTALL
#######################################################################


. /etc/greenginecode.conf
source $BINARIES

if [[ $ignore_nodes ]];then
    echo $ignore_nodes > $directory/ignore_nodes.txt
fi;


# run on first execution because tentakel is slow...
# to scan nodes again, delete the file $directory/nodes-wol-disable.txt
is_tentakel=`which tentakel`
if [[ $is_tentakel ]];then
    if [ ! -f $directory/nodes-wol-disable.txt ];then
        export HOME="/root/" # needed by tentakel
        tentakel "ethtool $eth | grep -i wake" |grep -B2 -i 'Wake-on: d' |awk '/compute/ {print $2}' | cut -d "(" -f1 > $directory/nodes-wol-disable.txt
        # try to change these nodes with Wake On LAN enable
        #(it must be enabled in network card boot option (BIOS or ctrl+... for NIC management interface at boot.))
        while read node
        do
            ssh $node "ethtool -s $eth wol g"
        done < $directory/nodes-wol-disable.txt
        # then rescan
        tentakel "ethtool $eth | grep -i wake" |grep -B2 -i 'Wake-on: d' |awk '/compute/ {print $2}' | cut -d "(" -f1 > $directory/nodes-wol-disable.txt
    fi;
fi;

if [[ $ignore_queues ]];then
    for ignorefile in $ignore_queues
        do
            rm -f $directory/$ignorefile.txt
    done
fi;

# Listing queues
queues=`qconf -sql`
#queues=`ls $SGE_ROOT/$SGE_CELL/spool/qmaster/cqueues/`
number_messages=0

function wakeup
{
   wakethem=`qhost -q | egrep -B$4 "$3.+au" |awk '{print $1}' |grep compute`
   i=0
   for node2wake in $wakethem
        do
            if [[ ! `grep -w $node2wake $1/nodes-wol-disable.txt` ]];then
                echo "$node2wake will be restart" >> $2/queue.log
                /sbin/boot_node.sh $node2wake
                test=0
                until [ `ping -c4 $node2wake |grep % |awk '{print $6}'` == "0%" ];do
                    # On my cluster, the previous command run in 5 seconds if it fails and 3 seconds on success.
                    # Lower or raise the following value if you want to change the reactivity of this test.
                    sleep 5
                    test=$((test+10))
                    if [ $test -gt $5 ];then
                        echo "$node2wake failed to restart after $timeout seconds" >> $2/queue.log
                        continue 2
                    fi;
                done;
                i=$((i+1))
            fi;
        if [ $i -eq $6 ];then
            break
        fi;
    done;
}

function poweroff
{
    curr_availability_lvl=$6

    echo "No waiting job and availabity level is maximum" >> $2/queue.log
    echo "The following nodes will be shutdown... : " >> $2/queue.log
    echo "Current avalaibility level : $curr_availability_lvl" >> $2/queue.log
    firstshoot=`cat $1/shutdown_priority.txt`
    # On next line egrep is just apply on nodes without any running jobs which belong to only one queue.
    #shutnodes=`egrep -B1 "[0/]?0/[0-9]+$" $1/$3.txt |grep compute |cut -d " " -f1`
    #for node in $shutnodes
    for node in $firstshoot
        do
            is_one_queue_member=`egrep -B1 "[0/]?0/[0-9]+$" $1/$3.txt |grep -w $node`
            # checking if node has WoL enable (1...) and : it is not a member of another queue, it is in priority list (...+1 = 2) and it is not in ignore list.
            if [[ `grep -w $node $1/* |wc -l` -eq 2 ]];then
                wakethem=`qhost -q | egrep -B$4 "$3.+au" |awk '{print $1}' |grep $node`
                if [[ ! $wakethem ]] && [[ $is_one_queue_member ]];then
                    job_array=`qstat -g d |grep -w $node` #check job-array
                    parallel_job=`qstat -g t |grep -w $node` #check parallel task
                    if [[ ! $job_array ]] && [[ ! $parallel_job ]];then
                        # checking node weight for minimum avalaibility lvl
                        nodeslots=`cat $1/$3.txt |grep -w $node | awk '{print $2}'`
                        nodeweight=`echo $nodeslots / $5 |bc -l`
                        curr_availability_lvl=`echo $curr_availability_lvl - $nodeweight |bc -l | cut -c 1-3`
                        curr_availability_lvl=`echo $curr_availability_lvl |sed -e "s|^\.|0\.|g"`
                        if [[ $curr_availability_lvl > $7 ]];then
                            echo $node >> $2/queue.log
                            /sbin/cleanhalt.sh $node -h now &> /dev/null
                        else
                            curr_availability_lvl=`echo $curr_availability_lvl + $nodeweight |bc -l | cut -c 1-3`
                            curr_availability_lvl=`echo $curr_availability_lvl |sed -e "s|^\.|0\.|g"`
                        fi;
                        echo "Current avalaibility level : $curr_availability_lvl" >> $2/queue.log
                        echo $curr_availability_lvl > $1/$3-avail-lvl.txt
                    fi;
                fi;
            fi;
    done
    echo $curr_availability_lvl > $1/$3-avail-lvl.txt
}


#function av_lvl
#{
#}


while :
do
    number_messages=`grep "$message2watch" $logfile2watch |wc -l`
    sleep $seconds & pid=$!
    for queue in $queues
        do
            scanfalse=`echo $ignore_queues | grep $queue`
            if [[ ! $scanfalse ]];then
                echo "--------------------------------------------------" >> $logdirectory/queue.log
                date "+%F %T" >> $logdirectory/queue.log
                echo $queue >> $logdirectory/queue.log

                # load on booted nodes
                #curr_load_lvl=`qstat -g c | tail -n +3 | grep $queue | awk '{print $2}'`

                qhost -q |grep -B$max_queues_node $queue |awk '/compute|\// {print $1, $3}' > $directory/$queue.txt

                waitings=`qstat -u \* -s p -q $queue | grep -cw 'qw'`

                total_slots=`qstat -g c | tail -n +3 | grep -w $queue | awk '{print $6}'`
                curr_avail_slots=`qstat -g c | tail -n +3 | grep -w $queue | awk '{print $5}'`
                curr_unavail_slots=`echo $total_slots - $curr_avail_slots |bc -l`

                curr_unavail_lvl=`echo $curr_unavail_slots / $total_slots | bc -l`
                #curr_availability_lvl=`echo "1 - $curr_load_lvl" | bc -l | cut -c 1-3`

                #if [ -r $directory/$queue-avail-lvl.txt ];then
                    #curr_availability_lvl=`cat $directory/$queue-avail-lvl.txt`
                #else
                curr_availability_lvl=`echo 1 - $curr_unavail_lvl | bc -l | cut -c 1-3`
                curr_availability_lvl=`echo $curr_availability_lvl |sed -e "s|^\.|0\.|g"`
                echo $curr_availability_lvl > $directory/$queue-avail-lvl.txt
                #fi;

                # node's order to halt (it depends of a given order or load) ... :
                if [[ $shutdown_priority ]] && [ ! -f $directory/shutdown_priority.txt ];then
                    echo "$shutdown_priority" > $directory/shutdown_priority.txt;
                elif [[ ! $shutdown_priority ]];then
                    qhost |awk '{print $1,$4}' |tail -n +4 | sort -k 2 -n|grep -wv "-" > $directory/shutdown_priority.txt
                fi;

                echo $waitings waitings jobs >> $logdirectory/queue.log
                echo $curr_avail_slots available slots >> $logdirectory/queue.log
                #echo total hosts : $n_hosts , total cpus : $total_cpus
                echo "current level (from 0 to 1(=100%)) of availability for this queue : "$curr_availability_lvl >> $logdirectory/queue.log

                if [ $waitings -gt 0 ] && [[ $curr_availability_lvl < $avail_min_lvl ]]; then
                    wakeup $directory $logdirectory $queue $max_queues_node $timeout $nb_wakeup_nodes
                elif [ $waitings -gt 0 ] && [[ $curr_availability_lvl > $avail_min_lvl ]] && [[ $curr_availability_lvl < 1.0 ]]; then
                    wakeup $directory $logdirectory $queue $max_queues_node $timeout $nb_wakeup_nodes
                elif [ $waitings -eq 0 ] && [[ $curr_availability_lvl == 1.0 ]]; then
                    poweroff $directory $logdirectory $queue $max_queues_node $total_slots $curr_availability_lvl $avail_min_lvl
                elif [ $waitings -eq 0 ] && [[ $curr_availability_lvl > $avail_min_lvl ]] && [[ $curr_availability_lvl < 1.0 ]]; then
                    poweroff $directory $logdirectory $queue $max_queues_node $total_slots $curr_availability_lvl $avail_min_lvl
                fi;

            #if ((`grep "$message2watch" $logfile2watch |wc -l` > $number_messages));then
                #poweroff $directory $logdirectory $queue $max_queues_node $total_slots $curr_availability_lvl $avail_min_lvl
            #fi;

            waiting_nodes=`qstat -u \* -r -q $queue  | egrep -A5 "qw.+[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}"|grep hostname| awk '{print $3}' |cut -d "=" -f2`
            for waiting_node in $waiting_nodes
                do
                echo "Booting $waiting_node because of resource reservation." >> $logdirectory/queue.log
                /sbin/boot_node.sh $waiting_node
            done
        fi;
    done;
    wait $pid
done;
