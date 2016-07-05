#!/usr/bin/perl -w

### check_snmp_lmsensors.pl
# based on check_stuff.pl

# Alexander Greiner-Baer <alexander.greiner-baer@web.de> 2007 
#
# Nagios plugin using the Nagios::Plugin module and Net::SNMP.  
# the snmp code is inspired by the check_snmp_env-Plugin written by
# Patrick Proy (http://www.manubulon.com/nagios/)
# checks status of temperature sensors and fans on remote hosts with snmp
# you need a lmsensors-enabled net-snmpd on the remote host
# test with:
#
# snmpwalk -v1 -c public <host> .1.3.6.1.4.1.2021.13.16
# snmpwalk -v 2c -c public <host> LM-SENSORS-MIB::lmTempSensorsValue
#
# License: GPL

use strict;
use warnings;

use Nagios::Plugin ;
use Net::SNMP;

use vars qw($VERSION $PROGNAME  $verbose $warn $critical $timeout $result);
$VERSION = 1;

$PROGNAME = "check_snmp_lmsensors";

# LM-SENSORS-MIB
my $lmSensorsBase = "1.3.6.1.4.1.2021.13.16";
my $lmSensorsTempTable = $lmSensorsBase.".2";
my $lmSensorsFanTable = $lmSensorsBase.".3";

my $lmSensorsIndex = ".1.1";
my $lmSensorsDesc = ".1.2";
my $lmSensorsValue = ".1.3";

# instantiate Nagios::Plugin
my $p = Nagios::Plugin->new(
	usage => "Usage: %s [ -v|--verbose ]  [-H <host>] [-t <timeout>]
	[ -C|--community=<COMMUNITY NAME> ] [ -s|--sensor=<Temp> or <Fan> ]
	[ -i|--index=<sensor index> ]
	[ -c|--critical=<critical threshold> ] [ -w|--warning=<warning threshold> ]",
	version => $VERSION,
	blurb => 'This plugin checks the given sensor (Fan or Temp) on the remote 
	host with snmp and will output OK, WARNING or CRITICAL if the resulting number 
	is between the specified thresholds. Remote host needs lmsensors-enabled net-snmpd.', 
	shortname => "SNMP Sensor",
	extra => "

	THRESHOLDs for -w and -c are specified 'min:max' or 'min:' or ':max'
	(or 'max'). If specified '\@min:max', a warning status will be generated
	if the count *is* inside the specified range.

	Examples:

	$PROGNAME -w 10 -c 18 Returns a warning
	if the resulting number is greater than 10,
		or a critical error
	if it is greater than 18.

	$PROGNAME -w 10 : -c 4 : Returns a warning
	if the resulting number is less than 10,
		or a critical error
	if it is less than 4.

	"
);

# add all arguments
$p->add_arg(
	spec => 'warning|w=s',

	help => 
	qq{-w, --warning=INTEGER,[INTEGER]
	Maximum number of allowable result, outside of which a
	warning will be generated.  If omitted, no warning is generated.},
	required => 1,
);

$p->add_arg(
	spec => 'critical|c=s',
	help => 
	qq{-c, --critical=INTEGER,[INTEGER]
	Maximum number of the generated result, outside of
	which a critical will be generated. },
	required => 1,
);

$p->add_arg(
	spec => 'sensor|s=s',
	help => 
	qq{-s, --sensor=STRING
	Specify the Sensortype on the command line. Use Temp or Fan.},
	required => 1,
);

$p->add_arg(
	spec => 'index|i=s',
	help => 
	qq{-i, --index=INTEGER
	Specify the Sensor numbers on the command line.},
	required => 1,
);

$p->add_arg(
	spec => 'community|C=s',
	help => 
	qq{-C, --community=STRING
	Specify the community name on the command line.},
	required => 1,
);

$p->add_arg(
	spec => 'host|H=s',
	help => 
	qq{-H, --host=STRING
	Specify the host on the command line.},
	required => 1,
);

# parse arguments
$p->getopts;

# split sensor numbers and thresholds

# get sensors and thresholds to check
my @sensors = split(',',$p->opts->index);
my @warn_thresholds = split(',',$p->opts->warning);
my @crit_thresholds = split(',',$p->opts->critical);
my $elem;

# print out sensor numbers and thresholds
if ( $p->opts->verbose ) {
	print "Sensors:\n";
	for $elem (@sensors) {
		print $elem."\n";
	} 
	print "Warning thresholds:\n";
	for $elem (@warn_thresholds) {
		print $elem."\n";
	} 
	print "Critical thresholds:\n";
	for $elem (@crit_thresholds) {
		print $elem."\n";
	} 
	print "--\n";

}

# perform checking on command line options

if ( (defined $p->opts->sensor) && ($p->opts->sensor !~ m/^Fan$/ && $p->opts->sensor !~ m/^Temp$/) )  {
	$p->nagios_die( " invalid Sensor supplied for the -s option " );
}

for $elem (@sensors) {
	if ( (defined $elem) && ( ($elem !~ m/^\d+$/)  || ($elem < 1 || $elem > 20) ) )  {
		$p->nagios_die( " invalid number supplied for the -i option " );
	}
}

