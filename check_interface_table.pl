#!/usr/bin/perl

=head1 NAME

  check_interface_table.pl -H <host> -C <community string> [OPTIONS]
	
=head1 DESCRIPTION	

=head2 Introduction

B<check_interface_table.pl> is a Nagios(R) plugin that allows you to monitor
one network device (e.g. router, switch, server) without knowing each interface
in detail. Only the hostname (or ip address) and the snmp community string are
required.

  Simple Example:
  
  # check_interface_table.pl -H server1 -C public
  
  Output:
  
  <a href="/nagios/interfacetable/server1-Interfacetable.html">total 3 interface(s)</a>

The above example polls our netware server (server1) and reads all interfaces.
The output is a HTML link to a web page which shows all interface in a table.

When clicking on the link the output looks like:

  server1 updated: Fri Nov 16 13:22:08 2007 (1 sec.)

  Name      Uptime        System Information 
  ---------------------------------------------------------------
  server1 71d 17h 56m   Novell NetWare 5.70.06 October 26, 2006 

  index Description Alias AdminStatus OperStatus Speed IP 
  -------------------------------------------------------- 
  1 HP NC10xx/... Gigabit Server Adapter   up up 1.00 Gbit 10.1.1.4/255.255.0.0 
  2 HP NC10xx/... Gigabit Server Adapter (0x000f2097890c)   up up 1.00 Gbit 10.4.1.2/255.255.0.0 
  3 3COM Etherlink PCI   up up 100.00 Mbit 192.168.17.4/255.255.0.0 
  
  [back] [reset table]

The first line tells the name and when the table was last updated. 
(1 sec.) means that the polling process took one second.

"Name", "Uptime" and "System Information" are for information only.

The table below these information fields shows different interface properties.
The last line has two ascii buttons which allow to navigate back and to reset the table.

=head2 Theory of operation

The perl program polls the remote machine in a highly efficient manner.
It collects all data from all interfaces and stores these data into the directory
/tmp/.ifState. 

  Each host (option -H) holds one text file:

  # ls /tmp/.ifState/*.txt
  /tmp/.ifState/server1-Interfacetable.txt

When the program is called twice, three times, etc. it retreives new
information from the network and compares it against this state file.

=head1 SYNOPSIS

  check_interface_table.pl -H <host> -C <snmp community> [options]
  check_interface_table.pl -H <host> -C <snmp community> -w <warn> -c <crit> [options]
 
=head1 PREREQUISITS

This chapter describes the operating system prerequisits to get this program  
running: 

=head2 net-snmp installed

The B<snmpwalk> command must be available on your operating system.

  Test your snmpwalk output with a command like:
  
  # snmpwalk -Oqn -v 1 -c public router.itdesign.at | head -3
  
  .1.3.6.1.2.1.1.1.0 Cisco IOS Software, 2174 Software Version 11.7(3c), REL.
  SOFTWARE (fc2)Technical Support: http://www.cisco.com/techsupport
  Copyright (c) 1986-2005 by Cisco Systems, Inc.
  Compiled Mon 22-Oct-03 9:46 by antonio
  .1.3.6.1.2.1.1.2.0 .1.3.6.1.4.1.9.1.620
  .1.3.6.1.2.1.1.3.0 9:11:09:19.48
    
  snmpwalk parameters:
  
  -Oqn -v 1 ............ some noise (please read "man snmpwalk")
  -c public  ........... snmp community string
  router.itdesign.at ... host where you do the snmp queries

B<snmpwalk> is part of the net-snmp suit (http://net-snmp.sourceforge.net/).
Some more unix commands to find it:

  # whereis snmpwalk
  snmpwalk: /usr/bin/snmpwalk /usr/share/man/man1/snmpwalk.1.gz
  
  # which snmpwalk
  /usr/bin/snmpwalk
  
  # rpm -qa | grep snmp
  net-snmp-5.3.0.1-25.15  
  
  # rpm -ql net-snmp-5.3.0.1-25.15 | grep snmpwalk
  /usr/bin/snmpwalk
  /usr/share/man/man1/snmpwalk.1.gz

=head2 PERL V5 installed

You need a working perl 5.x installation. Currently we use V5.8.8 under 
SUSE Linux Enterprise Server 10 SP1 for development. We know that it works
with other versions, too. 
  
Get your perl version with:
  
  # perl -V  

=head2 PERL Net::SNMP library

B<Net::SNMP> is the perl's snmp library. Some ideas to see if it is installed:
  
  # rpm -qa|grep -i perl|grep -i snmp
  perl-Net-SNMP-5.2.0-12.2

  # find /usr -name SNMP.pm
  /usr/lib/perl5/vendor_perl/5.8.8/Net/SNMP.pm
  
  if it is not installed please check your operating systems packages or install it
  from CPAN:
  
  http://search.cpan.org/search?query=Net%3A%3ASNMP&mode=all

=head2 PERL Config::General library installed

B<Config::General> is the only "excotic" library typically not installed on your OS.
We use this excelent library to write all interface information data back to the
file system.
  
  See:
  
  http://search.cpan.org/search?query=Config%3A%3AGeneral&mode=all
  
Version 2.31 of this library is part of the kit here - but it should work with
newer versions, too.
  
Installation is quite easy - extract the kit and type
  
  perl Makefile.PL 
  make
  make install

=head2 CGI script to reset the interface table

If everything is working fine you need the possibility to reset the interface table.
Often it is necessary that someone changes ip addresses or other properties. These
changes are necessary and you want to update (=reset) the table.

Resetting the table means to delete the state file in /tmp/.ifState.

Withing this kit you find an example shell script which does this job for you.
To install this cgi script do the following:

  1) Copy the cgi script to the correct location on your WEB server
  
  # cp -i InterfaceTableReset.cgi /usr/local/nagios/sbin

  2) Check permissions
  
  # ls -l /usr/local/nagios/sbin/InterfaceTableReset.cgi
  -rwxr-xr-x 1 nagios nagios 2522 Nov 16 13:14 /usr/local/nagios/sbin/Inte...
  
  3) Prepare the /etc/sudoers file so that the web server's account can call
  the cgi script (as shell script)
  
  # visudo  
  wwwrun ALL=(ALL) NOPASSWD: /usr/local/nagios/sbin/InterfaceTableReset.cgi

The above unix commands are tested under SUSE Linux Enterprise Server 10 SP1
with apache2 installed and nagios Version 3 compiled into /usr/local/nagios.

Please send me an email if you have information from other operating systems
on these details. I will update the documentation.

=head2 Configure Nagios 3.x to display HTML links in Plugin Output

In Nagios version 3.x there is html output per default disabled.

  1) Edit cgi.cfg and set this option to zero
      escape_html_tags=0

cgi.cfg is located in your configuration directory. (/usr/local/nagios/etc on
SuSe Linux)

=head1 OPTIONS

=head2 -H <host> (required option)

 no default

Specifies the remote host to poll. 

=head2 -C <snmp community string> (required)

 default = public

Specifies the snmp version 1 community string. Other snmp versions are not
implemented.

=head2 -w <warning counter> (optional)

Must be a positiv integer number. Changes in the interface table are compared
against this threshold.

  Example:
  
    ... -H server1 -C public -w 1 
    
  Leads to WARNING (exit code 1) when one or more interface properties were
  changed.

=head2 -c <critical counter> (optional)

Must be a positiv integer number. Changes in the interface table are compared
against this threshold.

  Example:
  
    ... -H server1 -C public -c 1 
    
  Leads to CRITICAL (exit code 2) when one or more interface properties were
  changed.

=head2 -Exclude <interface description> [optional]

Let's you exclude some interfaces from tracking. This is useful when you know
that some interfaces tend to flap and you do not want to track these.

  Example:

  ... -H router -C public -Exclude Dialer0,BVI20,FastEthernet0

Interface descriptions must match exactly!

=head2 -Include <interface description> [optional]

This is the opposite to the -Exclude option and incudes only some
interfaces.

  Example:

  ... -H router -C public -Ixclude FastEthernet0,FastEthernet1

=head2 -HTMLDir <directory> (optional)

 default = /usr/local/nagios/share/interfacetable

Sets another directory where the interfae HTML files are stored. Specifies the
path in the file system. See option B<-HTMLUrl> for changing the HTML link.

=head2 -HTMLUrl <url praefix> (optional)

 default = /nagios/interfacetable

B<-HTMLUrl> allows you to change the URL praefix in the output of the plugin.

  Example 1:

  # check_interface_table.txt -H server1 -C public -HTMLUrl ''  
  <a href="/server1-Interfacetable.html">total 3 interface(s)</a>

  Example 2:

  # check_interface_table.txt -H server1 -C public -HTMLUrl 'https://server1/iftbls'  
  <a href="https://server1/iftbls/server1-Interfacetable.html">total 3 interface(s)</a>

Specifies the HTML link only. See option B<HTMLDir> for the file system path.

=head2 -ResetUrl <url praefix> (optional)

B<-ResetUrl> allows you to change the URL praefix for the reset cgi program.

  Example - SUSE Linux paths':

  # check_interface_table/check_interface_table.txt -H server1 -C public \
    -HTMLDir '/srv/www/htdocs' -ResetUrl 'cgi-bin' -HTMLUrl ''

=head2 -StateDir <directory> (optional)

 default = /tmp/.ifState

Sets another directory where the interfae states are stored.

  Example:

  check_interface_table.txt -H server1 -C public -StateDir '/var/tmp'

