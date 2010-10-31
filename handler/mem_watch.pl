use strict;
use warnings;

package mem_watch;

use DBIx::Simple;
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Config::INI::Reader;
use CGI 'header';

my $config = Config::INI::Reader->read_file('../config.ini')->{_};

my $db = DBIx::Simple->new( $config->{db_source}, $config->{db_user}, $config->{db_password} );

my @data = ( get_data( $db, "emo_profile_log" ), get_data( $db, "eaa_profile_log" ), );

my @graphs = map make_graph( $_ ), sort { $a->{own_start} <=> $b->{own_start} } @data;

page( @graphs );

exit;

sub get_data {
    my ( $db, $table ) = @_;

    my @rows = $db->query("select guid, program, mem_change, log_time from $table order by log_time")->hashes;

    $_->{mem_change} = $_->{mem_change} / 1024 for @rows;

    my %sets;
    for ( @rows ) {
        $sets{$_->{guid}}->{program} = $_->{program};
        $sets{$_->{guid}}->{start} = $rows[0]->{log_time};
        $sets{$_->{guid}}->{end} = $rows[-1]->{log_time};
        $sets{$_->{guid}}->{size} ||= 0;
        $sets{$_->{guid}}->{size} += $_->{mem_change};
        push @{$sets{$_->{guid}}->{rows}}, { x => $_->{log_time}, y => $sets{$_->{guid}}->{size} };
    }

    my $min = min map { $_->{rows}[0]{y} } values %sets;
    my $max = max map { $_->{rows}[-1]{y} } values %sets;

    $_->{min} = $min for values %sets;
    $_->{max} = $max for values %sets;

    $_->{own_start} = $_->{rows}[0]{x} for values %sets;

    return values %sets;
}


sub make_graph {
    my ( $data ) = @_;

    my $rows = $data->{rows};

    my $count = @$rows;
    return if $count < 200;

    my $json = to_json( $rows );

    return qq|
        <h3>$data->{program} ($count)</h3>
        <div class="fig">
            <script type="text/javascript+protovis">
                var data = $json;
                stack( data, "$data->{start}", "$data->{end}", "$data->{min}", "$data->{max}" );
            </script>
        </div>
    |;
}

sub page {
    my ( @graphs ) = @_;

    print header();
    print qq|
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN">

<html>
<head>
    <title>Memory Progression Charts</title>
    <script type="text/javascript" src="protovis-r3.2.js"></script>
    <script type="text/javascript" src="stack.js"></script>
    <style type="text/css">


    </style>
</head>

<body>
    <div id="center">
    |;
    print for @graphs;
    print qq|
    </div>
</body>
</html>
    |;

}
