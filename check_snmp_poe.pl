#!/usr/bin/perl -w

use experimental 'smartmatch';

# RFC3621 PoE MIB
# snmpwalk -v 2c -c public <hostname> mib-2.105

#
# check_poe - nagios plugin 
#
# by Frank Bulk <frnkblk@iname.com> 
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
# This plugin checks the health status of PoE switches via SNMP.  To minimize
# network and node impact, this script checks the overall health and only if
# there is an error does it query more tables.
#
# Here is a suggested command definition:
#	# 'check_poe' command definition
#	define command {
#	        command_name check_poe
#	        command_line $USER1$/check_poe -H $HOSTADDRESS$ -C $ARG1$
#	}
#
# Here is a suggested service configuration:
#	define service{
#	        use                     generic-service
#	        host_name               switch
#	        service_description     PoE
#	        contact_groups          switch-admins
#	        notification_interval   15
#	        check_command           check_poe!public
#	}
#

use strict;

use Net::SNMP;
use Getopt::Long;
use File::Basename;
&Getopt::Long::config('auto_abbrev');
use IO::Socket;

my $version = "1.0";
my $status;
my $needhelp = '';
my $TIMEOUT = 30;

my %ERRORS = (
	'OK'       => '0',
	'WARNING'  => '1',
	'CRITICAL' => '2',
	'UNKNOWN'  => '3',
);

# default return value is UNKNOWN
my $state = "UNKNOWN";

# responses from script
my $answer = "";
my $errmsg = "";
my $statusmsg = "";
my $output = "";

# external variable declarations
my $hostname;
my $community = "public";
my $port = 161;
my $opt_w = 85;
my $opt_c = 95;
my $critical = 0;
my $warning = 0;
my %alarmstate;
my $temp_string;
my $temp_calc;
my $MainPseOperStatus;
my $MainPseUsageThreshold;
my $MainPsePower;
my $MainPseConsumptionPower;
my %bla;
my %PsePortDetectionStatus;
my $slot;
my $interface_num;
my @oid_array;
my $deliveringPower;
my $designatedPower;
my %PoEClass =( 
	'0'=> 0,
	'1'=> 3.84,
	'2'=> 6.49,
	'3'=> 12.95,
	'4'=> 25.5
);
my %cpeExtPsePortAdditionalStatus = (
	'0' => 'is being denied power due to insufficient power resources',
	'1' => 'is being denied power because the PD is trying to consume more power than it has been configured to consume',
	'2' => 'is trying to consume more power than it has been configured to consume, but is not being denied power'
);

# snmp related variables
my $snmpkey;
my $snmpoid;
my $key;

## main program