Interface states are stored in a reference txt file. This option
changes the file system location of that file.

ATTENTION! When implementing the "table reset" feature you must modify your
InterfaceTableReset.cgi program, too.

=head2 -h <host> (optinal option)

 if omitted it defaults to the host with -H 

Specifies the remote host to display in the HTML link.

 Example:
 
 check_interface_table.pl -h firewall -H srv-itd-99.itdesign.at -C mkjz65a

This option is maybe useful when you want to poll a host with -H and display
another link for it.


=head1 ATTENTION - KNOWN ISSUES

=head2 Interaction with Nagios

If you use this program with Nagios then it is typically called in the "nagios"
users context. This means that the user "nagios" must have the correct permissions
to write all required files into the filesystem (see chapter "Theory of operation").

=head2 Reset table

The "reset table button" is the next challange. Clicking in the web browser means to
trigger the "InterfaceTableReset.cgi" script which then tries to remove the state
file.

 If this does not work please check the following:

 * correct directory and permissions of InterfaceTableReset.cgi
 * correct entry in the /etc/sudoers file
 * look at /var/log/messages or /var/log/secure to see what "sudo" calls
 * look at the web servers access and error log files

=head2 /tmp cleanup

Some operating systems clean up the /tmp directory during reboot (I know that 
OpenBSD does this). This leads to the problem that the /tmp/.ifState directory
is deleted and you loose your interface information states. The solution for
this is to set the -StateDir <directory> switch from command line.

=head2 umask on file and directory creation

This program generats some files and directories on demand:

  /tmp/.ifState ... directory with table states
  /tmp/.ifCache ... directory with caching data
  /usr/local/nagios/share/interfacetable ... directory with html tables

To avoid file system conflicts we simply set the umask to 0000 so that all
files and directories are created with everyone read/write permissions.

If you don't want this - change the $UMASK variable in this program and
test it very carefully - especially under the account where the program is
executed.

  Example:
  
  # su - nagios
  nagios> check_interface_table.pl -H <host> -C <community string> -Debug 1  

=head1 LICENSE

This program was demonstrated from me during the Nagios conference in Nuernberg
(Germany) on the 12th of october 2007. Normally it is part of our commercial
suite of monitoring add ons around Nagios. This version is free software under
the terms and conditions of GPLV3.

Copyright (C) [2007]  [ITdesign Software Projects & Consulting GmbH] 

This program is free software; you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation; either version 3 of the License, or (at your option) any later
version. 

This program is distributed in the hope that it will be useful, but 
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details. 

You should have received a copy of the GNU General Public License along 
with this program; if not, see <http://www.gnu.org/licenses/>. 

=head1 COMMERCIAL Version

This version differs from our commercial version in the following:

 * Throughput on each intefcace is measured and displayed as graphs
 * Warning and critical can be set on throughput, too
 * Frequency of updates and bug fixes

Why dont't we have these features here?

From the technical point of view it is very time consuming to extract
these features out of our closed suite of add ons around nagios so 
we decided not to do it. 

What is out commercial version?

Our commercial suite of add ons around nagios contains the following
features:

 * Service Level Agreement calculation 
 * AS/400, iSeries Monitoring
 * VMWARE ESX Monitoring
 * Servicemonitorung 
 * Graph and Reports
 * Extended notification possibilities (distribution lists, 
   Notify by mobile phone, UDP, FTP, etc.)
 * and much much more
 
More details see:

 http://www.watchit.at

=head1 CONTACT INFORMATION

 Werner Neunteufl
 ITdesign Software Projects & Consulting
 Anton Freunschlaggasse 49, 1230 Wien
 Werner.Neunteufl@itdesign.at

=cut

# ------------------------------------------------------------------------
use strict;

use Net::SNMP qw(oid_base_match);
use Config::General;
use Data::Dumper;

my $STATE_OK=0;
my $STATE_WARNING=1;
my $STATE_CRITICAL=2;
my $STATE_UNKNOWN=3;

my $UMASK="0000";

# grab command line options
my $grefhOpt={};

# force help 
if ("X$ARGV[0]" eq "X") { $grefhOpt->{help}="me" };

# convert commandline arguments into hash
while (defined $ARGV[0]) {
    if ($ARGV[0] =~ /^-/) {
        $ARGV[0] =~ s/-//g;        
        $grefhOpt->{"$ARGV[0]"} = "$ARGV[1]";
    }
    shift;
}

# set debug environment variable
$grefhOpt->{Debug} and $ENV{WIT_DBG}="1";  

# ------------------------------------------------------------------------
# define OIDs here
# ------------------------------------------------------------------------
my $sysDescr        = ".1.3.6.1.2.1.1.1.0";
my $sysName         = ".1.3.6.1.2.1.1.5.0";
my $sysUpTime       = ".1.3.6.1.2.1.1.3.0";

my $ifDescr         = ".1.3.6.1.2.1.2.2.1.2";   # + ".<index>"
my $ifSpeed         = ".1.3.6.1.2.1.2.2.1.5";   # + ".<index>"

my $ifPhysAddress   = ".1.3.6.1.2.1.2.2.1.6";   # + ".<index>"
my $ifAdminStatus   = ".1.3.6.1.2.1.2.2.1.7";   # + ".<index>"
my $ifOperStatus    = ".1.3.6.1.2.1.2.2.1.8";   # + ".<index>"
my $ifLastChange    = ".1.3.6.1.2.1.2.2.1.9";   # + ".<index>"

my $ifAlias         = ".1.3.6.1.2.1.31.1.1.1.18"; # + ".<index>"

my $ipAdEntIfIndex  = ".1.3.6.1.2.1.4.20.1.2";
my $ipAdEntNetMask  = ".1.3.6.1.2.1.4.20.1.3";


my $refhPath = {};

# define cache directory or use /tmp
my $TmpDir=File::Spec->tmpdir();

# ------------------------------------------------------------------------
# set host information
#   -H <host we query>
#   -h <host we display>
# ------------------------------------------------------------------------
my $gHost;
my $ghost;
if ("$grefhOpt->{H}") {
    $gHost = "$grefhOpt->{H}";
    if ("$grefhOpt->{h}") {
        $ghost="$grefhOpt->{h}";
    } else {
        $ghost="$grefhOpt->{H}";
    }
} elsif ("$grefhOpt->{h}") {
    $ghost = "$grefhOpt->{h}";
    $gHost = "$grefhOpt->{h}";
} else {
    $grefhOpt->{help}="me"
}

# ------------------------------------------------------------------------
# set/create caching directory -CacheDir <directory>
my $gCacheDir = "$TmpDir/.ifCache";
"$grefhOpt->{CacheDir}" and $gCacheDir = "$grefhOpt->{CacheDir}";
$gCacheDir = "$gCacheDir/$gHost";
-d "$gCacheDir" or MyMkdir ("$gCacheDir");

# ------------------------------------------------------------------------
# set/create interface table state directory -StateDir <directory> 
my $gStateDir = "$TmpDir/.ifState";
"$grefhOpt->{StateDir}" and $gStateDir = "$grefhOpt->{StateDir}";
-d "$gStateDir" or MyMkdir ("$gStateDir");

# ------------------------------------------------------------------------
# set/create interface table HTML directory -HTMLDir <directory> 
my $gHTMLDir = "/usr/local/nagios/share/interfacetable";
"$grefhOpt->{HTMLDir}" and $gHTMLDir = "$grefhOpt->{HTMLDir}";

# ------------------------------------------------------------------------  
# Url to tablereset program
my $gHTMLUrl = '/nagios/interfacetable';    
defined $grefhOpt->{HTMLUrl} and $gHTMLUrl = "$grefhOpt->{HTMLUrl}";

# ------------------------------------------------------------------------
# community string
my $gCommunity = "public";
"$grefhOpt->{C}" and $gCommunity = "$grefhOpt->{C}";

# ------------------------------------------------------------------------
# Input Field Separator
my $gIFS = ",";
"$grefhOpt->{IFS}" and $gIFS = "$grefhOpt->{IFS}";

# ------------------------------------------------------------------------
# cache timer -cache <n1>,<n2>
my $gBaseCacheTimer = 3600; 
"$grefhOpt->{cache}" and $gBaseCacheTimer = "$grefhOpt->{cache}";

# ------------------------------------------------------------------------  
# Timeout for external data hook caching (undocumented Option -HookCache <time in seconds>
my $gHookCache = 15;
"$grefhOpt->{gHookCache}" and $gHookCache = "$grefhOpt->{gHookCache}";

# ------------------------------------------------------------------------  
# Url to tablereset program
my $gUrlToTableReset = '/nagios/cgi-bin';    
defined $grefhOpt->{ResetUrl} and $gUrlToTableReset = "$grefhOpt->{ResetUrl}";

# ------------------------------------------------------------------------
if ($ENV{WIT_DBG}) {
    print "host=\"$ghost\" Host=\"$gHost\" snmp community string=\"$gCommunity\"\n";
    print "CacheDir=\"$gCacheDir\" StateDir=\"$gStateDir\"\n";
    print "IFS=\"$gIFS\" cache=$gBaseCacheTimer\n";
}


# on "-help me" print help text
$grefhOpt->{help} and exit system ("pod2text -c $0");

