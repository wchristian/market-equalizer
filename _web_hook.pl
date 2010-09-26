#!/usr/bin/perl -w
use strict;
use warnings;

use CGI;
use Time::HiRes qw /time/;
use Data::Dumper;

my $cgi = CGI->new;
my %q = $cgi->Vars;

my $dir = "csv/";

open my $log, ">>", 'log';
print $log Dumper( \%q );
close $log;

die "DON'T HACK THE GIBSON" if (  !$q{type_id} or !$q{region_id} or !$q{source} or !$q{data} );

open my $fh, ">", $dir.time;
print $fh $q{data};
close $fh;

print $cgi->header;
print "success";