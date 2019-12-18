#!/usr/bin/perl -w
#
# check_bgp_counters - nagios plugin 
#
# by Frank Bulk <frnkblk@iname.com> 
#   inspiration by Douglas E. Warner <silfreed@silfreed.net>
#   inspiration by Christoph Kron <ck@zet.net> - check_ifstatus.pl
#
# This plugin improves upon the basic check_bgp and does everything via SNMP.
# For those that have no SNMP trap manager, this poll-based approach will still catch short BGP
# outages because certain counters will increment or change on BGP session failure and re-establishment.
# Checks against at least six counters are made, plus changes in prefixes.
# There's no need to know or enumerate the IP addresses of the BGP router's peers - the
# code handles that automatically.  There's also no need to accommodate for modified
# BGP update message intervals, as the code takes that into account when calculating how many changes
# should have occurred since the last check.
#
# Targeted to Cisco platform; comment out Cisco OIDs if you want a subset of the functionality
#
# Here is a suggested command definition:
#	# 'check_bgp_counters command definition
#	define command{
#	        command_name    check_bgp_counters
#	        command_line    perl $USER1$/check_bgp_counters -H $HOSTADDRESS$ -C $ARG1$ -f /tmp/ -v $ARG1$
#	}
#
# Here is a suggested service configuration:
#	define service{
#	        use                     generic-service
#	        host_name               router
#	        service_description     BGP
#	        contact_groups          router-admins
#	        notification_interval   15
#	        normal_check_interval   2
#	        max_check_attempts      1
#	        notification_options    w,c,r
#	        check_command           check_bgp_counters!community_string!cisco
#	}
#
# Several notes:
#	- increasing the max_check_attempts could result in missing counter changes,
#	  so it's recommended to leave it at '1'
#	- the host definition should use an IP address rather than a host name or FQDN
#	- make sure the directory and filename is writable by the NAGIOS process.
#	  If you first test using 'root' or another user, the cached files may not be
#	  overwritable
#	- you can change the error level of a counter by modifying the definition in 
#	  the code below.  In some environments prefixes may change all the time and
#	  so those OIDs could be commented out altogether.  Another option is to change
#	  the notification option to just 'c,r'
#	- if you silence notifications due to an issue with one BGP session, you won't be
#	  notified if another BGP session on that host goes awry.  This is potentially a 
#	  feature request: to narrow checking to per BGP session basis, which would naturally
#	  require setting up a separate service check for each BGP session.
#
# To test from the command-line, try something like this:
#	./check_bgp_counters -C community_string -H hostip -f /tmp
#
# Release notes
# v1.1
# - fixed last BGP peer state to print text rather than numeric value
# v1.2
# - added host names to each of the IPs listed for BGP neighbors
# v1.3
# - now ignore strings found in OIDs, useful to ignore certain BGP neighbors
# v1.4
# - AS numbers are now included
# - does not alarm on sessions that are administratively shut down
# v1.5
# - allow min/max sent/received limits to be added
# v1.6
# - add an option to check prefix counts (received versus installed on Brocade)
#
# Please report all bugs and comments to author, frnkblk@iname.com
#

use strict;

use Net::SNMP;
use Getopt::Long;
use File::Basename;
&Getopt::Long::config('auto_abbrev');
use IO::Socket;

my $version = "1.6";
my $status;
my $needhelp = '';
my $vendor;
my $TIMEOUT = 30;

my %ERRORS = (
	'OK'       => '0',
	'WARNING'  => '1',
	'CRITICAL' => '2',
	'UNKNOWN'  => '3',
);

# default return value is UNKNOWN
my $state = "UNKNOWN";

# time this script was run
my $runtime = time();

# responses from script
my $answer = "";
my $oidmsg = "";
my $error;
my $oidwarn = 0;
my $oidcrit = 0;

# external variable declarations
my $hostip;
my $community = "public";
my $port = 161;
my @ignore_string;
my @ignore_counters_string;
my $sessions_only = 0;
my $prefix_compare = 0;
my $counterFilePath;
my $counterFile;
my $minprefrecv = 0;
my $maxprefrecv = 2000000;
my $minprefsent;
my $maxprefsent;
my $warntmp;
my @warning;
my $crittmp;
my @critical;
my %snmpOID;
my %snmpOIDtype;
my %snmpOIDerror;
my %bgp_peer_admin_state;
my %bgp_peer_remote_as;

my %bgpPeerState;
$bgpPeerState{0} = "none";
$bgpPeerState{1} = "idle";
$bgpPeerState{2} = "connect";
$bgpPeerState{3} = "active";
$bgpPeerState{4} = "opensent";
$bgpPeerState{5} = "openconfirm";
$bgpPeerState{6} = "established";

