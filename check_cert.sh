#!/bin/bash

# check_cert.sh written by Paul Boot <paulboot@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# $1 X509 cetificate directory with PEM encoded certificate files (example: client1.crt)
# $2 warning range
# $3 critical range

#https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
#Range definition 		Generate an alert if x...
# 10 					< 0 or > 10, (outside the range of {0 .. 10})
# 10: 					< 10, (outside {10 .. ∞})
# ~:10	 				> 10, (outside the range of {-∞ .. 10})
# 10:20 				< 10 or > 20, (outside the range of {10 .. 20})
# @10:20 				≥ 10 and ≤ 20, (inside the range of {10 .. 20})

#Example: ./check_cert.sh <file.crt> 40 20
#Generates a warning if the certificate has and end-dat that is 40 days in the future

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.0"

#ToDo if exist
source /usr/lib/nagios/plugins/utils.sh

DEBUG=1
YES=0
NO=1
ERR=2
WARNINGFILESNUMBER=0
CRITICALFILESNUMBER=0

print_usage() {
    echo "Usage: $PROGNAME <path-to-cert-dir> <warningdays> <criticaldays> [<warningcount> <criticalcount>]"
}

print_help() {
    echo "$PROGNAME v$REVISION"
    echo ""
    print_usage
    echo ""
    echo "Per folder batch certificate age checker for X509 PEM and DER encoded certificates."
    echo ""
    echo "The value of <warningdays> must be hihger then the <criticaldays>, higher number is more days from now."
    echo "Example:"
    echo "Report any certificates found that are due to expire in 28 days as WARNING and list certificates due to expire in 14 days as CRITICAL."
    echo "$PROGNAME /etc/ssl/certs 28 14"
    echo ""
    echo "Report a warning if 10 or more certificates are due to expire in 28 days and report a critical if 15 or more certificates due to expire in 14 days"
    echo "$PROGNAME /etc/ssl/certs 28 14 10 15"
    echo ""
}

print_debug() {
    if [ $DEBUG -ne 0 ]
    then
        echo -n `date +'%b %d %k:%M:%S'`
        echo "  $PROGNAME $1"
    fi
} 

# Make sure the correct number of command line arguments
if [ $# -eq 3 ]
then
    CERDIR=$1
    WARNINGDAYS=$2   # Should be higher then CRITICALDAYS
    CRITICALDAYS=$3
    WARNINGCOUNTLIMIT=0
    CRITICALCOUNTLIMIT=0    
elif [ $# -eq 5 ]
then
    CERDIR=$1
    WARNINGDAYS=$2   # Should be higher then CRITICALDAYS
    CRITICALDAYS=$3
    WARNINGCOUNTLIMIT=$4
    CRITICALCOUNTLIMIT=$5
else
    print_help
    exit $STATE_UNKNOWN
fi

for FILENAME in $CERDIR/*
do
    [ -e "$FILENAME" ] || exit $STATE_UNKNOWN 

    ENDDATE=`openssl x509 -inform PEM -in "$FILENAME" -enddate -noout 2>> /dev/null | sed "s/.*=\(.*\)/\1/"`
    if [ -z "$ENDDATE" ]
    then
        #No ENDDATE found not a valid X509 PEM encoded
        ENDDATE=`openssl x509 -inform DER -in "$FILENAME" -enddate -noout 2>> /dev/null | sed "s/.*=\(.*\)/\1/"`
        if [ -z "$ENDDATE" ]
        then
            #No ENDDATE found, not a valid X509 DER encoded
            #ToDo display warning
            continue
        fi
    fi
    
    ENDEPOCH=`date -d "$ENDDATE" +%s`
    NOWEPOCH=`date +%s`
    DIFDAYS=$(expr $(expr $ENDEPOCH - $NOWEPOCH) / 86400)
    print_debug "FILENAME: $FILENAME DIFDAYS: $DIFDAYS"

    check_range $DIFDAYS $WARNINGDAYS:
    WARNING=$?
    check_range $DIFDAYS $CRITICALDAYS:
    CRITICAL=$?
    
    if [[ "$WARNING" -eq "$YES" && "$CRITICAL" -eq "$NO" ]]
    then
        WARNINGFILESLIST="$WARNINGFILESLIST `basename $FILENAME`"
        WARNINGFILESNUMBER=$((WARNINGFILESNUMBER+1))
    fi 
    if [ "$CRITICAL" -eq "$YES" ]
    then
        CRITICALFILESLIST="$CRITICALFILESLIST `basename $FILENAME`"
        CRITICALFILESNUMBER=$((CRITICALFILESNUMBER+1))
    fi
done

check_range $WARNINGFILESNUMBER $WARNINGCOUNTLIMIT
WARNING=$?
check_range $CRITICALFILESNUMBER $CRITICALCOUNTLIMIT
CRITICAL=$?
STATS="CERTS_WARN=$WARNINGFILESNUMBER;$WARNINGCOUNTLIMIT;$WARNINGCOUNTLIMIT;0 CERTS_CRIT=$CRITICALFILESNUMBER;$CRITICALCOUNTLIMIT;$CRITICALCOUNTLIMIT;0"

#Everything OK
if [[ $WARNING -eq $NO && $CRITICAL -eq $NO ]] 
then
	echo "OK|$STATS"
	exit $STATE_OK
fi

#Only WARNINGS
if [[ $WARNING -eq $YES && $CRITICAL -eq $NO ]] 
then
	echo "WARNING$WARNINGFILESLIST|$STATS"
	exit $STATE_WARNING
fi

#Only CRITICAL
if [[ $WARNING -eq $NO && $CRITICAL -eq $YES ]] 
then
	echo "CRITICAL$CRITICALFILESLIST|$STATS"
	exit $STATE_CRITICAL
fi

#CRITICAL and WARNIGS
if [[ $WARNING -eq $YES && $CRITICAL -eq $YES ]]
then
	echo "CRITICAL$CRITICALFILESLIST WARNING$WARNINGFILESLIST|$STATS"
	exit $STATE_CRITICAL
fi