my $gStartTime               = time (); # Time of program start
my $grefaHeader;                        # Contents of the Header table (Uptime, SysDescr, ...)
my $gHeader;                            # Generated HTML code of the Header table
my $grefaInterfaceTableData;            # Contents of the interface table (Uptime, OperStatus, ...)
my $gInterfaceTable;                    # Html code of the interface table
my $grefaAllIndizes;                    # Sorted array which holds all interface indexes
my $grefaExludedProperties;             # List of exclued properties

my $gFieldsForTable                  =               # Hash keys for the content off the html table
         'index,ifDescr,ifAlias,ifAdminStatus,ifOperStatus,ifSpeedReadable,IpInfo';
my $gHeaderForTable                  =               # Header for the cols off the html table
         'index;Description;Alias;AdminStatus;OperStatus;Speed;IP';

my $gInitialRun                      = 0;            # Flag that will be set if there exists no interface information file
my $gDifferenceCounter               = 0;            # Number of changes. This variable is used in the exitcode algorithm
my $gNumberOfInterfaces              = 0;            # Total number of interfaces
        # This is the base for the short and long cache timer.

my $grefaIPLines;                                    # Lines returned from snmpwalk storing ip addresses
my $grefaOperStatusLines;                            # Lines returned from snmpwalk storing ifOperStatus
my $gShortCacheTimer;                                # Short cache timer are calculated in ExtractCache timer routine
my $gLongCacheTimer;                                 # Short cache timer are calculated in ExtractCache timer routine
my $gText;                                           # Plugin Output ...
my $gChangeText;                                     # Contains data of changes in interface properties
my $grefhSNMP;                                       # Temp snmp structure
my $grefhFile;                                       # Properties from the interface file
my $grefhCurrent;                                    # Properties from current interface states


# create uniq file name without extension
my $gFile =  normalize($ghost).'-Interfacetable';

# file where we store interface information
# Option -D <directory> where interface information tables are stored
my $gInterfaceInformationFile = "$gStateDir/$gFile.txt";

# If -snapshot is set or DisableTrackingChanges is disabled on all interfaces
# we dont track changes
if ($grefhOpt->{nochanges} eq "ALL" or $grefhOpt->{snapshot}) {
    $gInitialRun=1;
} elsif ( $grefhOpt->{nochanges} ) {
    @$grefaExludedProperties =
        split ( /$gIFS/, $grefhOpt->{nochanges} );
}

# ------------------------------------------------------------------------------
# Read data
# ------------------------------------------------------------------------------

# get uptime of the host - no caching !
$grefhCurrent->{MD}->{sysUpTime} = GetUptime ([ "$sysUpTime" ],0);

# read all interfaces and its properties into the hash
$grefhFile = ReadInterfaceInformationFile ("$gInterfaceInformationFile");

# get sysDescr and sysName caching the long parameter
$grefhSNMP = GetMultipleDataWithSnmp ([ "$sysDescr","$sysName" ],$gLongCacheTimer);
$grefhCurrent->{MD}->{sysDescr} = "$grefhSNMP->{$sysDescr}";
$grefhCurrent->{MD}->{sysName}  = "$grefhSNMP->{$sysName}";

# get lines with interface oper status - no caching !
$grefaOperStatusLines = GetDataWithUnixSnmpWalk ($ifOperStatus,0);

if ($#$grefaOperStatusLines < 0 ) {
    print "$0: Could not read ifOperStatus information from host \"$gHost\" with snmp\n";
    exit $STATE_UNKNOWN;
}

$ENV{WIT_DBG} and print Dumper ($grefaOperStatusLines);

# get lines with ip addresses - no caching !
$grefaIPLines = GetDataWithUnixSnmpWalk ($ipAdEntIfIndex,0);

# extract ifIndex and ifOperStatus out of the lines and get the
# ifDescription from the net or from cache
Get_OperStatus_Description_Index ($grefaOperStatusLines);

# get IP Address and SubnetMask from the net or from cache
Get_IpAddress_SubnetMask ($grefaIPLines);

# get ifAdminStatus, ifSpeed and ifAlias from the net or from cache
Get_AdminStatus_Speed_Alias ($grefhCurrent);

#
# this feature is not documented because it is experimental today
# - it's a hook for some interface devices which make problems during 
# data read
if ( defined $grefhOpt->{ExternalData} ) {
    my $refaInterfaceData = GetExternalData ( $grefhOpt->{ExternalData} );
    $grefhCurrent = AppendExternalData ( $refaInterfaceData );
}

# ------------------------------------------------------------------------------
# Include / Exclude interfaces
# ------------------------------------------------------------------------------

# Include or Exclude interfaces -----------------------------------------------
# Save include/exclude information of each interface in the metadata
(defined $grefhOpt->{Exclude} or defined $grefhOpt->{Include}) and
    $grefhCurrent = EvaluateInterfaces ("$grefhOpt->{Exclude}", "$grefhOpt->{Include}");

# ------------------------------------------------------------------------------
# Create host information table data
# ------------------------------------------------------------------------------

$grefaHeader->[0]->[0]->{Value} = "$grefhCurrent->{MD}->{sysName}";
$grefaHeader->[0]->[1]->{Value} = TimeDiff (0,$grefhCurrent->{MD}->{sysUpTime} / 100);
$grefaHeader->[0]->[2]->{Value} = "$grefhCurrent->{MD}->{sysDescr}";

# ------------------------------------------------------------------------------ 
# Create interface information table data
# ------------------------------------------------------------------------------

# sort ifIndex by number
@$grefaAllIndizes = sort { $a <=> $b }
    keys (%{$grefhCurrent->{MD}->{IfIndexTable}->{ByIndex}});

#
# Generate Html Table
# do not compare ifDescr and ifIndex because they can change during reboot
#
$grefaInterfaceTableData = GenerateHtmlTable ({
    Fields               => "$gFieldsForTable",
    FieldsNoCompare      => "ifDescr,index",
});

# ------------------------------------------------------------------------------
# Create HTML tables
# ------------------------------------------------------------------------------

my $EndTime = time ();
my $TimeDiff = $EndTime-$gStartTime;

# Create "mini" info table
$gHeader = Csv2Html ("Name;Uptime;System Information;",$grefaHeader);

# Create "big" interface table
$gInterfaceTable   = Csv2Html ("$gHeaderForTable",$grefaInterfaceTableData);

# Write Html Table
WriteHtmlTable ({
    Header      => $gHeader,
    Body        => $gInterfaceTable,
    Dir					=> $gHTMLDir,
    FileName    => "$gHTMLDir/$gFile".'.html'
});

# ------------------------------------------------------------------------------
# write interface information file
# ------------------------------------------------------------------------------

# first run - the hash from the file is empty because we had no file before
# fill it up with all interface intormation and with the index tables
#
# we take a separate field where we remember the last reset
# of the entire file
if (not $grefhFile->{TableReset}) {
    $grefhFile->{TableReset} = scalar localtime time ();
    $grefhFile->{If} = $grefhCurrent->{If};
}

# Fill up the MD tree (MD = MetaData) - here we store all variable
# settings
$grefhFile->{MD} = $grefhCurrent->{MD};

# ------------------------------------------------------------------------------
# write interface information file
# ------------------------------------------------------------------------------

WriteConfigFileNew ("$gInterfaceInformationFile",$grefhFile);

# ------------------------------------------------------------------------------
# STDOUT
# ------------------------------------------------------------------------------

# If there are changes in the table write it to stdout
if ($gChangeText) {
    $gText = $gChangeText . "Total $gNumberOfInterfaces interface(s)";
} else {
    $gText = "OK: Total $gNumberOfInterfaces interface(s)"
}

# If current run is the first run we dont compare data
if ( $gInitialRun ) {
     $ENV{WIT_DBG} and
        print " (Debug) Initial run -> Setting DifferenceCounter to zero.\n";
    $gDifferenceCounter = 0;
    $gText = "OK: Total $gNumberOfInterfaces interface(s)";
} else {
    $ENV{WIT_DBG} and print " (Debug) Differences: $gDifferenceCounter\n";
}

# ------------------------------------------------------------------------------
# Calculate exitcode and exit this program
# ------------------------------------------------------------------------------

# $gDifferenceCounter contains the number of changes which
# were made in the interface configurations
my $ExitCode = mcompare ({
    Value       => $gDifferenceCounter,
    Warning     => $grefhOpt->{w},
    Critical    => $grefhOpt->{c}
});

# Append html table link to text
$gText = AppendLinkToText({
	  Text        => $gText,
	  HtmlUrl     => $gHTMLUrl,
	  File				=> "$gFile.html"   
	});

# Print Text and exit with the correct exitcode
ExitPlugin ({
    ExitCode    =>  $ExitCode,
    Text        =>  $gText,
    Fields      =>  $gDifferenceCounter
});

# This code should never be reached
exit $STATE_UNKNOWN;

# ------------------------------------------------------------------------
#      MAIN ENDS HERE
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Create interface table html table file
# This file will be visible on the browser
#
# WriteHtmlTable ({
#    Header      => $gHeader,
#    Body        => $gInterfaceTable,
#    FileName    => $gHtmlFileName
# });
#
# ------------------------------------------------------------------------
sub WriteHtmlTable {

    my $refhStruct = shift;

    my $Footer = HtmlLinks ({
        Back            =>  1,
        ResetTable      =>  "$gInterfaceInformationFile"
    });

    umask "$UMASK";

		not -d $refhStruct->{Dir} and MyMkdir($refhStruct->{Dir});

    open (OUT,">$refhStruct->{FileName}") or die "cannot $refhStruct->{FileName} $!";
        print OUT '<center><pre><a href="http://',$gHost,'">',$gHost,'</a>',
            ' updated: ',scalar localtime $EndTime,' (',$EndTime-$gStartTime,' sec.)</pre>';
        print OUT $refhStruct->{Header};
        print OUT $refhStruct->{Body};
        print OUT $Footer;
        print OUT '<center>';
    close (OUT);
    return 0;
}