# snmp related variables
my $session;
my $response;
my $snmpkey;
my $snmpoid;
my @oid_array;
my $oid;
my $int_ip;
my $key;
our %snmpIndexes;
our %hostnameIndexes;
my $snmpSysUpTime = ".1.3.6.1.2.1.1.3.0";
my $snmpHostUptime;
my %brocade_interface;

# file related variables
my $fileRuntime;
my $fileHostUptime;
my %fileIndexes;

## main program

# Just in case of problems, let's not hang NAGIOS
$SIG{'ALRM'} = sub {
	print ("ERROR: No snmp response from $hostip (alarm)\n");
	exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

# we must have -some- arguments
if (scalar(@ARGV) == 0) {
	usage();
} # end if no options

Getopt::Long::Configure("no_ignore_case");
$status = GetOptions(
	"h|help"		=> \$needhelp,
	"C|c|snmpcommunity=s"	=> \$community,
        "i|ignore-string=s"	=> \@ignore_string,
        "ic|ignore-counters-string=s"	=> \@ignore_counters_string,
        "so|sessions-only"	=> \$sessions_only,
	"p|port=i"		=> \$port,
	"v|vendor=s"		=> \$vendor,
	"f|filepath=s"		=> \$counterFilePath,
	"H|hostip=s"		=> \$hostip,
	"minprefrecv=i"		=> \$minprefrecv,
	"maxprefrecv=i"		=> \$maxprefrecv,
	"minprefsent|minprefsend|minprefadv=i"		=> \$minprefsent,
	"maxprefsent|maxprefsend|maxprefadv=i"		=> \$maxprefsent,
	"pc|prefix-compare"	=> \$prefix_compare,
);

#print "DEBUG: [$sessions_only]\n";

if ($status == 0 || $needhelp) {
	usage();
} # end if getting options fails or the user wants help

if (($minprefsent || $maxprefsent) && ($vendor !~ /cisco/)) {
	print "Check for max/min sent prefix count only works on Cisco vendor types (because of MIB support)\n";
	exit $ERRORS{"UNKNOWN"};
}
else {
	$minprefsent = 0;
	$maxprefsent = 2000000;
}

if ($minprefrecv >= $maxprefrecv) {
	print "The minimum received prefix count must be less than or equal to the maximum prefix count\n";
	exit $ERRORS{"UNKNOWN"};
}

if ($minprefsent >= $maxprefsent) {
	print "The minimum sent prefix count must be less than or equal to the maximum prefix count\n";
	exit $ERRORS{"UNKNOWN"};
}

if ($prefix_compare && (!defined($vendor) || ($vendor !~ /cisco|brocade/))) {
	print "Prefix comparisons only work Brocade and Cisco vendor types (because of MIB support)\n";
	exit $ERRORS{"UNKNOWN"};
}

if (!defined($counterFilePath)) {
	$state = "UNKNOWN";
	$answer = "Filepath must be specified";
	print "$state: $answer\n";
	exit $ERRORS{$state};
} # end check for filepath
if (!defined($hostip)) {
	$state = "UNKNOWN";
	$answer = "Host IP must be specified";
	print "$state: $answer\n";
	exit $ERRORS{$state};
} # end check for host IP
if (!defined($vendor)) {
	$vendor = "generic";
}

%bgp_peer_admin_state = snmp_get_table($hostip, $port, "1", $community, "1.3.6.1.2.1.15.3.1.3");
%bgp_peer_remote_as = snmp_get_table($hostip, $port, "1", $community, "1.3.6.1.2.1.15.3.1.9");

# bgpPeerState
$snmpOID{"1.3.6.1.2.1.15.3.1.2"} = "the BGP peer state";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.2"} = 0;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.2"} = "critical";
# bgpPeerInUpdates
$snmpOID{"1.3.6.1.2.1.15.3.1.10"} = "the number of BGP UPDATE messages received";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.10"} = 3;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.10"} = "warning";
# bgpPeerOutUpdates
$snmpOID{"1.3.6.1.2.1.15.3.1.11"} = "the number of BGP UPDATE messages sent";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.11"} = 3;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.11"} = "warning";
# bgpPeerInTotalMessages
$snmpOID{"1.3.6.1.2.1.15.3.1.12"} = "the number of messages received from the remote peer";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.12"} = 1;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.12"} = "warning";
# bgpPeerOutTotalMessages
$snmpOID{"1.3.6.1.2.1.15.3.1.13"} = "the number of messages transmitted to the remote peer";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.13"} = 1;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.13"} = "warning";
# bgpPeerFsmEstablishedTransitions
$snmpOID{"1.3.6.1.2.1.15.3.1.15"} = "The total number of times the BGP FSM transitioned into the established state";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.15"} = 3;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.15"} = "critical";
# bgpPeerFsmEstablishedTime
$snmpOID{"1.3.6.1.2.1.15.3.1.16"} = "the elapsed time the remote peer has been in the Established state or how long since this peer was last in the Established state";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.16"} = 5;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.16"} = "critical";
# bgpPeerKeepAlive
$snmpOID{"1.3.6.1.2.1.15.3.1.19"} = "the KeepAlive timer established with the remote peer";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.19"} = 3;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.19"} = "warning";
# bgpPeerInUpdateElapsedTime
$snmpOID{"1.3.6.1.2.1.15.3.1.24"} = "the elapsed time since the last BGP UPDATE message was received from the remote peer";
$snmpOIDtype{"1.3.6.1.2.1.15.3.1.24"} = 4;
$snmpOIDerror{"1.3.6.1.2.1.15.3.1.24"} = "warning";
if ($vendor eq "cisco") {
	# cbgpPeerLastErrorTxt
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.1.1.7"} = "the last error message";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.1.1.7"} = 3;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.1.1.7"} = "critical";
	# cbgpPeerPrevState
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.1.1.8"} = "the peer connection's previous state";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.1.1.8"} = 3;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.1.1.8"} = "critical";
	# cbgpPeerAcceptedPrefixes
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.1"} = "the number of accepted route prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.1"} = 2;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.1"} = "warning";
	# cbgpPeerDeniedPrefixes
