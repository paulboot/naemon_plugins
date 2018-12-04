#!/bin/bash

# Writen by Craig Dienger see: https://www.nagios.com/news/2018/01/monitoring-cryptocurrency-nagios/
# Minor tweaks by Paul Boot (added performance counts and hysteresis when "$SERVICEPERFDATA$" is added as fifth argument)

#Convert crypto values

# $1 FROM (example: BTC)
# $2 TO (example: USD)
# $3 warning range
# $4 critical range
# $5 previous $SERVICEPERFDATA$


#https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
#Range definition 		Generate an alert if x...
# 10 					< 0 or > 10, (outside the range of {0 .. 10})
# 10: 					< 10, (outside {10 .. ∞})
# ~:10	 				> 10, (outside the range of {-∞ .. 10})
# 10:20 				< 10 or > 20, (outside the range of {10 .. 20})
# @10:20 				≥ 10 and ≤ 20, (inside the range of {10 .. 20})

#Example: ./check_crypto.sh BTC USD "~:12000" "~:15000" "BTC_USD=3880.64;~:12000;~:15000;0  ARMED=0"
#Generates a warning if price is over 12,000 and critical if above 15,000

source /usr/lib/nagios/plugins/utils.sh

YES=0
NO=1
ERR=2
TRUE=1
FALSE=0
PROGNAME=$(basename $0)
PROGPATH=$(echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,')
REVISION="1.2"

if [ ! -z "$5" ]
then
    SERVICEPERFDATA=$5  #"BTC_USD=3880.64;~:12000;~:15000;0 WARNING_ARMED=0 CRITICAL_ARMED=0"
    #cut on space then cut on =
    WARNING_ARMED=$(cut -d'=' -f2 <<< $(cut -d' ' -f2 <<< $5))
    CRITICAL_ARMED=$(cut -d'=' -f2 <<< $(cut -d' ' -f3 <<< $5))
    if [[ -z "$WARNING_ARMED" || -z "$CRITICAL_ARMED" ]]
    then
        echo "UNKNOWN $! invalid previous perf data"
        exit $STATE_UNKNOWN     
    fi
else
    WARNING_ARMED=$TRUE
    CRITICAL_ARMED=$TRUE
fi

# Make sure the correct number of command line arguments
if [ $# -lt 4 ]
then
    echo "missing arguments usage: ./$PROGNAME BTC USD \"~:12000\" \"~:15000\""
    exit $STATE_UNKNOWN
fi

RESULT=$(/usr/bin/curl -X GET "https://min-api.cryptocompare.com/data/price?fsym=$1&tsyms=$2" -m 30 -s | awk -F '[:}]' '{print $2}')

if [ $WARNING_ARMED -eq $TRUE ]
then
    check_range $RESULT $3
    WARNING=$?
else
    WARNING_LOW=$(cut -d':' -f1 <<< $3)
    WARNING_HIGH=$(cut -d':' -f2 <<< $3)

    WARNING_LOW=$(bc <<< "scale=8; $WARNING_LOW + $WARNING_LOW/100")
    WARNING_HIGH=$(bc <<< "scale=8; $WARNING_HIGH - $WARNING_HIGH/100")
    
    #echo $RESULT "$WARNING_LOW:$WARNING_HIGH"
    check_range $RESULT "$WARNING_LOW:$WARNING_HIGH"
    WARNING=$?    
fi

if [ $CRITICAL_ARMED -eq $TRUE ]
then
    check_range $RESULT $4
    CRITICAL=$?
else
    CRITICAL_LOW=$(cut -d':' -f1 <<< $4)
    CRITICAL_HIGH=$(cut -d':' -f2 <<< $4)

    CRITICAL_LOW=$(bc <<< "scale=8; $CRITICAL_LOW + $CRITICAL_LOW/100")
    CRITICAL_HIGH=$(bc <<< "scale=8; $CRITICAL_HIGH - $CRITICAL_HIGH/100")
    
    #echo $RESULT "$CRITICAL_LOW:$CRITICAL_HIGH"
    check_range $RESULT "$CRITICAL_LOW:$CRITICAL_HIGH"
    CRITICAL=$?    
fi

if [ $WARNING -eq $NO ]
then
    WARNING_ARMED=$TRUE
    CRITICAL_ARMED=$TRUE
    echo "OK $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0 WARNING_ARMED=$WARNING_ARMED CRITICAL_ARMED=$CRITICAL_ARMED"
    exit $STATE_OK
fi

if [[ $WARNING -eq $YES && $CRITICAL -eq $NO ]] 
then
    WARNING_ARMED=$FALSE
    CRITICAL_ARMED=$TRUE
    echo "WARNING $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0 WARNING_ARMED=$WARNING_ARMED CRITICAL_ARMED=$CRITICAL_ARMED"
    exit $STATE_WARNING
fi

if [ $CRITICAL -eq $YES ]
then
    WARNING_ARMED=$FALSE
    CRITICAL_ARMED=$FALSE
    echo "CRITICAL $1 @ $RESULT $2|$1_$2=$RESULT;$3;$4;0 WARNING_ARMED=$WARNING_ARMED CRITICAL_ARMED=$CRITICAL_ARMED"
    exit $STATE_CRITICAL
fi

if [[ $WARNING -eq $ERR || $CRITICAL -eq $ERR ]]
then
    WARNING_ARMED=$TRUE
    CRITICAL_ARMED=$TRUE
    echo "UNKNOWN $! invalid range"
    exit $STATE_UNKNOWN
fi