# ------------------------------------------------------------------------
# Source: 
#   extracted from or our base library - but shortand 
# Purpose:
#   calc exit code 
# ------------------------------------------------------------------------
sub mcompare {

    my $refhStruct = shift;

    my $ExitCode = $STATE_OK; 

    $refhStruct->{Warning} and $refhStruct->{Value} >= $refhStruct->{Warning} 
        and $ExitCode = $STATE_WARNING;
        
    $refhStruct->{Critical} and $refhStruct->{Value} >= $refhStruct->{Critical} 
        and $ExitCode = $STATE_CRITICAL;    

    return $ExitCode;
}

# ------------------------------------------------------------------------
# Compare data from refhFile and refhCurrent and create the csv data for
# html table.
#
# $grefaInterfaceTableData = GenerateHtmlTable ({
#     Fields      => "ifAlias,ifAdminStatus,ifOperStatus,ifSpeedReadable,IpInfo"
# });
# ------------------------------------------------------------------------
sub GenerateHtmlTable {

    my $refhStruct = shift;

    # Array of the fields for the table
    my $refaFields      = [ split ( ',', $refhStruct->{Fields} ) ] ;

    # Array of fields which should be excluded from change tracking
    my $refaNoCompare   = [ split ( ',', $refhStruct->{FieldsNoCompare} ) ] ;

    # Fluss Variable (ah geh ;-) )
    my $iLineCounter = 0;

    # This is the final data structure which we pass to csv2htmlnew
    my $refaContentForHtmlTable;

    # MD5 Checksum
    my $DataForMD5CheckSum;

    # Print a header for debug information
    if ( $ENV{WIT_DBG} ) { print "x"x50; print "\n"; }

    # $grefaAllIndizes is a indexed and sorteted list of all interfaces
    for my $InterfaceIndex (@$grefaAllIndizes) {

        # Current field ID
        my $iFieldCounter = 0;

        # Get normalized interface name (key for If data structure)
        my $ifDescr = $grefhCurrent->{MD}->{IfIndexTable}->{ByIndex}->{$InterfaceIndex};

        # This is the If datastructure from the interface information file
        my $refhInterFaceDataFile     = $grefhFile->{If}->{$ifDescr};

        # This is the current measured If datastructure
        my $refhInterFaceDataCurrent  = $grefhCurrent->{If}->{$ifDescr};

        # This variable used for exittext
        $gNumberOfInterfaces++;

        for my $FieldName ( @$refaFields ) {

            my $ChangeTime;
            my $LastChangeInfo;
            my $CellColor;
            my $CellBackgroundColor;
            my $CellContent;

            # This is used to calculate the id (used for displaying the html table)
            $DataForMD5CheckSum .= $refhInterFaceDataCurrent->{"$FieldName"};

            # Flag if the current status of this field should not be compared with the
            # "snapshoted" status of this field.
            my $DontCompareThisField = grep (/$FieldName/i, @$refaNoCompare);

            my $CurrentFieldContent  = $refhInterFaceDataCurrent->{"$FieldName"};
            my $FileFieldContent     = $refhInterFaceDataFile->{"$FieldName"};

            # Delete the first and last "blank"
            $CurrentFieldContent =~ s/^ //;
            $CurrentFieldContent =~ s/ $//;

            # some fields have a change time property in the interface information file.
            # if the change time exists we store this and write into html table
            $ChangeTime = $grefhFile->{MD}->{If}->{$ifDescr}->{$FieldName."ChangeTime"};

            # If interface is excluded or this is the initial run we dont lookup
            # data changes and mark all properties of this interface olive
            if ($grefhCurrent->{MD}->{If}->{$ifDescr}->{Excluded} eq "true"
                or $gInitialRun  )  {
                $DontCompareThisField = 1;
                # Change the font color to "olive"
                $CellColor     = '<font color="#808000">';
            }

            # Set LastChangeInfo to this Format "(since 0d 0h 43m)"
            if ( defined $ChangeTime and defined $grefhOpt->{trackduration} ) {
                $ChangeTime = TimeDiff ("$ChangeTime",time());
                $LastChangeInfo = "(since $ChangeTime)";
            }
#
# not needed in GPL2 version ifDescr is never compared
#
## Special Cells ----------------------------------------------------------------
#
#						if ( $FieldName eq "ifDescr" ) {
#            	# We denormalize the ifDescr for displaying purposes
#            	$CurrentFieldContent = denormalize ($CurrentFieldContent);
#          	}

# Special Cells end -------------------------------------------------------------

            # If this field wont be compared wer just write the current field - value
            # in the table.
            if ( $DontCompareThisField  ) {
                $ENV{WIT_DBG} and print "Not comparing $FieldName on interface ".denormalize($ifDescr)."\n";
                $CellContent = denormalize( $CurrentFieldContent );
            } else {
                # Field content has NOT changed
                $ENV{WIT_DBG} and print
                    "Compare \"".denormalize($ifDescr)."($FieldName)\" now=\"$CurrentFieldContent\" file=\"$FileFieldContent\"\n";                                    
                if ( $CurrentFieldContent eq $FileFieldContent ) {
                    $CellContent = denormalize ( $CurrentFieldContent );
                } else {
                # Field content has changed ...
                    $CellContent = "New Value: " . denormalize( $CurrentFieldContent ) . "$LastChangeInfo Old Value: " . denormalize ( $FileFieldContent );

                    $gChangeText .= "(" . denormalize ($ifDescr) .
                        ") $FieldName changed to <b>$CurrentFieldContent</b> (previous value:  <b>$FileFieldContent</b>)<br>";

                    $CellBackgroundColor = "red";

                    $gDifferenceCounter++;
                }
            }

            # Write an empty cell content if CellContent is empty
            # This is for visual purposes
            not $CellContent and $CellContent = '&nbsp';

            # Store cell content in table
            $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{"Value"} = "$CellContent";

            # Change font and background color
            defined $CellColor and 
              $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{Font} = 
              $CellColor;
            defined $CellBackgroundColor and 
              $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{Background} = 
              $CellBackgroundColor;

            $iFieldCounter++;
        } # for FieldName
        $iLineCounter++;
    } # for $InterfaceIndex

    # Print a footer for debug information
     if ( $ENV{WIT_DBG} ) { print "x"x50; print "\n"; }

    return $refaContentForHtmlTable;
}

# ------------------------------------------------------------------------
# This function encludes or excludes interfaces from change comparison
# if there are exclude or include lists defined on the commandline.
#
# All interfaces which are excluded will be excluded from 
# traffic measurement and change counter count.
#
#   Indicated must be the interface name (ifDescr)
#   -Exclude "3COM Etherlink PCI"
#
#   It is possible to exclude all interfaces
#   -Exclude "ALL"
#
#   It is possible to exclude all interfaces but include one
#   -Exclude "ALL" -Include "3COM Etherlink PCI"
#
# It isnt neccessary to include ALL. This function does not exist.
#
# The interface information file will be altered as follows:
#
# <MD>
#    <If>
#        <3COMQ20EtherlinkQ20PCI>
#            CacheTimer   3600
#            Excluded     true
#            ifOperStatusChangeTime   1151586678
#        </3COMQ20EtherlinkQ20PCI>
#    </If>
# </MD>
#
# ------------------------------------------------------------------------
sub EvaluateInterfaces {

    my $ExcludeString = shift;
    my $IncludeString = shift;

    my @ExcludeList = split (/$gIFS/,$ExcludeString);
    my @IncludeList = split (/$gIFS/,$IncludeString);

    # Here we exlude Interfaces which are set in query
    for my $ifDescr (keys %{$grefhCurrent->{MD}->{If}}) {

        # Denormalize interface name
        my $ifDescrReadable = denormalize ($ifDescr);

        # For each exclusion
        for my $ExcludeString (@ExcludeList) {
            if ("$ifDescrReadable" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                $ENV{WIT_DBG} and print "-- exclude ($ExcludeString) interface \"$ifDescrReadable\"\n";
                $grefhCurrent->{MD}->{If}->{$ifDescr}->{Excluded} = "true";
            }
        }

        # Include interfaces ..
        for my $IncludeString (@IncludeList) {
            if ("$ifDescrReadable" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                $ENV{WIT_DBG} and print "+ include ($IncludeString) interface \"$ifDescrReadable\"\n";
                $grefhCurrent->{MD}->{If}->{$ifDescr}->{Excluded} = "false";
            }
        }

    } # for each interface
    return $grefhCurrent;
}

