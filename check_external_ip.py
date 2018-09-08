#!/usr/bin/python
 
# Import the necessary python modules.

from urllib2 import Request, urlopen, URLError, HTTPError
from sys import argv, exit
from os import path
import argparse

# Setup our help output.

parser = argparse.ArgumentParser(
     description='Checks the external IP dynamically assigned by the service provider.',
     epilog="""This plugin is designed for those who need to know the IP address dynamically 
            assigned to them by their service provider. The plugin checks with an external 
            website to find out what public IP address has been assigned by the service 
            providers. The results of the check are stored in a temp file located in /tmp. 
            If the results from the current IP check differs from the pervious results an 
            alert is triggered. These alerts contain the current IP address assigned. 

            This plugin doesn't require any arguments, and will work for both IPv4 and IPv6 
            address assignments. However if you have a dual stack network connection you can
            test either the IPv4 address or the IPv6 independently using the appropriate flag
            It is recommended that the max check attempts be set to 1 for this service check. 
            Failure to do will result is missed alerts when a new IP address is assigned.
            """.format(path.basename(argv[0])))

# Setup our mutally exclusive group and add the option for IPv4 or IPv6.
group = parser.add_mutually_exclusive_group()
group.add_argument('-4', '--ipv4', action="store_true", help='Connect using IPv4')
group.add_argument('-6', '--ipv6', action="store_true", help='Connect using IPv6')

# Store our command line arugments in a dictionary.

args = vars(parser.parse_args())

# Set the appropriate URL and temp file depending on the command line argument supplied. 
# Default to an URL that will work against IPv4 or IPv6.


if args['ipv4'] == True:
    url= Request("http://ipv4.icanhazip.com")
    ipAddressFile='/tmp/.external_ip_address_ipv4'
elif args['ipv6'] == True:
    url= Request("http://ipv6.icanhazip.com")
    ipAddressFile='/tmp/.external_ip_address_ipv6'
else:
    url = Request("http://www.icanhazip.com")
    ipAddressFile='/tmp/.external_ip_address'

# Try and connect to the URL, and report any failures

try:
    external_ip_address = urlopen(url).read().rstrip('\n')
except HTTPError, e:
     print "Server couldn\'t fulfill the request. Error code: %s" % e.code
     exit(3)
except URLError, e:
     print "Failed to reach server. Reason: %s" % e.reason
     exit(3)

# Try and open our temp file to compare the pervious IP address. If no temp file
# exist create a new one and send a warning about missing file. Compare results
# and warn when IP address changes.
 
try:
    open(ipAddressFile)
except IOError:
    f = open(ipAddressFile,'w')
    f.write(external_ip_address)
    f.close
    print "WARNING - New File Created with IP Address: %s" % external_ip_address
    exit(1)
else:
    f = open(ipAddressFile,'r+')
    current_ip_address = f.read()
    f.close
    if current_ip_address == external_ip_address:
         print "OK - Current IP Address: %s" % external_ip_address
         exit(0)
    else:
         f = open(ipAddressFile,'w')
         f.write(external_ip_address)
         f.close()
         print "CRITICAL - IP Address has changed to %s" % external_ip_address
         exit(2)

