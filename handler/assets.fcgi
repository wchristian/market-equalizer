#!/usr/bin/perl
use strict;
use warnings;

BEGIN {
    $ENV{CAP_DEVPOPUP_EXEC} = 0;
    $ENV{CGI_APP_DEBUG} = 1;
}

use lib "..";
use Games::EveOnline::AssetManager;
use CGI::Fast();

# if there are command line parameters, load them into ENV, in case we're not running on a web server
$ENV{PATH_INFO} = $ARGV[0] if @ARGV;
$ENV{CGIAPP_CONFIG_FILE} ||= '../config.ini';

my $webapp = Games::EveOnline::AssetManager->new(
    PARAMS => {
        'cfg_file' => $ENV{CGIAPP_CONFIG_FILE}
    }
);

while (1) {
    my $q = CGI::Fast->new;
    last if !$q;
    delete $webapp->{$_} for qw( __PRERUN_MODE  __CAP__SESSION_OBJ  sess  query_vars  __HEADER_PROPS );
    $webapp->query( $q );
    $DB::single=1 if $q->{param}{debug};
    $webapp->run();
}

exit;
