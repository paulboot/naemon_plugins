#!/usr/bin/python
# Copyright (c) Paul Boot (paulboot(at)gmail.com)
# See also LICENSE.txt

"""XXX Nagios plugin to check XXX"""

#Example: 
## met twee contexts en in verbose mode meerdere regels output!
## second context is not a scalar but a text output scalar, just used for reporting.

# Dependancies
# sudo apt-get install python-pip
# sudo pip --proxy http://gg.nl:8080/ install nagiosplugin --upgrade
# sudo locale-gen nl_NL.UTF-8

# Testing the URL takes about 30 seconds!
# wget --no-proxy -O output.txt http://gg.nl/PlanService/getfeed.aspx?id=uitloop&link=schedule&showzerodelay=n

#from __future__ import unicode_literals
import argparse
import pickle
import logging
import nagiosplugin
import re
import datetime
import pprint
from lxml import etree

import locale
locale.setlocale(locale.LC_ALL, 'nl_NL.UTF-8')

import requests

# Globals
NO_PROXY = {
             'http'  : '',
             'https' : ''
            }

pickle_path = '/usr/local/naemon/var/'
pickle_file = '_check_uitloop_all.pkl'

#Parsed data format
# <item>
    # <pubDate>Tue, 03 May 2018 09:21:51 GMT</pubDate>
    # <title>Uitloop Cardiologie - dr. v.d. P: 25 minuten.</title>
    # <link>http://localhost/iDoc.Web.Services/PlanService/GetFeed.aspx?ID=uitloop</link>
    # <description>Uitloop Cardiologie - dr. v.d. P: 25 minuten.</description>
    # <logisp:type>uitloop</logisp:type>
    # <logisp:department>A00104</logisp:department>
    # <logisp:departmentname>Cardiologie</logisp:departmentname>
    # <logisp:routeinfo></logisp:routeinfo>
    # <logisp:shortrouteinfo></logisp:shortrouteinfo>
    # <logisp:resource>dr. v.d. P</logisp:resource>
    # <logisp:uitloopminuten>25</logisp:uitloopminuten>
# </item>

# Parse title line: 'Uitloop Cardiologie - dr. v.d. P: 25 minuten'

_log = logging.getLogger('nagiosplugin')

class UITLOOP(nagiosplugin.Resource):
    """Resource creation"""
    def __init__(self, departmentname, uitloopminuten, hostname):
        
        self.departmentname=str(departmentname)
        self.uitloopminuten=int(uitloopminuten)
        self.hostname=str(hostname)
        
    def probe(self):

        #uitloopdict = {
        #    'Cardiologie' : { 'Jansen' : { 'uitloopminuten' : 20 },
        #                      'Pietersen' : { 'uitloopminuten' : 60 } },
        #    'XXXXlogie' : { 'XJansen' : { 'uitloopminuten' : 20 },
        #                      'XPietersen' : { 'uitloopminuten' : 60 } }
        #    }
        #pprint.pprint(uitloopdict)
        
        uitloopdict = {}
        maxuitloopminuten = 0
        aantaluitloopresources = 0
        
        input = open(pickle_path + self.hostname + pickle_file, 'rb')
        alluitloopdict = pickle.load(input)
        input.close()
        #pprint.pprint(alluitloopdict)
        
        for departmentname in alluitloopdict:
            if departmentname == self.departmentname:
                for resource in alluitloopdict[departmentname]:
                    if alluitloopdict[departmentname][resource]['uitloopminuten'] > self.uitloopminuten:
                        _log.debug('###DEBUG Found resoure: %s with exceded uitloop: %d min.', resource, alluitloopdict[departmentname][resource]['uitloopminuten'])
                        if not uitloopdict.has_key(departmentname):
                            uitloopdict[departmentname] = {}
                        if not uitloopdict[departmentname].has_key(resource):
                            uitloopdict[departmentname][resource] = {}
                        uitloopdict[departmentname][resource]['uitloopminuten'] = alluitloopdict[departmentname][resource]['uitloopminuten']
                        aantaluitloopresources += 1
                        
                        
        return [nagiosplugin.Metric('aantaluitloopresources', aantaluitloopresources, min=0),
                nagiosplugin.Metric('tekst', uitloopdict)]


class UitloopSummary(nagiosplugin.Summary):
    """Status regel output functies."""
    
    def problem(self, results):
        problemText=''
        for afdeling in results['tekst'].metric.value:
            problemText += "%s - " % afdeling 
            for naam in results['tekst'].metric.value[afdeling]:
                problemText += "%s: %d min. " % (naam, results['tekst'].metric.value[afdeling][naam]['uitloopminuten'])
        return problemText.encode('ascii', 'ignore')
    
    def verbose(self, results):
        verboseText='\nEr is uitloop geconstateerd op de volgende afdelingen:\n'
        for afdeling in results['tekst'].metric.value:
            verboseText += "\n%s - " % afdeling 
            for naam in results['tekst'].metric.value[afdeling]:
                verboseText += "%s: %d minuten. " % (naam, results['tekst'].metric.value[afdeling][naam]['uitloopminuten'])
        return verboseText.encode('ascii', 'ignore')
        
@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('-d', '--departmentname',
                      help='afdelingsnaam voluit geschreven zoals in de XML output')
    argp.add_argument('-u', '--uitloopminuten', metavar='RANGE', default=45,
                      help='maximale uitloop in minuten')
    argp.add_argument('-w', '--warning', metavar='RANGE', default=0,
                      help='warning niveau maximaal aantal resources met uitloop')
    argp.add_argument('-c', '--critical', metavar='RANGE', default=1,
                      help='critical niveau maximaal aantal resources met uitloop')
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output verbosity (use up to 3 times)')
    argp.add_argument('-t', '--timeout', type=int, default=60,
                      help='abort execution after TIMEOUT seconds')
    argp.add_argument('-H', '--hostname',
                      help='host name argument for webservices URL')
    argp.add_argument('-p', '--port', type=int, default=80,
                      help='port number (default: 80)')
    args = argp.parse_args()
    check = nagiosplugin.Check(
        UITLOOP(args.departmentname, args.uitloopminuten, args.hostname),
        nagiosplugin.ScalarContext('aantaluitloopresources', args.warning, args.critical, fmt_metric='{value} maximale uitloop in minuten'),
        nagiosplugin.Context('tekst'),
        UitloopSummary())
    check.main(verbose=args.verbose, timeout=args.timeout)

if __name__ == '__main__':
    main()

