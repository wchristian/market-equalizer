#!/usr/bin/perl

use strict;
use warnings;

#my $logfile = "mylog2.txt";
#open STDERR, ">>", $logfile or die "cannot append to '$logfile': $!\n";
#select STDERR; $| = 1;
#open LOG, ">&STDERR" or die "cannot dup LOG to STDOUT: $!\n";
#select LOG; $| = 1;

use DBI;

$|=1;

use CGI::Carp qw( fatalsToBrowser warningsToBrowser );

use lib '.';
use lib '..';

$ENV{CGI_APP_DEBUG} = 0;
$ENV{CAP_DEVPOPUP_EXEC} = 0;
$ENV{PATH_INFO} = $ARGV[0] if @ARGV;
use Games::EveOnline::AssetManager;
my $webapp = Games::EveOnline::AssetManager->new(
    PARAMS => { cfg_file => '../config.ini' }
);
$webapp->run;
warningsToBrowser(1);

exit;
