#!/bin/bash

function usage(){
	cat<<EOF
Usage:
./daniel.sh <command to wrap> -arg <num of args to pass the wrapped command> <arg1> .. <arg2> .. <argN> <main args (-c --failed-count and etc...)>

Example: ./daniel.sh netstat -arg 1 -a -c 3 --net-trace --debug

V        -h              Help
V	-c		Number of times to run the given command
        
V	--failed-count	Number of allowed failed command invocation attempts before timing out
	--net-trace		For each failed execution, create a 'pcap' file with the network traffic during the execution
	--sys-trace		For each failed execution, create a log for each of the following values, measured during command execution:
					disk I/O, memory, processes/threads, cpu usage of the command, network card package counters
				(Requires SUDO)
V	--debug			Debug mode, show each instruction executed by the script
EOF
}

_DEBUG="off"

#Base vars
COUNT=0
FAILEDCNT=0
NET_TRACE=false
SYS_TRACE=false
CALL_TRACE=false
LOG_TRACE=false
DEBUG=false

function onExit(){
	if (( ${failsArray[0]} < ${failsArray[1]} )); then
		FAILS=1
	elif (( ${failsArray[1]} < ${failsArray[0]} )); then
		FAILS=0
	else
		FAILS="Both are the same"
	fi

	echo "Run finished... printing summary:"
	echo "Exited with 1: ${failsArray[1]}"
	echo "Exited with 0: ${failsArray[0]}"
	echo "Most common return code: "$FAILS
	exit
}


function TEST(){
	if (( $1==0 )); then
		((failsArray[0]++))
	else
		((failsArray[1]++))
	fi

	if $LOG_TRACE; then #Output to log
		echo "Creaing LOG"
		echo $OUTPUT >> FAULT_LOG-$LogNameDate.$i.log
	fi	
}

trap onExit SIGINT SIGTERM

#Command and its args
COM=$1
shift
#Set TENO wuth getiot parameters
ARGS=`getopt -o c:h --long failed-count:,net-trace,sys-trace,call-trace,log-trace,debug -- "$@"`
eval set -- "$ARGS"
# extract options and their arguments into variables.
while true ; do
	case $1 in
	-c) #Check if the given input has a numeric value
		if ! [[ "$2" =~ ^[0-9]*$ ]]; then
			#If not, show the usage instructions, and exit with error			
			usage
			exit 1
		else #If so, initialize the COUNT as the value
			COUNT=$2
		fi
		
		shift 2
		;;
	-h)
		usage
		break
		;;
	--failed-count)
		#Check if the given input has a numeric value
		if ! [[ "$2" =~ ^[0-9]*$ ]]; then
			#If not, show the usage instructions, and exit with error			
			usage
			exit 1
		else #If so, initialize the allowed fails, and set the counter to 0
			FAILEDCNT=$2
			FAILS=0
		fi
		shift 2
		;;
	--net-trace)
		NET_TRACE=true
		shift
		;;
	--sys-trace)
		SYS_TRACE=true
		shift
		;;
	--call-trace)
		CALL_TRACE=true
		shift
		;;
	--log-trace)
		LOG_TRACE=true
		shift
		;;
	--debug)
	        set -x
		DEBUG=true
		shift
		;;
	--)
		shift
		break
		;;

	esac
done
#Commented out. Exists just for debugging
#sleep 30
failsArray=(0 0)
FL=1

#Execute the given command C times
for (( i=1; i<=$COUNT; i++ )){
#Loop to run i times
	trap onExit SIGINT SIGTERM
	#Generate a base name for all the logs
	LogNameDate=`date +%d%m%H%M%S`
	#OUTPUT keep's the command's stderr & stdout. Otherwise, check if LOGTRACE mode is on: On return 0 it does nothing. on return 1 it keeps it in the Err.log
	PNAME=$COM	
	TMPFAIL=${failsArray[1]} #Save the current fail status

#Get tcp packages info
	if $NET_TRACE; then
	#Run tcpdump in the background, and supress any nuhup's messages
	#Create a tmp file, which will be deleted if no errors will occur.
		echo "Running tcpdump"
		sudo nohup tcpdump -n -w tcpdump.$LogNameDate.$i.cap > /dev/null 2>&1 &
		echo "tcp created"
		TCID=$! #Save the nohup's ID, to kill it after the given gimmand finishes it's run.
	fi	

	if $SYS_TRACE; then
		echo "Strace ON: $COMID"
		strace -f $COM > kernel.$LogNameDate.$i.log 2>&1
		TEST $?
	else #TODO: Add a LOGPATH var instead of the LOG function
		eval $COM 2>&1 > $LOGPATH
	fi
	
	#CLEAN UP	
	if $NET_TRACE; then
		sudo kill $TCID > /dev/null 2>&1
		echo "DONE"
	fi
	
	if (( $TMPFAIL==${failsArray[1]} )); then #We had successes
		if $NET_TRACE; then #Remove the tmp log generated by the tcpdump
			echo "Removing tcpdump.$LogNameDate.$i.cap"
			sudo rm tcpdump.$LogNameDate.$i.cap > /dev/null 2>&1	
		fi
	fi

	if (( $FAILEDCNT!=0 && ${failsArray[1]}==$FAILEDCNT )); then
		#Check if --failed-count was initialized
		echo "Reached maximum allowed fails [${failsArray[1]}] aborting..."
		onExit
	fi	
	
} #End of for loop

onExit
