#!/bin/bash

# Write a command to the Naemon command file to cause
# it to process a service check result

# $1 <host_name>
# $2 <sevice_description>
# $3 <state_xx>
# $4 <description>

#./submit_check_result host_name 'Port Scans' 2 'Port scan from host $TARGET$ on port $PORT$ firewalled.'"

# Naemon Configuration:
#   Create a service definition and associate it with a host.
#   Set the max_check_attempts directive in the service definition to 1. This will tell Naemon to immediate force the service into a hard state when a non-OK state is reported.
#   Set the active_checks_enabled directive in the service definition to 0. This prevents Naemon from actively checking the service.
#   Set the passive_checks_enabled directive in the service definition to 1. This enables passive checks for the service.
#   Set this is_volatile directive in the service definition to 1. This will persist the error until???

#STATE_OK=0
#STATE_WARNING=1
#STATE_CRITICAL=2
#STATE_UNKNOWN=3
#STATE_DEPENDENT=4

echocmd="/bin/echo"

CommandFile="/var/lib/naemon/naemon.cmd"

# get the current date/time in seconds since UNIX epoch
datetime=`date +%s`

# create the command line to add to the command file
cmdline="[$datetime] PROCESS_SERVICE_CHECK_RESULT;$1;$2;$3;$4"

# append the command to the end of the command file
$($echocmd $cmdline >> $CommandFile)