#	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.2"} = "the number of denied prefixes";
#	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.2"} = 2;
#	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.2"} = "warning";
	# cbgpPeerAdvertisedPrefixes
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.6"} = "the number of advertised prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.6"} = 2;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.6"} = "warning";
	# cbgpPeerSuppressedPrefixes
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.7"} = "the number of suppressed prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.7"} = 2;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.7"} = "warning";
	# cbgpPeerWithdrawnPrefixes
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.8"} = "the number of withdrawn prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.8"} = 2;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.8"} = "warning";
}
elsif ($vendor eq "brocade") {
	# snBgp4NeighborSummaryIp
	$snmpOID{"1.3.6.1.4.1.1991.1.2.11.17.1.1.2"} = "the neighbor IP";
	$snmpOIDtype{"1.3.6.1.4.1.1991.1.2.11.17.1.1.2"} = -1;
	$snmpOIDerror{"1.3.6.1.4.1.1991.1.2.11.17.1.1.2"} = "warning";
	# snBgp4NeighborSummaryRouteReceived
	$snmpOID{"1.3.6.1.4.1.1991.1.2.11.17.1.1.5"} = "the number of received route prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.1991.1.2.11.17.1.1.5"} = 6;
	$snmpOIDerror{"1.3.6.1.4.1.1991.1.2.11.17.1.1.5"} = "warning";
	# snBgp4NeighborSummaryRouteInstalled
	$snmpOID{"1.3.6.1.4.1.1991.1.2.11.17.1.1.6"} = "the number of installed route prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.1991.1.2.11.17.1.1.6"} = 6;
	$snmpOIDerror{"1.3.6.1.4.1.1991.1.2.11.17.1.1.6"} = "warning";
}

# setup counterFile now that we have host IP and oid
$counterFile = "$counterFilePath/$hostip.check_bgp_counters.nagioscache";

readolddata();
getSysUpTime();

foreach $key (keys %snmpOID) {
	getCounters($key);
}
checkIgnores();