# ------------------------------------------------------------------------
# Get the uptime of the remote system and store timeticks in raw format
# (not translated into human readable format)
# ------------------------------------------------------------------------
sub GetUptime {
    my $refaOID     = shift;
    my $CacheTimer  = shift;

    my $Value = SnmpGetV1 ({
        -hostname   => "$gHost",
        -community  => "$gCommunity",
        -translate  => [ -timeticks => 0x0 ], # disable conversion get raw timeticks
        OID         => $refaOID,
        CacheTimer  => int rand ($CacheTimer),
        Debug       => $ENV{WIT_DBG},
    });

    # we got data
    if ($Value > 0) {
        return $Value;
    } else {
        # und tschuess - hat keinen Sinn weiter zu machen        
        print "$0: Could not read sysUpTime information from host \"$gHost\" with snmp\n";
        exit $STATE_UNKNOWN;
    }
}
# ------------------------------------------------------------------------
# Get Data with perl net-snmp module
# ------------------------------------------------------------------------
sub GetDataWithSnmp {
    my $refaOID     = shift;    # ref to array of OIDs (numbers only)
    my $CacheTimer  = shift;

    my $Value = SnmpGetV1 ({
        -hostname   => "$gHost",      # option -h
        -community  => "$gCommunity", # option -C
        OID         => $refaOID,
        CacheTimer  => int rand ($CacheTimer),  # random caching
        Debug       => $ENV{WIT_DBG},       # Debug
    });

    return ($Value);
}

# ------------------------------------------------------------------------
# Get multiple Data with perl net-snmp module
# ------------------------------------------------------------------------
sub GetMultipleDataWithSnmp {
	
    my $refaOID     = shift;    # ref to array of OIDs (numbers only)
    my $CacheTimer  = shift;

    my $refhSNMP = SnmpGetV1 ({
        -hostname   => "$gHost",      # option -h
        -community  => "$gCommunity", # option -C
        OID         => $refaOID,
        CacheTimer  => int rand ($CacheTimer),  # random caching
        Debug       => $ENV{WIT_DBG},       # Debug
    });

    return ($refhSNMP);
}
# ------------------------------------------------------------------------
# Get Data with the unix snmpwalk command - this is faster than perls
# snmp implementation
# ------------------------------------------------------------------------
sub GetDataWithUnixSnmpWalk {
	
    my $OID         = shift;    # only one OID (number or name)
    my $CacheTimer  = shift;

    my ($refaLines) = ExecuteCommand ({
        Command     => "snmpwalk -Oqn -c '$gCommunity' -v 1 $gHost $OID",
        Retry       =>  2,
        CacheTimer  =>  int rand ($CacheTimer),
        Debug       =>  $ENV{WIT_DBG}
    });

    return $refaLines;
}
# ------------------------------------------------------------------------
# get ifOperStatus, ifDescr and ifIndex
# ------------------------------------------------------------------------
sub Get_OperStatus_Description_Index {

    my $refaOperStatusLines = shift;

    # Example of $refaOperStatusLines
    #    .1.3.6.1.2.1.2.2.1.8.1 up
    #    .1.3.6.1.2.1.2.2.1.8.2 down
    for (@$refaOperStatusLines) {
        my ($Index,$OperStatusNow) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $OperStatusNow =~ s/\s+$//g;    # remove invisible chars from the end

        $ENV{WIT_DBG} and print "Index = $Index $gLongCacheTimer\n";
        # read the interface description with the index extracted above
        my $Desc = GetDataWithSnmp ([ "$ifDescr.$Index" ],$gLongCacheTimer);

        # check an empty interface description and add a new description
        # this occurs on some devices (e.g. HP procurve switches)
        if ("$Desc" eq "") {
            # read the MAC address of the interface - independend if it has one
            # or not
            my $MacAddress = GetDataWithSnmp ([ "$ifPhysAddress.$Index" ],
                $gShortCacheTimer);

            $Desc = "($MacAddress)";

            if ($ENV{WIT_DBG}) {
                print "Interface with index $Index has no description.";
                print " Set it to $Desc\n";
            }
        }

        # normalize the interface description to not get into trouble
        # with special characters and how Config::General handles blanks
        $Desc = normalize ($Desc);

        # on some operating systems there could be interfaces with
        # the same name - check this out - append uniq text at the end to
        # get a uniq interface name
        if ($grefhCurrent->{If}->{"$Desc"}) {
            my $Text; # dummy text for uniq if description

            # read the MAC address of the interface
            my $MacAddress = GetDataWithSnmp ([ "$ifPhysAddress.$Index" ],
                $gShortCacheTimer);

            # check if we got back a MAC Address - otherwise take the interface
            # index - this could only lead to problems where index is changed
            # during reboot and duplicate interface names
            if ($MacAddress) {
                $Text = "(${MacAddress})";
            } else {
                $Text = "(${Index})";
            }

            $ENV{WIT_DBG} and
                print "Duplicate if ($Index) name - \"$Text\"\n";

            # append a blank (normalized) the MAC Address or the index
            # to the end of the description
            $Desc = "${Desc}Q20".normalize($Text);
        }

        # Store the oper status as property of the current interface
        $grefhCurrent->{If}->{"$Desc"}->{ifOperStatus}    = "$OperStatusNow";

        #
        # Store a CacheTimer (seconds) where we cache the next
        # reads from the net - we have the following possibilities
        #
        # ifOperStatus:
        #
        # Current state | first state  |  CacheTimer
        # -----------------------------------------
        # up              up              $gShortCacheTimer
        # up              down            0
        # down            down            $gLongCacheTimer
        # down            up              0
        # other           *               0
        # *               other           0
        #
        # One exception to that logic is the "Changed" flag. If this
        # is set we detected a change on an interface property and do not
        # cache !
        #
        my $OperStatusFile = $grefhFile->{If}->{"$Desc"}->{ifOperStatus};

        $ENV{WIT_DBG} and print "Now=\"$OperStatusNow\" File=\"$OperStatusFile\"\n";
        # set cache timer for further reads
        if ("$OperStatusNow" eq "up" and "$OperStatusFile" eq "up") {
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{CacheTimer} = $gShortCacheTimer;
        } elsif ("$OperStatusNow" eq "down" and "$OperStatusFile" eq "down") {
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{CacheTimer} = $gLongCacheTimer;
        } else {
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{CacheTimer} = 0;

            $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeText} =
                "Old = \"$OperStatusFile\", Current = \"$OperStatusNow\" ";
        }

        # remember change time of the interface property
        if ($grefhFile->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime}) {
                        # umkopieren damit am Ende die Info erhalten bleibt
                $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime} =
                    $grefhFile->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime}
        } else {
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime} = time;
        }

        # track changes of the oper status
        if ("$OperStatusNow" eq "$OperStatusFile") {   # no changes to its first state
            # delete the changed flag and reset the time when it was changed
            if ($grefhFile->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeText}) {
                delete $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeText};
                $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime} = time;
            }
        # ifOperstatus has changed
        } else {
            # flag if changes already tracked
            if (not $grefhFile->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeText}) {
                $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeTime} = time;
            }

            # remember the change every run of this program, this is useful if the
            # ifOperStatus changes from "up" to "testing" to "down"
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{ifOperStatusChangeText} =
                "Old = \"$OperStatusFile\", Current = \"$OperStatusNow\" ";
        }


        # create another tree in the MetaData hash which stores interface index
        # and description. This is used later wehen getting the ip address
        # and for displaying the html table
        $grefhCurrent->{MD}->{IfIndexTable}->{ByIndex}->{"$Index"} = "$Desc";
        $grefhCurrent->{MD}->{IfIndexTable}->{ByName}->{"$Desc"} = "$Index";

         # Store Index und Description in MD. This is needed for displaying the
         # Html table. lukas2
         $grefhCurrent->{If}->{$Desc}->{index}   = "$Index";
         $grefhCurrent->{If}->{$Desc}->{ifDescr} = "$Desc";

    }
    return 0;
}

