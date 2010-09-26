#!/usr/bin/perl

use strict;
use warnings;

use DBI;

$|=1;

use CGI::Carp qw( fatalsToBrowser warningsToBrowser );

use lib '.';
$ENV{CAP_DEVPOPUP_EXEC} = 1;
use Games::EveOnline::AssetManager;
my $webapp = Games::EveOnline::AssetManager->new(
    PARAMS => { cfg_file => 'config.ini' }
);
$webapp->run();
warningsToBrowser(1);