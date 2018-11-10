#!/bin/bash

# Writen by Craig Dienger see: https://www.nagios.com/news/2018/01/monitoring-cryptocurrency-nagios/
# Minor tweaks by Paul Boot (added performance counts for graphing)

#Convert crypto values

# $1 FROM (example: BTC)
# $2 TO (example: USD)
# $3 warning range
# $4 critical range


#https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
#Range definition 		Generate an alert if x...
# 10 					< 0 or > 10, (outside the range of {0 .. 10})
# 10: 					< 10, (outside {10 .. ∞})
# ~:10	 				> 10, (outside the range of {-∞ .. 10})
# 10:20 				< 10 or > 20, (outside the range of {10 .. 20})
# @10:20 				≥ 10 and ≤ 20, (inside the range of {10 .. 20})

#Example: ./check_crypto.sh BTC USD "~:12000" "~:15000"
#Generates a warning if price is over 12,000 and critical if above 15,000

source /usr/lib/nagios/plugins/utils.sh

YES=0
NO=1
ERR=2

RESULT=`/usr/bin/curl -X GET "https://min-api.cryptocompare.com/data/price?fsym=$1&tsyms=$2" -m 30 -s | awk -F '[:}]' '{print $2}'` 

check_range $RESULT $3
WARNING=$?
check_range $RESULT $4
CRITICAL=$?

if [ $WARNING -eq $NO ]
then
	echo "OK $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0"
	exit $STATE_OK
fi

if [[ $WARNING -eq $YES && $CRITICAL -eq $NO ]] 
then
	echo "WARNING $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0"
	exit $STATE_WARNING
fi

if [ $CRITICAL -eq $YES ]
then
	echo "CRITICAL $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0"
	exit $STATE_CRITICAL
fi

if [[ $WARNING -eq $ERR || $CRITICAL -eq $ERR ]]
then
    echo "UNKNOWN $! invalid range"
    exit $STATE_UNKNOWN
fi