# ------------------------------------------------------------------------
# extract ip addresses out of snmpwalk lines
#
# # snmpwalk -Oqn -c public -v 1 router IP-MIB::ipAdEntIfIndex
# .1.3.6.1.2.1.4.20.1.2.172.31.92.91 15
# .1.3.6.1.2.1.4.20.1.2.172.31.92.97 15
# .1.3.6.1.2.1.4.20.1.2.172.31.99.76 15
# .1.3.6.1.2.1.4.20.1.2.193.83.153.254 29
# .1.3.6.1.2.1.4.20.1.2.193.154.197.192 14
#
# ------------------------------------------------------------------------
sub Get_IpAddress_SubnetMask {
    my $refaIPLines = shift;

    my $refaNetMask;

    # store all ip information in the hash to avoid reading the netmask
    # again in the next run
    $grefhCurrent->{MD}->{SnmpIpInfo} = join (";",@$refaIPLines);

    # remove all invisible chars incl. \r and \n
    $grefhCurrent->{MD}->{SnmpIpInfo} =~ s/[\000-\037]|[\177-\377]//g;

    # # snmpwalk -Oqn -v 1 -c public router IP-MIB::ipAdEntNetMask
    # .1.3.6.1.2.1.4.20.1.3.172.31.92.91 255.255.255.255
    # .1.3.6.1.2.1.4.20.1.3.172.31.92.97 255.255.255.255
    #
    # read the subnet masks with caching 0 only if the ip addresses
    # have changed
    if ($grefhCurrent->{MD}->{SnmpIpInfo} eq $grefhFile->{MD}->{SnmpIpInfo}) {
        $refaNetMask = GetDataWithUnixSnmpWalk ($ipAdEntNetMask,$gLongCacheTimer);
    } else {
        $refaNetMask = GetDataWithUnixSnmpWalk ($ipAdEntNetMask,0);
    }

    # Example lines:
    # .1.3.6.1.2.1.4.20.1.2.172.31.99.76 15
    # .1.3.6.1.2.1.4.20.1.2.193.83.153.254 29
    for (@$refaIPLines) {
        my ($IpAddress,$Index) = split / /,$_,2;        # blank splits OID & ifIndex
        $IpAddress  =~  s/^.*1\.4\.20\.1\.2\.//;    # remove up to the ip address
        $Index          =~  s/\D//g;                    # remove all but numbers

        # extract the netmask
        #
        # $refaNetMaks looks like this:
        #
        # $VAR1 = [
        #          '.1.3.6.1.2.1.4.20.1.3.10.1.1.4 255.255.0.0',
        #          '.1.3.6.1.2.1.4.20.1.3.10.2.1.4 255.255.0.0',
        #          '.1.3.6.1.2.1.4.20.1.3.172.30.1.4 255.255.0.0
        #        ];

        my ($Tmp,$NetMask) = split (" ",join ("",grep /$IpAddress /,@$refaNetMask),2);
        $NetMask    =~ s/\s+$//;    # remove invisible chars from the end

        # get the interface description stored before from the index table
        my $Desc = $grefhCurrent->{MD}->{IfIndexTable}->{ByIndex}->{"$Index"};

        # separate multiple IP Adresses with a blank
        # blank is good because the WEB browser can break lines
        if ($grefhCurrent->{If}->{"$Desc"}->{IpInfo}) {
            $grefhCurrent->{If}->{"$Desc"}->{IpInfo} =
            $grefhCurrent->{If}->{"$Desc"}->{IpInfo}." "
        }
        # now we are finished with the puzzle of getting ip and subnet mask
        # add IpInfo as property to the interface
        my $IpInfo = "$IpAddress/$NetMask";
        $grefhCurrent->{If}->{"$Desc"}->{IpInfo} .= $IpInfo;

        # check if the IP address has changed to its first run
        my $FirstIpInfo = $grefhFile->{If}->{"$Desc"}->{IpInfo};

        # disable caching of this interface if ip information has changed
        if ("$IpInfo" ne "$FirstIpInfo") {
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{CacheTimer} = 0;
            $grefhCurrent->{MD}->{If}->{"$Desc"}->{CacheTimerComment} =
                "caching is disabled because of first or current IpInfo";
        }
    }
    return 0;
}

# ------------------------------------------------------------------------
# Read config file with the perl Config::General Module
#
#   http://search.cpan.org/search?query=Config%3A%3AGeneral&mode=all
#
# ------------------------------------------------------------------------
sub ReadConfigFileNew {

    my $ConfigFile = shift;

    my $refoConfig; # object definition for the config
    my $refhConfig; # hash reference returned

    # return undef if file is not readable
    -r "$ConfigFile" or return $refhConfig;

    # Initialize ConfigFile Read Process (create object)
    $refoConfig = new Config::General (
        -ConfigFile             => "$ConfigFile",
        -UseApacheInclude       => "false",
        -MergeDuplicateBlocks   => "false",
        -InterPolateVars        => "false",
    );

    # Read Config File
    %$refhConfig = $refoConfig->getall;

    # return reference
    return $refhConfig;
}
# ------------------------------------------------------------------------
# --- write a hash reference to a file --- see ReadConfigFileNew ---------
#
# $gFile = full qulified filename with path
# $refhStruct = hash reference
#
# ------------------------------------------------------------------------
sub WriteConfigFileNew {
    my $ConfigFile   =   shift;
    my $refhStruct   =   shift;

    use File::Basename;

    my $refoConfig; # object definition for the config
    my $Directory = dirname ($ConfigFile);

    # Initialize ConfigFile Read Process (create object)
    $refoConfig = new Config::General (
        -ConfigPath => "$Directory"
    );

    # Write Config File
    if (-f "$ConfigFile" and not -w "$ConfigFile") {
        print "Unable to write to file $ConfigFile $!\n";
        exit $STATE_UNKNOWN;
    }

    $refoConfig->save_file("$ConfigFile", $refhStruct);
    $ENV{WIT_DBG} and print "Wrote interface data to file: $ConfigFile\n";

    return 0;
}
# ------------------------------------------------------------------------
# walk through each interface and read ifAdminStatus, ifSpeed and ifAlias
# ------------------------------------------------------------------------
sub Get_AdminStatus_Speed_Alias {

    # loop through all found interfaces
    for my $Desc (keys %{$grefhCurrent->{If}}) {

        my $CacheTimer = 0;

        # extract the index out of the MetaData
        my $Index           = $grefhCurrent->{MD}->{IfIndexTable}->{ByName}->{"$Desc"};

        # Current state | first state  |  CacheTimer
        # -----------------------------------------
        # down            down            $gLongCacheTimer
        # *               *               0
        my $OperStatusNow  = $grefhCurrent->{If}->{"$Desc"}->{ifOperStatus};
        my $OperStatusFile = $grefhFile->{If}->{"$Desc"}->{ifOperStatus};

         # Set cachtimer to the long cache timer value if the operstatus is now down
         # and was down in the past.
         if ( ( "$OperStatusNow" eq "down" ) and ( "$OperStatusFile" eq "down" ) ) {
            $CacheTimer = $gLongCacheTimer;
         }

        # get next interface properties with caching to avoid network load
        my $refhSNMP = GetMultipleDataWithSnmp (
            [ "$ifAdminStatus.$Index", "$ifSpeed.$Index","$ifAlias.$Index" ],$CacheTimer);

        # store ifAdminStatus converted from a digit to "up" or "down"
        $grefhCurrent->{If}->{"$Desc"}->{ifAdminStatus} =
            ConvertAdminStatusToReadable ($refhSNMP->{"$ifAdminStatus.$Index"});

        # store ifSpeed in a machine and human readable format
        $grefhCurrent->{If}->{"$Desc"}->{ifSpeed} =
            ($refhSNMP->{"$ifSpeed.$Index"});
        $grefhCurrent->{If}->{"$Desc"}->{ifSpeedReadable} =
            ConvertSpeedToReadable ($refhSNMP->{"$ifSpeed.$Index"});

        # store ifAlias normalized to not get into trouble with special chars
        $grefhCurrent->{If}->{"$Desc"}->{ifAlias} =
            normalize ($refhSNMP->{"$ifAlias.$Index"});
    }
    return 0;
}
# ------------------------------------------------------------------------
# extract two cache timers out of the commandline -cache option
#
# Examples:
#   -cache 150              $gShortCacheTimer = 150 and $Long... = 300
#   -cache 3600,86400       $gShortCacheTimer = 3600 and $Long...= 86400
#
# ------------------------------------------------------------------------
sub ExtractCacheTimer {
    my $CacheString = shift;

    # only one number entered
    if ($CacheString =~ /^\d+$/) {
        $gShortCacheTimer = $CacheString;
        $gLongCacheTimer  = 2*$gShortCacheTimer;
    # two numbers entered - separated with a comma
    } elsif ($CacheString =~ /^\d+$gIFS\d+$/) {
        ($gShortCacheTimer,$gLongCacheTimer) = split (/$gIFS/,$CacheString);
    } else {
        print "$0: Wrong cache timer specified\n";
        exit $STATE_UNKNOWN;
    }
    $ENV{WIT_DBG} and
        print "Set ShortCacheTimer = $gShortCacheTimer and LongCacheTimer = $gLongCacheTimer\n";
    return ($gShortCacheTimer,$gLongCacheTimer);
}
# ------------------------------------------------------------------------
# get the interface speed as integer and convert it to a readable format
# return a string
# ------------------------------------------------------------------------
sub ConvertSpeedToReadable {
    my $Speed = shift;
    if ($Speed > 999999999) {
        $Speed = sprintf ("%0.2f Gbit",$Speed/1000000000);
    } elsif ($Speed > 999999) {
        $Speed = sprintf ("%0.2f Mbit",$Speed/1000000);
    } elsif ($Speed > 999) {
        $Speed = sprintf ("%0.2f kbit",$Speed/1000);
    } elsif ($Speed > 0) {
        $Speed = sprintf ("%0.2f bit",$Speed);
    } else {
        $Speed = "";
    }
    return $Speed;
}
# ------------------------------------------------------------------------
# get the interface administrative status as integer or string and convert
# it to a readable format - return a string
#
# http://www.faqs.org/rfcs/rfc2863.html
#
#    ifAdminStatus OBJECT-TYPE
#        SYNTAX  INTEGER {
#                    up(1),       -- ready to pass packets
#                    down(2),
#                    testing(3)   -- in some test mode
#                }
# ------------------------------------------------------------------------
sub ConvertAdminStatusToReadable {
    my $AdminStatus = shift;
    if ($AdminStatus =~ /1/) {
        $AdminStatus = "up";
    } elsif ($AdminStatus =~ /2/) {
        $AdminStatus = "down";
    } elsif ($AdminStatus =~ /3/) {
        $AdminStatus = "testing";
    } else {
        # we do nothing and leave the original status
    }
    return $AdminStatus;
}

