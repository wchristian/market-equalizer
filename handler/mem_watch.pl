use strict;
use warnings;

package mem_watch;

use DBIx::Simple;
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Config::INI::Reader;
use CGI 'header';

my $global_max = 0;
my $global_min = 0;

my $config = Config::INI::Reader->read_file('../config.ini')->{_};

my $db = DBIx::Simple->new( $config->{db_source}, $config->{db_user}, $config->{db_password} );

my @data = ( get_data( $db, "eaa_profile_log" ), get_data( $db, "emo_profile_log" ), );
split_by_path( $_ ) for @data;

my @graphs = map make_graph( $_ ), sort { $a->{own_start} <=> $b->{own_start} } @data;

page( @graphs );

exit;

sub split_by_path {
    my ( $set ) = @_;

    my %paths;
    for ( @{$set->{rows}} ) {
        $_->{path_info} =~ s:^/list/[\w-]+:/list/\<region\>:;
        my $path = $paths{$_->{path_info}} ||= {};
        $path->{size} ||= 0;
        $path->{name} = $_->{path_info};
        push @{$path->{rows}}, { x => $set->{own_start} - $set->{start}, y => 0 } if !$path->{rows};
    }

    my $last_index;
    for ( @{$set->{rows}} ) {
        my $path = $paths{$_->{path_info}};
        $path->{size} += $_->{mem_change};
        $path->{reqs}++;

        $last_index = $_->{log_time} - $set->{start};
        push @{$path->{rows}}, { x => $last_index, y => sprintf "%.2f", $path->{size} };
    }

    my @paths = reverse sort { $a->{size} <=> $b->{size} } values %paths;
    $set->{rows} = [ @paths ];

    for ( @paths ) {
        $_->{color} = random_color();
        $_->{per_req} = sprintf "%.2f", $_->{size}/$_->{reqs};
        push @{$_->{rows}}, { x => $last_index, y => $_->{size} };

        $global_max = max( $global_max, $_->{size});
        $global_min = min( $global_min, $_->{size});

        $_->{size} = sprintf "%.2f", $_->{size};
    }

    return;
}

sub random_color
{
    my @hex;

    push( @hex, rand 255 ) for ( 0 .. 2 );

    while ( !is_colorful(@hex) )
    {
        shift @hex;
        push @hex, rand 255;
    }

    $_ = sprintf( "%02x", $_ ) for (@hex);

    my $color = "\#" . $hex[0] . $hex[1] . $hex[2];

    return $color;
}

# function checks rgb colour against HSV constraints, returns 1 if it's sufficiently colourful, 0 if not
sub is_colorful
{
    my @colours = @_;

    $_ /= 255 for (@colours);

    my $brightness = sqrt(
      $colours[0] * $colours[0] * .241 +
      $colours[1] * $colours[1] * .691 +
      $colours[2] * $colours[2] * .068);

    return 0 if $brightness > 0.7;
    return 0 if $brightness < 0.3;

    my $value = max @colours;
    #
    #return 0 if $value > 0.9;
    #return 0 if $value < 0.1;

    my $min        = min @colours;
    my $delta      = $value - $min;
    my $saturation = $delta / $value;

    return 0 if $saturation < 0.8;

    return 1;
}

sub get_data {
    my ( $db, $table ) = @_;

    my @rows = $db->query("select guid, program, mem_change, log_time, path_info from $table order by log_time")->hashes;

    $_->{mem_change} = $_->{mem_change} / 1024 for @rows;

    my %sets;
    for ( @rows ) {
        $sets{$_->{guid}}->{program} = $_->{program};
        $sets{$_->{guid}}->{start} = $rows[0]->{log_time};
        $sets{$_->{guid}}->{end} = $rows[-1]->{log_time};
        $sets{$_->{guid}}->{size} ||= 0;
        $sets{$_->{guid}}->{size} += $_->{mem_change};
        push @{$sets{$_->{guid}}->{rows}}, $_;
    }

    my $max = max map { $_->{size} } values %sets;

    $_->{row_count} = @{$_->{rows}} for values %sets;
    $_->{max} = $max for values %sets;

    $_->{own_start} = $_->{rows}[0]{log_time} for values %sets;

    return values %sets;
}


sub make_graph {
    my ( $data ) = @_;

    my $rows = $data->{rows};

    return if $data->{row_count} < 200;

    my $json = to_json( $rows );

    my $end = $data->{end}-$data->{start};

    my $legend = join '', map {
        "
            <tr style='color: $_->{color}'>
                <th>$_->{name}</th>
                <td>$_->{reqs} reqs</td>
                <td>$_->{size} MB</td>
                <td>$_->{per_req} MB</td>
            </tr>
        " } @{$rows};

    return qq|
        <h3>$data->{program} ($data->{row_count} requests)</h3>
        <div class="fig">
            <table>
                <tr>
                    <td>
                        <script type="text/javascript+protovis">
                            var data = $json;
                            stack( data, "0", "$end", "$global_min", "$global_max" );
                        </script>
                    </td>
                    <td>
                        <table border="1" style="border-collapse:collapse;text-align:right;">
                            <tr><th>path</th><th>requests</th><th>sum of changes</th><th>change per request</th></tr>
                            $legend
                        </table>
                    </td>
                </tr>
            </table>
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

    <script type="text/javascript+protovis">
        function stack( data, start, end, min, max ) {

            var w = 400,
            h = 100,
            x = pv.Scale.
                linear(start, end).
                range(0, w),
            y = pv.Scale.
                linear(min, max).
                range(0, h);

            /* The root panel. */
            var vis = new pv.Panel()
                .width(w)
                .height(h)
                .bottom(20)
                .left(20)
                .right(10)
                .top(5);

            /* X-axis ticks. */
            vis.add(pv.Rule)
                .data(x.ticks())
                .visible(function(d) d > 0)
                .left(x)
                .strokeStyle("#eee")
              .add(pv.Rule)
                .bottom(-5)
                .height(5)
                .strokeStyle("#000")
              //.anchor("bottom").add(pv.Label)
                //.text(x.tickFormat)
                ;

            /* Y-axis ticks. */
            vis.add(pv.Rule)
                .data(y.ticks(5))
                .bottom(y)
                .strokeStyle(function(d) d ? "#eee" : "#000")
              .anchor("left").add(pv.Label)
                .text(y.tickFormat);

            /*vis.add(pv.Layout.Stack)
                .layers(data)
                .offset(-40)
                .x(function(d) x(d.x))
                .y(function(d) y(d.y))
              .layer.add(pv.Area);*/

            data.forEach(addline);

            function addline(line) {
                vis.add(pv.Line)
                    .data(line.rows)
                    .interpolate("step-after")
                    .left(function(d) x(d.x))
                    .bottom(function(d) y(d.y))
                    .strokeStyle(pv.color(line.color))
                    .lineWidth(2);
            }

            vis.render();
        }
    </script>
		<style type="text/css">
        th { text-align: left; }
        td, th { padding-left: 0.4em; padding-right: 0.4em; }
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
