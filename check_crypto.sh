#!/bin/bash

# Writen by Craig Dienger see: https://www.nagios.com/news/2018/01/monitoring-cryptocurrency-nagios/
# Minor tweaks by Paul Boot


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

#Example: ./crypto.sh BTC USD "~:12000" "~:15000"
#Generates a warning if price is over 12,000 and critical if above 15,000

result=`/usr/bin/curl -X GET "https://min-api.cryptocompare.com/data/price?fsym=$1&tsyms=$2" -m 30 -s | awk -F '[:}]' '{print $2}'` 


source /usr/lib/nagios/plugins/utils.sh

check_range $result $3
warning=$?
check_range $result $4
critical=$?

if [ $critical -eq 0 ]
then
	echo "CRITICAL $1 @ $result $2|$1_$2=$result;$3;$4;0"
	exit 2 
fi

if [ $warning -eq 1 ]
then
	echo "OK $1 @ $result $2|$1_$2=$result;$3;$4;0"
	exit 0
fi

if [ $warning -eq 0 ] 
then
	echo "WARNING $1 @ $result $2|$1_$2=$result;$3;$4;0"
	exit 1 
fi
