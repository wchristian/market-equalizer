#!/usr/bin/perl
use strict;
use warnings;

BEGIN {
    $ENV{CAP_DEVPOPUP_EXEC} = 0;
    $ENV{CGI_APP_DEBUG} = 1;
    $ENV{DEBUG_MEM} = 1;
}

use lib "..";
use Games::EveOnline::AssetManager;
use CGI::Fast();
use Data::Dumper;
use Dash::Leak;
use Time::HiRes 'time';
use Data::GUID;

$Data::Dumper::Indent = 0;

# if there are command line parameters, load them into ENV, in case we're not running on a web server
$ENV{PATH_INFO} = $ARGV[0] if @ARGV;
$ENV{CGIAPP_CONFIG_FILE} ||= '../config.ini';

my $webapp = Games::EveOnline::AssetManager->new(
    PARAMS => {
        'cfg_file' => $ENV{CGIAPP_CONFIG_FILE}
    }
);
my $guid = Data::GUID->guid_base64;

leaksz "block label";
while (my $q = new CGI::Fast) {
    my $start = time;

    delete $webapp->{$_} for qw( __PRERUN_MODE  __CAP__SESSION_OBJ  sess  query_vars  __HEADER_PROPS );
    $webapp->header_type('header');
    $webapp->query( $q );
    $webapp->run();

    my $duration = time - $start;

    leaksz( 'profile', sub { log_memory( { duration => $duration, webapp => $webapp }, @_ ) } );
}

exit;

sub log_memory {
    my ( $data, $change, $in_out, $name ) = @_;

    my $now = int time;

    $data->{webapp}->dbh->do(
        "
            INSERT INTO eaa_profile_log
            ( log_time, guid, program, in_out, path_info, mem_change, duration )
            VALUES
            (?,?,?,?,?,?,?)
        ",
        undef,
        $now, $guid, $0, $in_out, $ENV{PATH_INFO}, $change, $data->{duration}
    );

    return;
}