# ------------------------------------------------------------------------
# Read all interfaces and its properties into the hash $grefhFile
# ------------------------------------------------------------------------
sub ReadInterfaceInformationFile {

    my $InterfaceInformationFile = shift;

    my $grefhFile;

    # read all properties from the state file - store into $grefhFile
    if (-r "$InterfaceInformationFile") {
        $grefhFile = ReadConfigFileNew ("$InterfaceInformationFile");

        # we got data from an old formated file - check this
        if (not $grefhFile->{MD}->{sysUpTime}) {
            unlink ("$InterfaceInformationFile");   # delete the old file
            print "$0: first run - initializing interface table now\n";
            exit $STATE_OK;
        }

        # check if the uptime read from the host > then the uptime
        # stored in the file -> means host was not rebooted
        if ($grefhCurrent->{MD}->{sysUpTime} > $grefhFile->{MD}->{sysUpTime} and
            $gBaseCacheTimer) {

            # extract cache timers out of the command line option
            ($gShortCacheTimer,$gLongCacheTimer) = ExtractCacheTimer ("$gBaseCacheTimer");
        # it seems that the remote system was rebooted - caching is disabled
        }
    # the file with interface information was not found - this is the first
    # run of the program or it was deleted before
    } else {
        # the file was not found - store the sysUptime immediately
        # Grund: Wenn das Programm mitten drinnen unterbrochen wird
        # (z.B. service check time out) greift beim naechsten Aufruf
        # das Caching.
        WriteConfigFileNew ("$InterfaceInformationFile",$grefhCurrent);
        $gInitialRun = 1;
    }
    return $grefhFile;
}

# ------------------------------------------------------------------------
# Get data from external interface program
#
# The program should deliver results in this format:
#
# Index:=<InterfaceIndex>,<Key>:=<Value>,<Key>:=<Value>, ...
# Note: Index has to be the first property
#
# Example result:
#
# Index:=33,ifAlias:=(25)
# Index:=32,ifAlias:=(24) VMW51S-nic4
# Index:=21,ifAlias:=(13) FWW11E-1/4
# Index:=59,ifAlias:=(51)
# Index:=26,ifAlias:=(18)
# Index:=17,ifAlias:=(9)
# Index:=54,ifAlias:=(46)
# Index:=53,ifAlias:=(45)
# Index:=18,ifAlias:=(10)
# Index:=30,ifAlias:=(22) FWW11E-4/4
# ------------------------------------------------------------------------
sub GetExternalData {

    my $InterfaceCommand = shift;

    my ($refaInterfaceResponse) = ExecuteCommand ({
        Command     => "$InterfaceCommand",
        Retry       =>  2,
        CacheTimer  =>  $gHookCache,
        Debug       =>  $ENV{WIT_DBG}
    });

    $ENV{WIT_DBG} and print "Result: " , Dumper ($refaInterfaceResponse);

    return $refaInterfaceResponse;
}

# ------------------------------------------------------------------------
# Append data from external interface program to $grefhCurrent
# ------------------------------------------------------------------------
sub AppendExternalData {

    my $refaInterfaceData = shift;
    my $PROPERTY_FS       = ",";
    my $DATA_FS           = ":=";

    # For each Index:=33,ifAlias:=(25),...
    for my $InterfaceDataLine ( @$refaInterfaceData ) {

        my $Property;
        my $InterfaceIndex;
        my $refaRawIfProperties;

        @$refaRawIfProperties = split ( /$PROPERTY_FS/, $InterfaceDataLine );

        # Get the interface index Index:=33,ifAlias:=(25),...
        ( $Property,$InterfaceIndex ) =
            #split ( /$DATA_FS/, @$refaRawIfProperties->[0] );
            split ( /$DATA_FS/, @$refaRawIfProperties[0] );

        my $InterfaceDescr =
            $grefhCurrent->{MD}->{IfIndexTable}->{ByIndex}->{$InterfaceIndex};

        # For each property from interface ifAlias:=(25),...
        for ( 1...$#$refaRawIfProperties ) {
            my ( $Property,$Value ) =
                #split ( /$DATA_FS/, @$refaRawIfProperties->[$_] );
                split ( /$DATA_FS/, @$refaRawIfProperties[$_] );

            # Save data from each property into $grefhCurrent
            chomp ($Value);
            $grefhCurrent->{If}->{$InterfaceDescr}->{$Property} = "$Value";
        }
    }
    
    return $grefhCurrent;
}

# ------------------------------------------------------------------------
# calculate time diff of unix epoch seconds and return it in
# a readable format
#
# my $x = TimeDiff ("1150100854","1150234567");
# print $x;   # $x equals to 1d 13h 8m
#
# ------------------------------------------------------------------------
sub TimeDiff {
    my $StartTime = shift;
    my $EndTime = shift;

    my $String = "(NoData)"; # default text (error)

    my $Days  = 0;
    my $Hours = 0;
    my $Min   = 0;
    my $TimeDiff;
    my $Rest;

    # check start must be before end
    if ($EndTime < $StartTime) {
        return "$String";
    }

    $TimeDiff = $EndTime - $StartTime;

    $Days = int ($TimeDiff / 86400);
    $Rest = $TimeDiff - ($Days * 86400);

    if ($Rest < 0) {
        $Days = 0;
        $Hours = int ($TimeDiff / 3600);
    } else {
        $Hours = int ($Rest / 3600);
    }

    $Rest = $Rest - ($Hours * 3600);

    if ($Rest < 0) {
        $Hours = 0;
        $Min = int ($TimeDiff / 60);
    } else {
        $Min = int ($Rest / 60);
    }

    return "${Days}d ${Hours}h ${Min}m";
}

# ------------------------------------------------------------------------
# normalize and denormalize subroutines extracted from our Common library
# - used to get rid of special characters
# ------------------------------------------------------------------------
sub normalize {
    my $Text=shift;

    # Q normalisieren
    $Text=~s/Q/Q51/g;

    # einstellige HEX Zahlen mit 0 davor konvertieren
    $Text=~s/[\000-\017]/sprintf ("Q0%X",ord($&))/ge;

    # alle anderen Zeichen durch Q + HEX code ersetzen
    $Text=~s/[\W_]/sprintf ("Q%X",ord($&))/ge;

    # fertig
    return $Text;
}

# ------------------------------------------------------------------------
# normalize and denormalize subroutines extracted from our Common library
# - used to get rid of special characters
# ------------------------------------------------------------------------

sub denormalize {
    my $Text=shift;
    $Text=~s/Q../pack "H2",substr($&,1,3)/ge;
    return $Text;
}

# ------------------------------------------------------------------------
# routine extracted from our communications library
# ------------------------------------------------------------------------
sub SnmpGetV1 {
    my $refhStruct = shift;
    
    #
    # store variables and delete them from the hash 
    # this is necessary for the snmp session which takes the same
    # hash ref and does not work with arguments other than starting
    # with a dash
    # see http://search.cpan.org/search?query=Net%3A%3ASnmp&mode=all
    #
    my $refaOIDs            = $refhStruct->{OID}; # ref to array of OIDs
    my $GlobalCacheTimer    = $refhStruct->{CacheTimer}; # CacheTimer
    my $Debug               = $refhStruct->{Debug};
    
    delete $refhStruct->{OID};
    delete $refhStruct->{CacheTimer};
    delete $refhStruct->{Debug};
        
    my $refhSnmpValues; # hash returned to the caller
    my $refoSession;    # SNMP session object
    my $SessionError;   # SNMP session error 

    # example cache dir name
    # /tmp/watchit/Cache/SnmpGetV1/cat-itd-01
    my $CacheDir = "$gCacheDir/SnmpGetV1";
    
    # Create the directory if not existend
    not -d $CacheDir and MyMkdir($CacheDir);

    # create snmp V1 session
    ($refoSession,$SessionError) = Net::SNMP->session (%$refhStruct);
    
    my $OIDLine;    # one line of OIDs or OIDs and caching timers
    my $SnmpValue;  # one snmp value

    if (defined $refoSession) {

        # OIDs come in an array (ref) - go through each
        # example:
        #    $refaOIDs = [
        #              '.1.3.6.1.2.1.2.2.1.11.1',
        #              '.1.3.6.1.2.1.2.2.1.12.1'
        #            ];    
        for $OIDLine (@$refaOIDs) {
            
            my  $CacheTimer=0;      

            $SnmpValue="";  # clear value
                        
            # OID could be .1.3.6.1.2.1.2.2.1.11.1,200
            # <OID>,<CacheTimer> for this OID only
            my ($OID,$OIDCacheTimer) = split ',',$OIDLine,2;

            # remove non digits
            $OIDCacheTimer=~s/\D//g;
            
            if ("X$OIDCacheTimer" eq "X") { # is empty?
                $CacheTimer = $GlobalCacheTimer;
            } else {
                $CacheTimer = $OIDCacheTimer;
            }            
            
            if ($CacheTimer > 0) {
                if (-r "$CacheDir/$OID") {                
                    my @FileProperties=stat("$CacheDir/$OID");

                    # $FileProperties[9] = LastModifyTime of file
                    # only read the cache file if it is not too old                
                    if (time - $CacheTimer < $FileProperties[9]) {
                        open (IN,"<$CacheDir/$OID");
                            $SnmpValue = <IN>;                        
                        close (IN); 
                    } 
                }
            }        
            # snmp value not from cache - read it from the net
            if ("X$SnmpValue" eq "X") {
                # get the snmp value - we do not check errors
                # here because of negative caching 
                my $refhValue = $refoSession->get_request(-varbindlist => ["$OID"]);
                $SnmpValue  =   $refhValue->{"$OID"};
                
                # remove non ascii chars incl. \r and \n
                $SnmpValue  =~  s/[\000-\037]|[\177-\377]//g; 
                    
                # replace ; with , - just to be sure
                $SnmpValue  =~  s/;/,/g;           
                
                if ($CacheTimer > 0) {

                    umask "$UMASK";
                    open (OUT,">$CacheDir/$OID");
                        print OUT $SnmpValue;         
                    close (OUT);
                }            
                $Debug and print "SnmpGetV1 data from net (cache=$CacheTimer sec.) OID=$OID ";
            } else {
                $Debug and print "SnmpGetV1 data from file (cache=$CacheTimer sec.) $CacheDir/$OID ";
            }
            
            $Debug and print "$SnmpValue\n";
            
            # fill hash with data
            $refhSnmpValues->{$OID}="$SnmpValue";
        } # for my $OIDLine ...
   
        # if we have only 1 OID -> return the Value instead the hash
        if ($#$refaOIDs == 0) {
            return $SnmpValue;
        }
    } 
    # return the complete hash with OIDs as keys or
    # undef if the SNMP session fails
    return $refhSnmpValues;
} # sub

