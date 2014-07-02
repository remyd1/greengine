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


#args[1] => Node_name
#args[2] => [h|r] halt or reboot
#args[3] => [HH:MM|now] Time
#args[4] => optional : [-F|reinstall|message] fsck -F , reinstall a node
# or write something to the log file /var/log/haltnodes.

echo -e " \n
 -------------------------------------------------------------- \n
 --------------------- cleanhalt.sh --------------------------- \n
 -------- program to shutdown or reboot a node properly ------- \n
 --------------- Grid Engine is required ---------------------- \n
 "

usage="-e \n
 -------------------------------------------------------------- \n
 -------------------------------------------------------------- \n
 --- Usage : \n
 -------------------------------------------------------------- \n
 -------------------------------------------------------------- \n
\n
 cleanhalt.sh node_name action Time {-F|reinstall|message} \n
\n
 -------------------------------------------------------------- \n
\n
\n
 node_name : required \n
\n
\n
 ## action :required \n
 = -h \n
 ## ----> halt \n
 ---- or \n
 = -r \n
 ## ----> reboot \n
\n
\n
 ## Time :required \n
 --- = now \n
 ##   or \n
 --- = HH:MM \n
 ----> HH hour \n
 ----> MM minutes \n
\n
\n
 ## Optional argument :
 -F : fsck at reboot \n
    ## or \n
 reinstall : reinstall the node [works only with rocks cluster] \n
 message : write a message on logs
\n
\n
 cleanhalt.sh [-h][--help] \n
 ----> print this help.\n\n
 -------------------------------------------------------------- \n"



if [ "$#" -lt 3 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ];then
    echo $usage
    exit 1
else
    rm -f /tmp/$1jobs.txt

    /usr/bin/python /root/bin/node_mail_user.py $1
    sleep 4
    
    jobs=`/opt/gridengine/bin/linux-x64/qhost -j -h $1 |awk '{print $1}'`
    for job in $jobs
	do
		if [[ "$job" =~ ^[0-9]+$ ]] ; then 
    			/opt/gridengine/bin/linux-x64/qdel -f $job
		fi
	done


    if [[ "$2" == -[hr] ]];then
        date >> /var/log/haltnodes
        # we will try to determine if some nfs storage are still mounted/busy
        # another option could be to kill everything open by the user:
        #kill -9 `lsof -t -u $user`
        busyusers=`ssh $1 lsof 2>/dev/null | awk '$9 ~ /home\// {print $3}' |uniq`
        busypids=`ssh $1 lsof 2>/dev/null | awk '$9 ~ /home\// {print $2}' |uniq`
        for busypid in $busypids
        do
            ssh $1 "kill -9 $busypid"
            echo "busy PIDs from "$1 >> /tmp/job_per_host.txt
            echo $busypid >> /tmp/job_per_host.txt
        done
        ssh $1 /sbin/service autofs stop
        sleep 2
        if [[ "$4" == "-F" ]];then
            ssh $1 "shutdown $2 $4 $3"
            echo "$1 action [$2] at $3 with $4 option- ok"
            echo "## Node $1 stopped at $3 with action $2 and option $4" >> /var/log/haltnodes
        elif [[ "$4" == "reinstall" ]];then
            echo "$1 action [$2] at $3 with $4 option- ok"
            /opt/rocks/bin/rocks set host boot $1 action=install
            ssh $1 "shutdown $2 $3"
            echo "## Node $1 stopped at $3 with action $2 and option $4" >> /var/log/haltnodes
        elif [[ "$4" == "" ]];then
            ssh $1 "shutdown $2 $3"
            echo "$1 action [$2] at $3 - ok"
            echo "## Node $1 stopped at $3 with action $2 and option $4" >> /var/log/haltnodes
        else
            ssh $1 "shutdown $2 $3"
            echo "$1 action [$2] at $3 - ok"
            echo "## Node $1 stopped at $3 with action $2 and message $4" >> /var/log/haltnodes
            echo $*  >> /var/log/haltnodes
        fi;
        for busyuser in $busyusers
        do
            echo "user $busyuser was still connected on $1 ..." >> /var/log/haltnodes
        done
    else
        echo $usage
    fi;

fi;
