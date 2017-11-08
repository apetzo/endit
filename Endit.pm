#   ENDIT - Efficient Northern Dcache Interface to TSM
#   Copyright (C) 2006-2017 Mattias Wadenstein <maswan@hpc2n.umu.se>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see <http://www.gnu.org/licenses/>.

package Endit;
use strict;
use warnings;
use IPC::Run3;
use POSIX qw(strftime);

our (@ISA, @EXPORT_OK);
BEGIN {
	require Exporter;
	@ISA = qw(Exporter);
	@EXPORT_OK = qw(%conf readconf printlog getusage);
}


our $logsuffix;
our %conf;

sub printlog($) {
	my $msg = shift;
	my $now = strftime '%Y-%m-%d %H:%M:%S', localtime;

	my $lf;
	if($conf{'logdir'}) {
		my $logfilename = $conf{'logdir'} . '/' . $logsuffix;
		open $lf, '>>', $logfilename or warn "Failed to open $logfilename: $!";
	}

	chomp($msg);
	my $str = "$now [$$] $msg\n";

	if($lf && $lf->opened) {
		print $lf $str;
		if(!close($lf)) {
			print $str;
		}
	} else {
		print $str;
	}
}

my %confold2new = (
	timeout => 'archiver_timeout',
	minusage => 'archiver_threshold1_usage',
	maxretrievers => 'retriever_maxworkers',
	tapefile => 'retriever_hintfile',
	remounttime => 'retriever_remountdelay',
);

my %confobsolete = (
	hsminstance => 1,
	remotedirs => 1,
	pollinginterval => 1,
	maxusage => 1,
);

sub readconf() {
	my $conffile = '/opt/endit/endit.conf';

	# Sensible defaults
	$conf{sleeptime} = 60; # Seconds
	$conf{archiver_timeout} = 7200; # Seconds
	$conf{archiver_threshold1_usage} = 500; # GB
	$conf{retriever_maxworkers} = 1; # Number of processes
	$conf{retriever_remountdelay} = 600; # Seconds

	if($ENV{ENDIT_CONFIG}) {
		$conffile = $ENV{ENDIT_CONFIG};
	}

	printlog "Using configuration file $conffile";

	open my $cf, '<', $conffile or die "Can't open $conffile: $!";
	while(<$cf>) {
		next if $_ =~ /^#/;
		chomp;
		next unless($_);
		next if(/^\s+$/);

		my($key,$val) = split /:\s+/;
		if(!defined($key) || !defined($val) || $key =~ /^\s/ || $key =~ /\s$/) {
			die "Aborting on garbage config line: '$_'";
			next;
		}

		if($confold2new{$key}) {
			warn "Config directive $key deprecated, please use $confold2new{$key} instead";
			$key = $confold2new{$key};
		}

		if($confobsolete{$key}) {
			warn "Config directive $key OBSOLETE, skipping";
			next;
		}

		$conf{$key} = $val;
	}

	# Verify that required parameters are defined
	foreach my $param (qw{dir logdir dsmcopts}) {
		if(!defined($conf{$param})) {
			die "$conffile: $param is a required parameter, exiting";
		}
	}

	# Verify that required subdirs are present and writable
	foreach my $subdir (qw{in out request requestlists trash}) {
		if(! -d "$conf{dir}/$subdir") {
			die "Required directory $conf{dir}/$subdir missing, exiting";
		}
		my $tmpf = "$conf{dir}/$subdir/.endit.$$";
		if(open(my $fh, '>', $tmpf)) {
			close($fh);
			unlink($tmpf);
		}
		else {
			my $err = $!;
			unlink($tmpf); # Just in case
			die "Can't write to directory $conf{dir}/$subdir: $err, exiting";
		}
	}
}

# Return filessystem usage (gigabytes)
sub getusage($@) {
	my $dir = shift;
	my $size = 0;

	printlog "Getting size of files in $dir: ". join(" ", @_) if($conf{debug});

	while(my $file = shift) {
		next unless(-e "$dir/$file");

		$size += (stat _)[7];
	}

	printlog "Total size: $size bytes" if($conf{debug});

	return $size/(1024*1024*1024); # GiB
}

sub readtapelist($) {
	my $tapefile = shift;
	printlog "reading tape list $tapefile" if $conf{verbose};
	my $out = {};
	open my $tf, '<', $tapefile or return undef;
	while (<$tf>) {
		chomp;
		my ($id,$tape) = split /\s+/;
		next unless defined $id && defined $tape;
		$tape=~tr/a-zA-Z0-9.-/_/cs;
		$out->{$id} = $tape;
	}
	close($tf);
	return $out;
}

1;