for $elem (@warn_thresholds) {
	unless ( (defined $elem) && ( ($elem =~ m/^\d+$/) ||  ($elem =~ m/^\d+:\d+$/) ) ) {
		$p->nagios_die( " you didn't supply a threshold argument " );
	}
}

for $elem (@crit_thresholds) {
	unless ( (defined $elem) && ( ($elem =~ m/^\d+$/) ||  ($elem =~ m/^\d+:\d+$/) ) ) {
		$p->nagios_die( " you didn't supply a threshold argument " );
	}
}

unless ( $#sensors == $#warn_thresholds && $#sensors == $#crit_thresholds ) {
	$p->nagios_die( " index <-> thresholds mismatch "  );
}

my @thresholds;
for (my $i=0;$i<$#sensors+1;$i++) {
	$thresholds[$i] = { 'Warn' => $warn_thresholds[$i], 'Crit' => $crit_thresholds[$i] };
}

# checking

my @results;
my $sens_value;
my $sens_desc;
my $uom;
my $return=0;
my $message="";

# open snmp session
my ($session,$error);
($session, $error) = Net::SNMP->session(
	hostname  => $p->opts->host,
	community => $p->opts->community
);
if (!defined($session)) {
	$p->nagios_exit(
		return_code => "UNKNOWN",
		message => $error
	);
}

# set snmp table to use
my $isTemp = 0;	
my $lmSensorsUsedTable = $lmSensorsFanTable;
# use temperature table for temperature checking
if ( $p->opts->sensor =~ m/^Temp$/ ) {
	$lmSensorsUsedTable = $lmSensorsTempTable;
	$isTemp = 1;
}

# full output is in $table
my $table = $session->get_table($lmSensorsUsedTable);

if ( $p->opts->verbose ) {
	print "SNMP output table:\n";
	foreach my $key (sort keys %$table) {
		print "$key $$table{$key}\n";
	}
	print "--\n";
}

if (!defined($table)) {
	my $session_error = $session->error;
	$session->close;
	$p->nagios_exit(
		return_code => "UNKNOWN",
		message => $session_error
	);
}
$session->close;

# check number of sensors we have
my $num_sensors = 0;
my $comb;
foreach my $key (keys %$table) {
	$comb = $lmSensorsUsedTable.$lmSensorsIndex;
	if ( $key =~ /$comb/ ) {
		$num_sensors++;
	}

}

# process the snmp output and store in @results
my $i=0;
for $elem (@sensors) {
	if ( $elem > $num_sensors ) {
		$p->nagios_exit(
			return_code => "UNKNOWN",
			message => "invalid sensor index"
		);
	}
	$uom = "U/min";
	foreach my $key (keys %$table) {
		$comb = $lmSensorsUsedTable.$lmSensorsDesc.".".$elem;
		if ( $key =~ /$comb/ ) {
			$sens_desc = $$table{$key};
		}
		$comb = $lmSensorsUsedTable.$lmSensorsValue.".".$elem;
		if ( $key =~ /$comb/ ) {
			$sens_value = $$table{$key};
		}
	}
	if ( $isTemp ) {
		# lmSensors temperature output is multplied with 1000
		$sens_value = $sens_value / 1000;
		$uom = "C";
	}
	$results[$i] = { 'Desc' => $sens_desc, 'Value' => $sens_value, 'UOM' => $uom };
	$i++;
}
if ( $p->opts->verbose ) {
	print "Results:\n";
	foreach $elem (@results) {
		print $elem->{'Desc'},"\n";
		print $elem->{'Value'},"\n";
		print $elem->{'UOM'},"\n";
	}
	print "--\n";
}

# compare results with thresholds and add perfparse output
for (my $i=0;$i<$#sensors+1;$i++) {
	my $loc_ret=0;
	$p->set_thresholds(warning => $thresholds[$i]->{'Warn'}, critical => $thresholds[$i]->{'Crit'});
	my $threshold = $p->threshold;

	$p->add_perfdata(
		label	=> $results[$i]->{'Desc'},
		value	=> $results[$i]->{'Value'},
		uom	=> "",
		threshold => $threshold
	);
	$loc_ret = $p->check_threshold(check => $results[$i]->{'Value'}, warning => $thresholds[$i]->{'Warn'}, critical => $thresholds[$i]->{'Crit'});
	if ( $p->opts->verbose ) {
		print "Sensor ".($i+1)." returned: $loc_ret\n";
	}
	if ( $loc_ret != 0 ) {
		$message =  $message.$results[$i]->{'Desc'}.": ".$results[$i]->{'Value'}." (".$results[$i]->{'UOM'}.") exceeds threshold";
	}
	else {
		$message = $message.$results[$i]->{'Desc'}.": ".$results[$i]->{'Value'}." (".$results[$i]->{'UOM'}.")"; 
	}
	if ( $i != $#sensors ) {
		$message.=", ";
	}
	$return = $return | $loc_ret;
}

$p->nagios_exit( 
	return_code => $return, 
	message => $message 
);