if ($vendor eq "brocade") {
	foreach $key (grep(/1.3.6.1.4.1.1991.1.2.11.17.1.1.2/, keys %snmpIndexes)) {
		@oid_array = split (/\./, $key);
		my $index = pop(@oid_array);
		$oid = "1.3.6.1.4.1.1991.1.2.11.17.1.1.2." . $index;
		$int_ip = $snmpIndexes{$oid};
#print "DEBUG: int_ip [$int_ip]\n";
#print "DEBUG: key [$index]\n";
		$brocade_interface{$int_ip} = $index;
	}
}
elsif ($vendor eq "cisco") {
	# self-created OID
	$snmpOID{"1.3.6.1.4.1.9.9.187.1.2.4.1.99"} = "the number of received route prefixes";
	$snmpOIDtype{"1.3.6.1.4.1.9.9.187.1.2.4.1.99"} = 2;
	$snmpOIDerror{"1.3.6.1.4.1.9.9.187.1.2.4.1.99"} = "warning";
	# need to add up the accepted and denied prefixes to get a received prefixes count; store it in a made up OID
	foreach $key (grep(/1.3.6.1.4.1.9.9.187.1.2.4.1.1|1.3.6.1.4.1.9.9.187.1.2.4.1.2/, keys %snmpIndexes)) {
#print "DEBUG: key [$key] [$snmpIndexes{$key}]\n";
		@oid_array = split (/\./, $key);
		my $index = join(".", @oid_array[$#oid_array-5 .. $#oid_array]);
		$oid = "1.3.6.1.4.1.9.9.187.1.2.4.1.99." . $index;
#print "DEBUG: key [$oid] [$snmpIndexes{$key}]\n";
		if (!defined($snmpIndexes{$oid})) {
			$snmpIndexes{$oid} = $snmpIndexes{$key};
		}
		else {
			$snmpIndexes{$oid} += $snmpIndexes{$key};
		}
	}
}

outputdata();

# check to see if we pulled data from the cache file or not
if (!defined($fileRuntime)) {
	$state = "OK";
	$answer = "never cached - caching";
	print "$state: $answer\n";
	exit $ERRORS{$state};
} # end if cache file didn't exist

# check host's uptime to see if it goes backward, but only alarm if it's not the Brocade roll-over issue
if (($fileHostUptime > $snmpHostUptime) && (($fileHostUptime <= 4293500) || ($fileHostUptime >= 4296500))) {
	$state = "WARNING";
	$answer = "uptime goes backward - recaching data";
	print "$state: $answer\n";
	exit $ERRORS{$state};
} # end if host uptime goes backward

# check if number of indexes in file is different than our new data
if (scalar(keys(%fileIndexes)) != scalar(keys(%snmpIndexes))) {
	$state = "WARNING";
	$answer = "number of indexes changed - recaching data";
	print "$state: $answer\n";
	exit $ERRORS{$state};
} # end number of indexes different

# foreach snmp key (sorted numerically), figure stuff out
foreach $key (sort numerically (keys %snmpIndexes)) {
	my $timeperiod = ($runtime-$fileRuntime);
	# now need to strip OID down until it matches one that is defined
	my $shortkey = $key;
	while (!defined($snmpOIDtype{$shortkey}) && $shortkey) {
		chop $shortkey;
	}

	# depending on the OID, we handle each check and message differently

	# the OID that the value always needs to be in a good state (i.e. "established") and has an OID that ends with an IP address
	if ($snmpOIDtype{$shortkey} eq 0) {
		@oid_array = split (/\./, $key);
		$int_ip = join(".", @oid_array[$#oid_array-3 .. $#oid_array]);
		$oid = join(".", @oid_array[0 .. $#oid_array-4]);
		if ($snmpIndexes{$key} ne "established") {
			my $oid2 = "1.3.6.1.2.1.15.3.1.3." . $int_ip;
			my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
			my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
			my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
			# 1 is 'stop' and '2' is start
			if ($bgp_peer_admin_state{$oid2} ne 1) {
				if ($snmpOIDerror{$oid} eq "warning") {
					$oidwarn++;
				}
				elsif ($snmpOIDerror{$oid} eq "critical") {
					$oidcrit++;
				}
			}
			if ($hostname) {
				$oidmsg .= "Host $hostname [$hostip] ";
			}
			else {
				$oidmsg .= "Host $hostip ";
			}
			if ($int_hostname) {
				$oidmsg .= "with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} is in state '$snmpIndexes{$key}'";
			}
			else {
				$oidmsg .= "with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} is in state '$snmpIndexes{$key}'";
			}
			if ($bgp_peer_admin_state{$oid2} eq 1) {
				$oidmsg .= " [administratively down]\n";
			}
			else {
				$oidmsg .= "\n";
			}
			
		}

	}

	# those OIDs that end with IP address and who have counters that go up regularly
	elsif (($snmpOIDtype{$shortkey} eq 1) && (!$sessions_only)) {
		@oid_array = split (/\./, $key);
		$int_ip = join(".", @oid_array[$#oid_array-3 .. $#oid_array]);
		$oid = join(".", @oid_array[0 .. $#oid_array-4]);
		my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
		my $bgpPeerKeepAlive = $snmpIndexes{"1.3.6.1.2.1.15.3.1.19." . $int_ip};
#print "DEBUG: timeperiod [$timeperiod]\n";
#print "DEBUG: bgpPeerKeepAlive [$bgpPeerKeepAlive]\n";
#print "DEBUG: snmpIndexes{key} [$snmpIndexes{$key}]\n";
#print "DEBUG: other [" . ($fileIndexes{$key} + ($timeperiod / $bgpPeerKeepAlive) + 2) . "]\n";
		if ($bgpPeerKeepAlive) {
			if ($snmpIndexes{$key} > ($fileIndexes{$key} + ($timeperiod / $bgpPeerKeepAlive) + 3)) {
				my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
				my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
				if (!arrayInScalar($int_ip, @ignore_counters_string) && !arrayInScalar($int_hostname, @ignore_counters_string)) {
					if ($snmpOIDerror{$oid} eq "warning") {
						$oidwarn++;
					}
					elsif ($snmpOIDerror{$oid} eq "critical") {
						$oidcrit++;
					}
				}	
	
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
			}
		}

	}
	# those OIDs that end with IP address AND a two-place index
	elsif ($snmpOIDtype{$shortkey} eq 2) {
#print "DEBUG: key $key snmpIndexes{key} $snmpIndexes{$key} minprefsent $minprefsent maxprefsent $maxprefsent\n";
		if (
			($snmpIndexes{$key} ne $fileIndexes{$key}) ||
			((($snmpIndexes{$key} > $maxprefrecv) || ($snmpIndexes{$key} < $minprefrecv)) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.99/)) || 
			((($snmpIndexes{$key} > $maxprefsent) || ($snmpIndexes{$key} < $minprefsent)) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.6/)) ||
			($prefix_compare && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.2/) && $snmpIndexes{$key})
		) {
			@oid_array = split (/\./, $key);
			$int_ip = join(".", @oid_array[$#oid_array-5 .. $#oid_array-2]);
			my $index = join(".", @oid_array[$#oid_array-1 .. $#oid_array]);
			$oid = join(".", @oid_array[0 .. $#oid_array-6]);
			my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
			my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
			my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
			if (!arrayInScalar($int_ip, @ignore_counters_string) && !arrayInScalar($int_hostname, @ignore_counters_string)) {
				if ($snmpOIDerror{$oid} eq "warning") {
					$oidwarn++;
				}
				elsif ($snmpOIDerror{$oid} eq "critical") {
					$oidcrit++;
				}
			}

			if ($snmpIndexes{$key} ne $fileIndexes{$key}) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
			}

#print "DEBUG: key $key snmpIndexes{key} $snmpIndexes{$key} minprefsent $minprefsent maxprefsent $maxprefsent\n";
			# Cisco received prefixes
			if (($snmpIndexes{$key} > $maxprefrecv) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.99/)){
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' received prefixes is greater than the specified maximum of '$maxprefrecv'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' received prefixes is greater than the specified maximum of '$maxprefrecv'\n";
				}
			}
			elsif (($snmpIndexes{$key} < $minprefrecv) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.99/)) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' received prefixes is less than the specified minimum of '$minprefrecv'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' learned prefixes is less than the specified minimum of '$minprefrecv'\n";
				}
			}
			# Cisco advertised/sent prefixes
			elsif (($snmpIndexes{$key} > $maxprefsent) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.6/)) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' advertised prefixes is greater than the specified maximum of '$maxprefsent'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' learned prefixes is greater than the specified maximum of '$maxprefsent'\n";
				}
			}
			elsif (($snmpIndexes{$key} < $minprefsent) && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.6/)) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' advertised prefixes is less than the specified minimum of '$minprefsent'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' learned prefixes is less than the specified minimum of '$minprefsent'\n";
				}
			}

			# stopped checking the below because it appears to be the number of accumulated denies
			# check if there are any denied prefixes
#			if ($prefix_compare && ($key =~ /1.3.6.1.4.1.9.9.187.1.2.4.1.2/) && $snmpIndexes{$key}) {
#				my $oid4 = "1.3.6.1.4.1.9.9.187.1.2.4.1.1." . $int_ip . "." . $index;
#				$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' prefixes are denied ('$snmpIndexes{$oid4}' have been accepted)\n\tUse 'show ip bgp ipv4 unicast neighbors $int_ip received-routes' to pick out denied routes (need 'soft-reconfiguration inbound' configured) or show ip bgp route-map\n";
#			}
		}
	}
	# those OIDs that end with IP address and do not change regularly
	elsif ($snmpOIDtype{$shortkey} eq 3) {
		if ($snmpIndexes{$key} ne $fileIndexes{$key}) {
			@oid_array = split (/\./, $key);
			$int_ip = join(".", @oid_array[$#oid_array-3 .. $#oid_array]);
			$oid = join(".", @oid_array[0 .. $#oid_array-4]);
			my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
			my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
			my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
			if (!arrayInScalar($int_ip, @ignore_counters_string) && !arrayInScalar($int_hostname, @ignore_counters_string)) {
				if ($snmpOIDerror{$oid} eq "warning") {
					$oidwarn++;
				}
				elsif ($snmpOIDerror{$oid} eq "critical") {
					$oidcrit++;
				}
			}

			if ($int_hostname) {
				$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
			}
			else {
				$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
			}
		}
	}
	# those OIDs that end with IP address and normally count up over time
	elsif (($snmpOIDtype{$shortkey} eq 4) || ($snmpOIDtype{$shortkey} eq 5)) {
		# the second half of this if statement is to deal with a brocade counter rollover issue
		if (($snmpIndexes{$key} < $fileIndexes{$key}) && (($fileIndexes{$key} <= 4293500) || ($fileIndexes{$key} >= 4296500))) {
#print "DEBUG: key: [$key]\n";
#print "DEBUG: snmpIndexes{key}: [$snmpIndexes{$key}]\n";
#print "DEBUG: fileIndexes{key}: [$fileIndexes{$key}]\n";
			@oid_array = split (/\./, $key);
			$int_ip = join(".", @oid_array[$#oid_array-3 .. $#oid_array]);
			$oid = join(".", @oid_array[0 .. $#oid_array-4]);
			my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
			if (($key =~ /1\.3\.6\.1\.2\.1\.15\.3\.1\.16\./) || ($key =~ /1\.3\.6\.1\.2\.1\.15\.3\.1\.24\./)) {
				$fileIndexes{$key} = convertseconds($fileIndexes{$key});
				$snmpIndexes{$key} = convertseconds($snmpIndexes{$key});
			}
			my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
			my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
			if (!arrayInScalar($int_ip, @ignore_counters_string) && !arrayInScalar($int_hostname, @ignore_counters_string) && !($snmpOIDtype{$shortkey} eq 5)) {
				if ($snmpOIDerror{$oid} eq "warning") {
					$oidwarn++;
				}
				elsif ($snmpOIDerror{$oid} eq "critical") {
					$oidcrit++;
				}
			}

			if ($int_hostname) {
				$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
			}
			else {
				$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
			}
		}
	}
	# Brocade private MIB where index number is not IP address, but needs to be discovered
	elsif ($snmpOIDtype{$shortkey} eq 6) {
		@oid_array = split (/\./, $key);
		my $index = pop(@oid_array);
		my $oid4 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.5." . $index;
		my $oid5 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.6." . $index;
		if (
			($snmpIndexes{$key} ne $fileIndexes{$key}) ||
			((($snmpIndexes{$key} > $maxprefrecv) || ($snmpIndexes{$key} < $minprefrecv)) && ($key =~ /1.3.6.1.4.1.1991.1.2.11.17.1.1.5/)) ||
			($prefix_compare && ($key =~/1.3.6.1.4.1.1991.1.2.11.17.1.1.6/) && ($snmpIndexes{$oid4} ne $snmpIndexes{$oid5}))
		) {
			@oid_array = split (/\./, $key);
			my $index = pop(@oid_array);
			$oid = join(".", @oid_array);
			my $oid2;
			$oid2 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.2." . $index;
			$int_ip = $snmpIndexes{$oid2};
			my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
			my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
			my $hostname = trimwhitespace(gethostbyaddr(inet_aton($hostip), AF_INET));
			if (!arrayInScalar($int_ip, @ignore_counters_string) && !arrayInScalar($int_hostname, @ignore_counters_string)) {
				if ($snmpOIDerror{$oid} eq "warning") {
					$oidwarn++;
				}
				elsif ($snmpOIDerror{$oid} eq "critical") {
					$oidcrit++;
				}
			}

			if ($snmpIndexes{$key} ne $fileIndexes{$key}) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpOID{$oid} changed from '$fileIndexes{$key}' to '$snmpIndexes{$key}'\n";
				}
			}
			
			if ($snmpIndexes{$key} > $maxprefrecv) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' learned prefixes is greater than the specified maximum of '$maxprefrecv'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' learned prefixes is greater than the specified maximum of '$maxprefrecv'\n";
				}
			}
			elsif ($snmpIndexes{$key} < $minprefrecv) {
				if ($int_hostname) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: '$snmpIndexes{$key}' learned prefixes is less than the specified minimum of '$minprefrecv'\n";
				}
				else {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$key}' learned prefixes is less than the specified minimum of '$minprefrecv'\n";
				}
			}

			if ($prefix_compare && ($key =~ /1.3.6.1.4.1.1991.1.2.11.17.1.1.6/)) {
				my $oid4 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.5." . $index;
				my $oid5 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.6." . $index;
				if ($snmpIndexes{$oid4} ne $snmpIndexes{$oid5}) {
					$oidmsg .= "Host $hostname [$hostip] with interface to BGP peer $int_ip/AS $bgp_peer_remote_as{$oid3}: '$snmpIndexes{$oid4}' learned but '$snmpIndexes{$oid5}' installed prefixes\n\tUse 'show ip bgp filtered-routes detail' to identify filtered routes'\n";
				}
			}
		}
	}
	else {
#		print "No comparison made for $key!\n";
	}
} # end foreach $key

# figure out what state we're in
if ($oidcrit > 0) {
	$state = "CRITICAL";
} elsif ($oidwarn > 0) {
	$state = "WARNING";
} else {
	$state = "OK";
} # end if we have warnings or not

# setup final message
$answer = "critical $oidcrit, warning $oidwarn\n$oidmsg";
print ("$state: $answer");
foreach $key (sort numerically (keys %snmpIndexes)) {
        if ($key =~ /^1\.3\.6\.1\.2\.1\.15\.3\.1\.2\./) {
		@oid_array = split (/\./, $key);
		$int_ip = join(".", @oid_array[$#oid_array-3 .. $#oid_array]);
		my $int_hostname = gethostbyaddr(inet_aton($int_ip), AF_INET);
		my $oid3 = "1.3.6.1.2.1.15.3.1.9." . $int_ip;
		if ($int_hostname) {
			if ($vendor eq "cisco") {
				my $oid4 = "1.3.6.1.4.1.9.9.187.1.2.4.1.99." . $int_ip . ".1.1";
				my $oid5 = "1.3.6.1.4.1.9.9.187.1.2.4.1.1." . $int_ip . ".1.1";
				my $oid6 = "1.3.6.1.4.1.9.9.187.1.2.4.1.6." . $int_ip . ".1.1";
				print "BGP state of $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpIndexes{$key}; prefixes (received/installed/sent): $snmpIndexes{$oid4}/$snmpIndexes{$oid5}/$snmpIndexes{$oid6}\n";
			}
			elsif ($vendor eq "brocade") {
				my $index = $brocade_interface{$int_ip};
				my $oid4 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.5." . $index;
				my $oid5 = "1.3.6.1.4.1.1991.1.2.11.17.1.1.6." . $index;
				print "BGP state of $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpIndexes{$key}; prefixes (received/installed): $snmpIndexes{$oid4}/$snmpIndexes{$oid5}\n";
			}
			else {
				print "BGP state of $int_hostname [$int_ip/AS $bgp_peer_remote_as{$oid3}]: $snmpIndexes{$key}\n";
			}
		}
		else {
			print "BGP state of $int_ip/AS $bgp_peer_remote_as{$oid3}: $snmpIndexes{$key}\n";
		}

	}
}
exit $ERRORS{$state};


## subroutines ##

# the usage of this program (duh)
sub usage
{
	print <<END;
== check_bgp_counters v$version ==
Perl SNMP Check Counter plugin for Nagios
Frank Bulk <frnkblk\@iname.com>
checks a provided counter and verifies that it was within

Usage:
  check_bgp_counters (-C|--snmpcommunity) <read_community>
                     (-H|--host IP address) <host ip>
                     [-p|--port] <port> 
           [-minprefrecv]--minprefrecv| <number> (minimum received prefixes; Brocade and Cisco)
           [-maxprefrecv]--maxprefrecv| <number> (maximum received prefixes; Brocade and Cisco)
           [-minprefsent]--minprefsent| <number> (minimum sent prefixes; just Cisco)
           [-maxprefsent]--maxprefsent| <number> (maximum sent prefixes; just Cisco)
                     [-i|--ignore-string] <ignore_string> (ignore BGP peer by IP or host name, i.e. 172.16.0.1)
                    [-ic|--ignore-counters-string] <ignore_counter_string> (ignore the counters for one or more BGP peers by IP or host name, i.e. 172.16.0.1,192.168.0.1)
                    [-so|--sessions-only]
                    [-pc|--prefix-compare] (compare received versus installed prefixes and rejected prefixes; Brocade and Cisco)
                     [-v|--vendor] <generic|cisco|brocade>
		     (-f|--filepath) <file path>

END
	exit $ERRORS{"UNKNOWN"};
}


# for sorting things numerically
sub numerically
{
	# some elements in the OID are greater than 255 to need to encode using UNICODE
	(pack'U*',split/\./,$a) cmp (pack'U*',split/\./,$b);
} # end numerically


# read in the old data (if it exists)
sub readolddata
{
	if (-e $counterFile) {
		open(FILE, "$counterFile");
		chomp($fileRuntime = <FILE>);
		chomp($fileHostUptime = <FILE>);
		while (my $line = <FILE>) {
			chomp($line);
			my @splitline = split(/ /, $line, 2);
			$fileIndexes{$splitline[0]} = $splitline[1];
		} # end while rest of file
		close(FILE);
	} # end if file exists
} # end readolddata


# output data for cache
sub outputdata
{
	if ((-w $counterFile) || (-w dirname($counterFile))) {
		open(FILE, ">$counterFile");
		print FILE "$runtime\n";
		print FILE "$snmpHostUptime\n";
		foreach $key (sort numerically (keys %snmpIndexes)) {
			print FILE "$key $snmpIndexes{$key}\n";
		} # end for each value to output
		close(FILE);
	} else {
		$state = "WARNING";
		$answer = "file $counterFile is not writable\n";
		print ("$state: $answer\n");
        exit $ERRORS{$state};
	} # end if file is writable
} # end outputdata


# get sysUpTime from host
sub getSysUpTime
{
	# get the uptime for the host given
	($session, $error) = Net::SNMP->session(
		-hostname  => $hostip,
		-community => $community,
		-port      => $port
	);

	if (!defined($session)) {
		$state = "UNKNOWN";
		$answer = $error;
		print "$state: $answer";
		exit $ERRORS{$state};
	}

	$session->translate(
		[-timeticks => 0x0]
	);

	$response = $session->get_request(
		-varbindlist => [$snmpSysUpTime]
	);

	if (!defined($response)) {
		$answer=$session->error;
		$session->close;
		$state = "WARNING";
		print "$state: $answer,$community,$snmpSysUpTime";
		exit $ERRORS{$state};
	}

	$snmpHostUptime = $response->{$snmpSysUpTime};

	$session->close;
} # end getSysUpTime


# get counters the user wants from host
sub getCounters
{
	my $temp_snmpCounter = shift;

	# get the value(s) for the oid given
	($session, $error) = Net::SNMP->session(
		-hostname  => $hostip,
		-community => $community,
		-port      => $port,
	);

	if (!defined($session)) {
		$state = "UNKNOWN";
		$answer = $error;
		print "$state: $answer";
		exit $ERRORS{$state};
	}

	if ( !defined($response = $session->get_table($temp_snmpCounter))
		&& !defined($response = $session->get_request($temp_snmpCounter))
		)
	{
		if ( !defined($response = $session->get_table($temp_snmpCounter))
			&& !defined($response = $session->get_request($temp_snmpCounter))
			)
		{
			$answer = $session->error;
			$session->close;
			$state = "WARNING";
			print "$state: $answer,$community,$temp_snmpCounter\n";
			exit $ERRORS{$state};
		}
	}

	foreach $snmpkey (keys %{$response}) {
		$key = $snmpkey;
		my @oid_array = split (/\./, $key);
		my $oid = join(".", @oid_array[0 .. $#oid_array-4]);
		if (($oid =~ /^1\.3\.6\.1\.2\.1\.15\.3\.1\.2$/) || ($oid =~ /^1\.3\.6\.1\.4\.1\.9\.9\.187\.1\.2\.1\.1\.8$/)) {
			$response->{$snmpkey} = $bgpPeerState{$response->{$snmpkey}};
		}
		# if the value this is isn't in @ignore_string, okay
		$snmpIndexes{$key} = $response->{$snmpkey};
	}

	$session->close;
} # end getCounters


# check to see if we're supposed to be ignoring a key. if so, kill it
sub checkIgnores
{
	foreach my $key (keys(%snmpIndexes)) {
		if (arrayInScalar($key, @ignore_string)) {
			delete($snmpIndexes{$key});
		} # end if ignore, nuke key
	} # end foreach key
} # end checkIgnores

# check to see if variables in @array match $scalar
sub arrayInScalar
{
	my $temp_key = shift;
	my @temp_ignore_string = @_;

	foreach (@temp_ignore_string) {
#		if ($temp_key =~ /$_\.\d+$/) {
		if (($_ ne "") && ($temp_key =~ /$_$/)) {
			return 1; #true
		}
	}	

	return 0; #false
} # end arrayInScalar

sub convertseconds
{
	my $result = shift;

	my $days = 0;
	my $hours = 0;
	my $minutes = 0;
	my $seconds = 0;

        if (($result / (60*60*24)) >= 1) {
                $days = int($result / (60*60*24));
                $result -= ($days * 60 * 60 * 24);
        }
        if (($result / (60*60)) >= 1) {
                $hours = int($result / (60*60));
                $result -= ($hours * 60 * 60);
        }
        if (($result / 60) >= 1) {
                $minutes = int($result / 60);
                $result -= ($minutes * 60);
        }
        $seconds = $result;

        if ($days) {
                return "$days days, $hours hours, $minutes minutes, $seconds seconds";
        }
        elsif ($hours) {
                return "$hours hours, $minutes minutes, $seconds seconds";
        }
        elsif ($minutes) {
                return "$minutes minutes, $seconds seconds";
        }
        else {
                return "$seconds seconds";
        }
}

sub trimwhitespace {
        my $string = shift;

        if ($string) {
                $string =~ s/^\s+//;
                $string =~ s/\s+$//;
        }
        else {
                $string = '';
        }

        return $string;
}

sub snmp_get_table {
        my $ip = shift;
        my $port = shift;
        my $version = shift;
        my $community = shift;
        my $snmp_oid = shift;
#print "DEBUG: snmp_oid [$snmp_oid]\n";

        my ($session, $error) = Net::SNMP->session(
                -hostname => $ip,
                -community => $community,
                -version => $version,
                -timeout => 10,
                -port => $port,
        );

        my $snmp_result = $session->get_table(
                -baseoid => $snmp_oid
        );

        if (!defined($snmp_result)) {
#               print "ERROR: $session->error.\n";
                $session->close;
                return;
#               exit 1;
        }

        $session->close;

        return %{$snmp_result};
}


