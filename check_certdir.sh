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

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.0"

if [ ! -e "/usr/lib/nagios/plugins/utils.sh" ]
then
    echo "Please specify path to utils.sh, part of the Nagios/Monitoring plugin projects"
    exit 3
fi
source /usr/lib/nagios/plugins/utils.sh

DEBUG=0
YES=0
NO=1
ERR=2
FILESNUMBER=0
OKFILESNUMBER=0
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
    echo "Batch certificate age checker for X509 PEM and DER encoded certificates."
    echo "The value of <warningdays> must be hihger then the <criticaldays>, higher number is"
    echo "more days from now, is better."
    echo ""
    echo "Examples"
    echo "  Report any certificates, that match *.pem, who are due to expire in 28 days as WARNING and"
    echo "  list certificates due to expire in 14 days as CRITICAL."
    echo "     $PROGNAME '/etc/ssl/certs/*.pem' 28 14"
    echo ""
    echo "  Report a warning if 10 or more certificates who are due to expire in 28 days and"
    echo "  report a critical if 0 or more certificates due to expire in 14 days"
    echo "     $PROGNAME '/etc/ssl/certs/*' 28 14 10 0"
    echo ""
}

print_debug() {
    if [ $DEBUG -ne 0 ]
    then
        echo -n `date +'%b %d %k:%M:%S'`
        echo "  $PROGNAME $1"
    fi
} 

print_statusdetails() {
    echo "Status details:"
    echo "in directory: $CERTDIR"
    echo "WARNING certificates:$WARNINGFILESLIST"
    echo "CRITICAL certificates:$CRITICALFILESLIST"
}

# Make sure the correct number of command line arguments
if [ $# -eq 3 ]
then
    CERTDIR=$1
    WARNINGDAYS=$2   # Should be higher then CRITICALDAYS
    CRITICALDAYS=$3
    WARNINGCOUNTLIMIT=0
    CRITICALCOUNTLIMIT=0    
elif [ $# -eq 5 ]
then
    CERTDIR=$1
    WARNINGDAYS=$2   # Should be higher then CRITICALDAYS
    CRITICALDAYS=$3
    WARNINGCOUNTLIMIT=$4
    CRITICALCOUNTLIMIT=$5
else
    print_help
    exit $STATE_UNKNOWN
fi

for FILENAME in $CERTDIR
do
    print_debug "Filename: $FILENAME"
    if [ ! -e "$FILENAME" ] 
    then
        echo "STATE UNKNOWN No directory, directory empty or not a file: $FILENAME"
        exit $STATE_UNKNOWN 
    fi

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
    FILESNUMBER=$((FILESNUMBER+1))
    
    ENDEPOCH=`date -d "$ENDDATE" +%s`
    NOWEPOCH=`date +%s`
    DIFDAYS=$(expr $(expr $ENDEPOCH - $NOWEPOCH) / 86400)
    print_debug "FILENAME: $FILENAME DIFDAYS: $DIFDAYS"

    check_range $DIFDAYS $WARNINGDAYS:
    WARNING=$?
    check_range $DIFDAYS $CRITICALDAYS:
    CRITICAL=$?
    
    if [[ "$WARNING" -eq "$NO" && "$CRITICAL" -eq "$NO" ]]
    then 
        OKFILESNUMBER=$((OKFILESNUMBER+1))
    elif [[ "$WARNING" -eq "$YES" && "$CRITICAL" -eq "$NO" ]]
    then
        WARNINGFILESLIST="$WARNINGFILESLIST `basename $FILENAME`($DIFDAYS day(s))"
        WARNINGFILESNUMBER=$((WARNINGFILESNUMBER+1))
    elif [ "$CRITICAL" -eq "$YES" ]
    then
        CRITICALFILESLIST="$CRITICALFILESLIST `basename $FILENAME`($DIFDAYS day(s))"
        CRITICALFILESNUMBER=$((CRITICALFILESNUMBER+1))
    fi
done

check_range $WARNINGFILESNUMBER $WARNINGCOUNTLIMIT
WARNING=$?
check_range $CRITICALFILESNUMBER $CRITICALCOUNTLIMIT
CRITICAL=$?

DETAILS="CERTS_ALL=$FILESNUMBER CERTS_OK=$OKFILESNUMBER CERTS_WARN=$WARNINGFILESNUMBER CERTS_CRIT=$CRITICALFILESNUMBER"
STATS="CERTS_ALL=$FILESNUMBER CERTS_OK=$OKFILESNUMBER CERTS_WARN=$WARNINGFILESNUMBER;$WARNINGCOUNTLIMIT;\
$WARNINGCOUNTLIMIT;0 CERTS_CRIT=$CRITICALFILESNUMBER;$CRITICALCOUNTLIMIT;$CRITICALCOUNTLIMIT;0"

#Everything OK
if [[ $WARNING -eq $NO && $CRITICAL -eq $NO ]] 
then
	echo "OK $DETAILS|$STATS"
    print_statusdetails
	exit $STATE_OK
fi

#Only WARNINGS
if [[ $WARNING -eq $YES && $CRITICAL -eq $NO ]] 
then
	echo "WARNING $DETAILS|$STATS"
    print_statusdetails
	exit $STATE_WARNING
fi

#Only CRITICAL or CRITICAL and WARNING
if [ $CRITICAL -eq $YES ] 
then
	echo "CRITICAL $DETAILS|$STATS"
    print_statusdetails
	exit $STATE_CRITICAL
fi

#Catch all error
echo "UNKNOWN error"
exit $STATE_UNKNOWN