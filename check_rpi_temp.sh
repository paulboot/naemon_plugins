#!/bin/bash
 
################################################################################
# Nagios plugin to monitor Raspberry Pi CPU Temp                           #
# Original Purpose: Nagios plugin to monitor temperatures from DS18B20      #
# Original Author: Kalen Wessel (http://crushbeercrushcode.org)                          #
# Modified By: Kowen Houston (v1.0) https://kowenhouston.wordpress.com/2015/02/12/raspberry-pi-nagios-check-scripts/
# Modofied By Paul Boot (v1.1 and up)
################################################################################

#NOTE: if you run this script the user executing the script probably Naemon/Nagios
#needs to have privileges to run 'vcgencmd measure_temp' add the user to the
#video group run 'sudo usermod -a -G video naemon'

VERSION="Version 1.1"
AUTHOR="Paul Boot"
 
PROGNAME="check_rpi_temp.sh"
 
# Constants
SENSORCPU='/sys/class/thermal/thermal_zone0/temp'
SENSORGPU='vcgencmd measure_temp'
 
 
# Exit codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
 
# Helper functions #############################################################
 
function print_revision {
   # Print the revision number
   echo "$PROGNAME - $VERSION"
}
 
function print_usage {
   # Print a short usage statement
   echo "Usage: $PROGNAME -w <limit> -c <limit>"
}
 
function print_help {
   # Print detailed help information
   print_revision
   echo "$AUTHOR\n\nCheck temperature for RPi CPU and GPU\n"
   print_usage
 
   /bin/cat <<__EOT
 
Options:
-h
   Print detailed help screen
 
-w TEMPERATURE in Celcius
   Exit with WARNING status if greater than TEMPERATURE in Celcius
 
-c TEMPERATURE in Celcius
   Exit with CRITICAL status if greater than TEMPERATURE in Celcius
__EOT
}
# Main #########################################################################

#ToDo
#Check if sensor exists or exit
 
# Sanatized reading of raw temperature from CPU Sensor
temp_sanatized=`cat $SENSORCPU`
# Celcius Temperature
let "tempCPU=$temp_sanatized/1000"

# Sanatized reading of raw temperature from GPU Sensor
temp_sanatized=`$SENSORGPU`
# Remove text
tempGPU=${temp_sanatized:5:-4}

# Warning threshold
thresh_warn=
# Critical threshold
thresh_crit=
 
# Parse command line options
while [ "$1" ]; do
   case "$1" in
       -h | --help)
           print_help
           exit $STATE_OK
           ;;
       -V | --version)
           print_revision
           exit $STATE_OK
           ;;
       -v | --verbose)
           : $(( verbosity++ ))
           shift
           ;;
       -w | --warning | -c | --critical)
           if [[ -z "$2" || "$2" = -* ]]; then
               # Threshold not provided
               echo "$PROGNAME: Option '$1' requires an argument"
               print_usage
               exit $STATE_UNKNOWN
           elif [[ "$2" = +([0-9]) ]]; then
               # Threshold is a number (Celcius)
               thresh=$2
           else
               # Threshold is not a number
               echo "$PROGNAME: Threshold must be integer"
               print_usage
               exit $STATE_UNKNOWN
           fi
           [[ "$1" = *-w* ]] && thresh_warn=$thresh || thresh_crit=$thresh
           shift 2
           ;;
       -?)
           print_usage
           exit $STATE_OK
           ;;
       *)
           echo "$PROGNAME: Invalid option '$1'"
           print_usage
           exit $STATE_UNKNOWN
           ;;
   esac
done
 
if [[ -z "$thresh_warn" || -z "$thresh_crit" ]]; then
   # One or both thresholds were not specified
   echo "$PROGNAME: Threshold not set"
   print_usage
   exit $STATE_UNKNOWN
elif [[ "$thresh_crit" -lt "$thresh_warn" ]]; then
   # The warning threshold must be greater than the critical threshold
   echo "$PROGNAME: Critical threshold should be greater than warming threshold"
   print_usage
   exit $STATE_UNKNOWN
fi

#Outout and performance stats
checkOutput="tempCPU=$tempCPU°C, tempGPU=$tempGPU°C | tempCPU=$tempCPU°C;$thresh_warn;$thresh_crit;0 tempGPU=$tempGPU°C;$thresh_warn;$thresh_crit;0"

if [[ "$tempCPU" -gt "$thresh_crit" || "$tempGPU" -gt "$thresh_crit" ]]; then
   # Temperature is greater than the critical threshold
   echo "TEMP CRITICAL - $checkOutput"
   exit $STATE_CRITICAL
elif [[ "$tempCPU" -gt "$thresh_warn" ]] || [[ "$tempGPU" -gt "$thresh_warn" ]]; then
   # Temperature is greater than the warning threshold
   echo "TEMP WARNING - $checkOutput"
   exit $STATE_WARNING
else
   # Temperature is stable
   echo "TEMP OK - $checkOutput"
   exit $STATE_OK
fi