# ------------------------------------------------------------------------
# dir creator extracted from our FileOperations library
# ------------------------------------------------------------------------
sub MyMkdir {
	
    my  $Directory = shift;
        
    $Directory  =~  s/\s//g;    # remove invisible characters
    $Directory  =~  s/\\/\//g;  # replace \ with /
    $Directory  =~  s/\/+/\//g; # replace duplicate or more slashes with one /

    # split directory into pieces
    my @Dirs    =   split /\//,$Directory;
    
    # growing directory structure
    my $Snake;
    
    # walk through each directory and create it
    for my $Dir (@Dirs) {
        $Snake .= $Dir.'/';        
        if (not -d "$Snake") {
        		umask "$UMASK";
            my $Success = mkdir $Snake;
            if ("$Success" ne "1") {
                undef $Snake;
                last;
            }
        }
    }

    # remove last / and return the directory back to the caller
    if ("$Snake" =~ /\/$/) {
        chop ($Snake);
    }
    return $Snake;
}

# ------------------------------------------------------------------------
# ExecuteCommand Routine. Enhanced with our cache algorith...
# ------------------------------------------------------------------------
sub ExecuteCommand {
    my $refhStruct=shift;

    my $Command = $refhStruct->{Command};
        
    my $refaLines=[];   # Pointer to Array of strings (output)
    
    my $CacheFile;      # Filename storing cached data
    my $ExitCode;       # exit code of the unix command

    my $Now=time();     # current time in seconds since epoch
    
    my $CacheDir="$gCacheDir/ExecuteCommand/"; # cache dir
    
    # Create Cachedir if not existend
    not -d $CacheDir and MyMkdir($CacheDir);
   
    # If caching for this command is enabled
    if ($refhStruct->{CacheTimer} > 0) {

        $CacheFile = $CacheDir . normalize ("$Command");
        
        if (-r "$CacheFile") {
            my @FileProperties=stat($CacheFile);
            
            # $FileProperties[9] = LastModifyTime of file
            # only read the cache file if it is not too old
            if ($Now-$refhStruct->{CacheTimer} < $FileProperties[9]) {
                open (IN,"<$CacheFile");
                    @$refaLines=<IN>;
                close (IN);
                # leave this subroutine with cached data found
                $refhStruct->{Debug} and
                    print "ExecuteCommand (1) got data from cache $CacheFile\n";
                return ($refaLines,0); 
            }
        }
    }
                        
    # execute the unix command
    open(UNIX,"$Command |") or last;
        while (<UNIX>) {
            push @$refaLines,$_;
        }
    close(UNIX);
    $ExitCode=$? >> 8; # calculate the exit code             

    $refhStruct->{Debug} and
        print "ExecuteCommand (2) executed \"$Command\" and got ExitCode \"$ExitCode\"\n";

                
    # write a cache file if the cache timer > 0
    if ($refhStruct->{CacheTimer} > 0) {
        $refhStruct->{Debug} and
            print "ExecuteCommand (3) Write cache file CacheTimer=$refhStruct->{CacheTimer}\n";        
        umask "$UMASK"; # change to rw-rw-rw maybe changed later because of security
        open (OUT,">$CacheFile") or return ($refaLines,$ExitCode);
            print OUT @$refaLines;
        close (OUT);
    }
    return ($refaLines,$ExitCode);
}

# ------------------------------------------------------------------------------
# Csv2Html
# This function generates a html table
#
# Function call:
# $gHtml   = Csv2Html ("Name;Surname",$refaLines);
# ------------------------------------------------------------------------------
sub Csv2Html {
    my $Header     = shift;       # Header contains the HTML table header as scalar
    my $refaLines  = shift;       # Reference to array of table lines

    my $refaProperties;           # List of properties from each line
    my $HTML;                     # HTML Content back to the caller
    my $HTMLTable;                # HTML Table code only
    my $FS = ';';

    if ($#$refaLines >= 0) {

        # Build HTML format and table header
        $HTML .= '<a name=top></a>'."\n";                
        $HTML .= '<br>';
        $HTML .='<span style="font-size:8pt" style="font-family:monospace">'."\n";
        $HTML .='<table border style="font-size:8pt;WORD-BREAK:NORMAL;" bgcolor=#D2D2D2>'."\n";

        # Build html table title header
        #
        # - $Header looks like this: 
        # index;Description;Alias;AdminStatus;OperStatus;Speed;IP
        #
        # - It will be transformed to:
        # <th>index</th><th>Description</th><th>Alias</th> ...
        $HTML .= "<th>$_</th>" for (split /$FS/,$Header);

        foreach my $Line ( @$refaLines ) {
            # start table line ---------------------------------------------
            $HTMLTable .= "<tr>";

            foreach my $Cell ( @$Line ) {

                my $Value;
                my $SpecialCellFormat;
                my $SpecialTextFormatHead;
                my $SpecialTextFormatFoot;

                # if background is defined ---------------------------------
                if ( defined $Cell->{Background} ) {
                    $SpecialCellFormat .= 'bgcolor="' . $Cell->{Background} . '"';
                }

                # if a special font is indicated ---------------------------
                if ( defined $Cell->{Font} ) {
                    $SpecialTextFormatHead .= $Cell->{Font};
                    $SpecialTextFormatFoot .= '</font>';
                }

                # if we got a value write into cell ------------------------
                if ( defined $Cell->{Value} and  $Cell->{Value} ne " ") {
                    $Value = $Cell->{Value};
                } else {
                # otherwise create a empty cell ----------------------------
                    $Value = "&nbsp;";
                }

                # if a link is indicated -----------------------------------
                if ( defined $Cell->{Link} ) {
                    $Value = '<a href="' . $Cell->{Link} . '">' . $Value . '</a>';
                }

                # finally build the table line;
                $HTMLTable .= '<td ' . $SpecialCellFormat . '>' . 
                    $SpecialTextFormatHead . $Value . 
                    $SpecialTextFormatFoot. '</td>' . "\n";
            }
            # end table line -----------------------------------------------
            $HTMLTable .= "</tr>";
        }
         $HTMLTable .= "</table>";
         $HTML .= "<tr align=right><td>$HTMLTable</td></tr><br>";
    } else {
        $HTML.='<a href=JavaScript:history.back();>No data to display</a>'."\n";    
    }

    return $HTML;
}

# ------------------------------------------------------------------------------
# AppendLinkToText
# Apend html table link to text
# ------------------------------------------------------------------------------
sub AppendLinkToText {

    my $refhStruct = shift;
    my $ResultText;
    
    $ResultText = '<a href="' . "$refhStruct->{HtmlUrl}/$refhStruct->{File}" . '">' . $refhStruct->{Text} . '</a>';
    
    return $ResultText;
}

# ------------------------------------------------------------------------------
# ExitPlugin
# Print correct output text and exit this plugin now
# ------------------------------------------------------------------------------
sub ExitPlugin {
    
    my $refhStruct = shift;

    # --------------------------------------------------------------------
    # when we have UNKNOWN the exit code and the text can
    # be overwritten from the command line with the options
    # -UnknownExit and -UnknownText
    #
    # Example for CRITICAL (code=2):
    #
    # ...itd_check_xxxxx.pl -UnknownExit 2 -UnknownText "Error getting data"
    #
    if ($refhStruct->{ExitCode} == $STATE_UNKNOWN) {
        $refhStruct->{ExitCode} = $refhStruct->{UnknownExit};
        $refhStruct->{Text}     = $refhStruct->{UnknownText};
    }    
    
    print $refhStruct->{Text};
    print "\n";
    exit $refhStruct->{ExitCode};
}

# ------------------------------------------------------------------------------
# Append Buttons
# ------------------------------------------------------------------------------
sub HtmlLinks {
    
	my $refhStruct=shift;
	my $Text=shift;	
	
	my $InterfaceStateFile = "$refhStruct->{ResetTable}";
	
	my $HTML;

    # nice font
    $HTML.='<span style="font-size:8pt" style="font-family:monospace">'."\n";
	
	# back button	
	if ($refhStruct->{Back}) {
	    $HTML.='<a href="JavaScript:history.back();">[ back ]</a>'."\n";
	}
	
	# reset button to remove file
	if ($InterfaceStateFile) {
      if (-f "$InterfaceStateFile") {
		      $HTML.="<a href=\"$gUrlToTableReset/InterfaceTableReset.cgi?Command=rm&What=$InterfaceStateFile\">[ reset table ]</a>";
			}
	}

  $HTML.='</span>'."\n";
	
	return $HTML;
}