# Just in case of problems, let's not hang 
$SIG{'ALRM'} = sub {
	print ("ERROR: No snmp response from $hostname (alarm)\n");
	exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

# we must have -some- arguments
if (scalar(@ARGV) == 0) {
	usage();
} # end if no options

Getopt::Long::Configure("no_ignore_case");
$status = GetOptions(
	"h|help"             	=> \$needhelp,
	"C|snmpcommunity=s"  	=> \$community,
	"p|port=i"          	=> \$port,
	"H|hostname=s"      	=> \$hostname,
	"w|warning=i"		=> \$opt_w,
	"c|critical=i"		=> \$opt_c,
);

if ($status == 0 || $needhelp) {
	usage();
} # end if getting options fails or the user wants help

# check MainPseOperStatus
$MainPseOperStatus = snmp_get_request($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.3.1.1.3.1");
if ($MainPseOperStatus eq 3) {
	$critical++;
	$errmsg .= "\nThe operational status of the main PSE is faulty";
}

%bla = snmp_get_table($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.1.1.10");
foreach my $key (keys %bla) {
	$designatedPower += $PoEClass{$bla{$key}-1};
}

$MainPsePower = snmp_get_request($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.3.1.1.2.1");
$MainPseConsumptionPower = snmp_get_request($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.3.1.1.4.1");
$temp_calc = $MainPseConsumptionPower / $MainPsePower * 100;
$statusmsg .= sprintf ("\n$MainPseConsumptionPower watts used out of $MainPsePower watts available (%.1f%% used)", $temp_calc);
$temp_calc = $designatedPower / $MainPsePower * 100;
$statusmsg .= sprintf ("\n$designatedPower watts allocated out of $MainPsePower watts available (%.1f%% allocated)", $temp_calc);
if ($temp_calc >= $opt_c) {
	$critical++;
	$errmsg .= sprintf("\nThe allocated power of %.1f%% is over the critcial threshold of $opt_c%%", $temp_calc);
}
elsif ($temp_calc >= $opt_w) {
	$warning++;
	$errmsg .= sprintf("\nThe allocated power of %.1f%% is over the warning threshold of $opt_w%%", $temp_calc);
}

$MainPseUsageThreshold = snmp_get_request($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.3.1.1.5.1");
if (($MainPseUsageThreshold) && ($temp_calc > $MainPseUsageThreshold)) {
	$warning++;
	$errmsg .= sprintf("\nThe allocated power of %.1f%% is over the system usage threshold of %.1f%%", $temp_calc, $MainPseUsageThreshold);
} 

$temp_calc = $MainPsePower - $designatedPower;
if ($temp_calc < 15.4) {
	$warning++;
	$errmsg .= sprintf("\nOnly %.1f watts if left, not enough for one Class 4 device needing an allocation of 15.4 watts", $temp_calc);
}

%PsePortDetectionStatus = snmp_get_table($hostname, $port, "2c", $community, "1.3.6.1.2.1.105.1.1.1.6");
foreach my $key (keys %PsePortDetectionStatus) {
	if (($PsePortDetectionStatus{$key} eq 4) || ($PsePortDetectionStatus{$key} eq 6)) {
		$warning++;
		@oid_array = split (/\./, $key);
		$interface_num = pop(@oid_array);
		$slot = pop(@oid_array);
		$errmsg .= "\nThere is a power detection fault on $slot/$interface_num";
	}
	elsif ($PsePortDetectionStatus{$key} eq 3) {
		$deliveringPower++;
	}
}
if ($deliveringPower eq 1) {
	$statusmsg .= sprintf("\n$deliveringPower port is being served power for an average of %.1f watts/port", $MainPseConsumptionPower/$deliveringPower);
}
else {
	$statusmsg .= sprintf("\n$deliveringPower ports are being served power for an average of %.1f watts/port", $MainPseConsumptionPower/$deliveringPower);
}

# Test if this is a Cisco device that is power monitor capable
if (($warning || $critical) && (snmp_get_request($hostname, $port, "2c", $community, "1.3.6.1.4.1.9.9.402.1.3.1.3.1") eq 1)) {
#print "DEBUG: Cisco device\n";
	%bla = snmp_get_table($hostname, $port, "2c", $community, "1.3.6.1.4.1.9.9.402.1.2.1.5");
	foreach my $key (sort keys %PsePortDetectionStatus) {
		if (($PsePortDetectionStatus{$key} eq 4) || ($PsePortDetectionStatus{$key} eq 6)) {
			@oid_array = split (/\./, $key);
			$interface_num = pop(@oid_array);
			$slot = pop(@oid_array);
			$temp_calc = hex($bla{"1.3.6.1.4.1.9.9.402.1.2.1.5." . $slot . "." . $interface_num});
			if ($temp_calc ~~ [ 0 .. 2 ] ) {
				$warning++;
				$errmsg .= "\nNote that interface $slot/$interface_num $cpeExtPsePortAdditionalStatus{$temp_calc}";
			}
		}
	}
}

#print "DEBUG: critical [$critical]\n";
#print "DEBUG: warning [$warning]\n";

# figure out what state we're in
if ($critical) {
	$state = "CRITICAL";
} elsif ($warning) {
	$state = "WARNING";
} else {
	$state = "OK";
} # end if we have warnings or not

if (($critical) || ($warning)) {
	$answer = "critical: $critical warning: $warning";
	$output = "$state: $answer$errmsg$statusmsg";
}
else {
	$output = "$state$statusmsg";
}

# setup final message
print ("$output\n");
exit $ERRORS{$state};


## subroutines ##

# the usage of this program (duh)
sub usage
{
	print <<END;
== check_poe v$version ==
Perl SNMP check PoE plugin for Nagios
Frank Bulk <frnkblk\@iname.com>

Usage:
  check_poe (-C|--snmpcommunity) <read_community>
                 (-H|--hostname) <hostname>
                 [-p|--port] <port> 

END
	exit $ERRORS{"UNKNOWN"};
}

sub snmp_get_request {
        my $ip = shift;
	my $port = shift;
        my $version = shift;
	my $community = shift;
        my $sysdescr = shift;

        my $snmp_result = '';

        my ($session, $error) = Net::SNMP->session(
                -hostname => $ip,
                -version => $version,
                -community => $community,
                -port => $port);

        $snmp_result = $session->get_request(
                -varbindlist => [$sysdescr]
                );

        if (!defined($snmp_result)) {
#               print "\nERROR: Trying to obtain $sysdescr from $ip. $session->error.\n";
                sleep 5;
                $snmp_result = $session->get_request(
                        -varbindlist => [$sysdescr]
                );
                if (!defined($snmp_result)) {
                        print "\nERROR: Trying to obtain $sysdescr from $ip. $session->error.\n";
                        $session->close;
                        return 0;
                }
        }

        $session->close;

        return $snmp_result->{$sysdescr};
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
                -timeout => $TIMEOUT,
                -port => $port,
        );

        my $snmp_result = $session->get_table(
                -baseoid => $snmp_oid
        );

        if (!defined($snmp_result)) {
                sleep 5;
                my $snmp_result = $session->get_table(
                         -baseoid => $snmp_oid
                );
                if (!defined($snmp_result)) {
                        print "\nERROR: Trying to obtain $snmp_oid from $ip. $session->error.\n";
                        $session->close;
                        exit $ERRORS{"UNKNOWN"};
                }
        }

        $session->close;

        return %{$snmp_result};
}


