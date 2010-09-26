#!/usr/bin/perl

use strict;
use warnings;

#my $logfile = "mylog.txt";
#open STDERR, ">>", $logfile or die "cannot append to '$logfile': $!\n";
#select STDERR; $| = 1;
#open LOG, ">&STDERR" or die "cannot dup LOG to STDOUT: $!\n";
#select LOG; $| = 1;

use DBI;

$|=1;

use CGI::Carp qw( fatalsToBrowser warningsToBrowser );

use lib '.';
use lib '..';

$ENV{CAP_DEVPOPUP_EXEC} = 0;
$ENV{CGI_APP_DEBUG} = 0;
$ENV{PATH_INFO} = $ARGV[0] if @ARGV;
use Games::EveOnline::MarketOrders;
my $webapp = Games::EveOnline::MarketOrders->new(
    PARAMS => { cfg_file => '../market_config.ini' }
);
$webapp->run;
warningsToBrowser(1);

exit;
