package Games::EveOnline::MarketOrders::ECUpdate;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

memoize( 'expiry_to_timestamp' );

use base qw( Exporter );
our @EXPORT_OK = qw(
    get_newest_dump_filenames   download_dumps  process_ec_dump_file    unpack_dump
);


sub get_newest_dump_filenames {
    my ( $c ) = @_;

    my %cfg = $c->cfg;

    my $max_count = 15;
    my $base_url = 'http://eve-central.com/dumps/';
    my $last_update = time - ($max_count+1) * ( 60 * 60 * 24 );

    if( -e $c->{cfg}{dump_dir}."last_update" ) {
        open my $fh, '<', $c->{cfg}{dump_dir}."last_update";
        ($last_update ) = <$fh>;
        close $fh;
    }

    my @files;
    foreach my $entry ( WWW::IndexParser->new( url => $base_url ) ) {
        next if $entry->filename !~ /.dump.gz/ or $entry->filename =~ /latest_db/;
        my $file_date = $entry->filename;
        $file_date =~ s/.dump.gz//;
        $file_date = expiry_to_timestamp( $file_date );
        next if $file_date <= $last_update;

        push @files, $entry;
    }

    return @files;
}

sub download_dumps {
    my ($c,$files) = @_;

    my %cfg = $c->cfg;

    my $base_url = 'http://eve-central.com/dumps/';
    my @downloads;

    for my $file ( @{ $files } ) {
        next if( -e $c->{cfg}{dump_dir}.$file->filename );
        my %download = (
            url => $base_url.$file->filename,
            path => $c->{cfg}{dump_dir}.$file->filename,
            store => 'file',
            name => $file->filename,
        );
        push @downloads, \%download;
    }

    return if !@downloads;

    say "Downloading ". @downloads ." new files.<br><br>";

    return download_in_parallel ( @downloads );
}

sub process_ec_dump_file {
    my ($c, $file ) = @_;

    my %cfg = $c->cfg;

    my $dump_file = $c->{cfg}{dump_dir}.$file->filename;

    say "Unpacking $dump_file...<br>";
    my $unpackedname = $c->unpack_dump($dump_file);

    my $t0 = new Benchmark;
    say "Preparing orders for insertion...<br>";

    my %old;

    my $inserts = 0;
    my $attempted_inserts = 0;
    my $counter = 0;
    my $counter2 = 0;

    my %csv_column = (
        typeid => typeid,
        regionid => regionid,
        reportedtime => reportedtime,
    );

    open my $csv, "<", $unpackedname;
    <$csv>;
    while ( <$csv> ) {
        my @order = split ' , ', $_;

        $order[reportedtime] = substr $order[reportedtime], 0, 16 ;

        my $is_next_order_batch;
        if ( $old{typeid} ) {
            my %changes;
            for my $column ( qw( typeid regionid reportedtime ) ){
                $changes{$column}{old} = $old{$column};
                $changes{$column}{new} = $order[$csv_column{$column}];
            }
            $changes{typeid}{changed} = 1 if $changes{typeid}{old} != $changes{typeid}{new};
            $changes{regionid}{changed} = 1 if $changes{regionid}{old} != $changes{regionid}{new};
            $changes{reportedtime}{changed} = 1 if $changes{reportedtime}{old} ne $changes{reportedtime}{new};

            if ( $changes{typeid}{changed} or $changes{regionid}{changed} or $changes{reportedtime}{changed} ) {
                $is_next_order_batch = 1;
            }
        }

        if ( $is_next_order_batch ) {
            $old{source} = 'ec';
            $inserts += $c->finalize_old_batch( \%old );
            $attempted_inserts++;
            $old{content} = '';
        }

        $old{content} .= $_;
        $old{typeid} = $order[typeid];
        $old{regionid} = $order[regionid];
        $old{reportedtime} = $order[reportedtime];

        $counter++;
        unless ( $counter % 1000 ) {
            print ".";
            $counter2++;
            say "<br>" unless $counter2 % 80;
        }
    }
    close $csv;

    say "   <br>
            $counter orders checked, $inserts/$attempted_inserts reports inserted.<br>
            Operation time: ".timestr(timediff(Benchmark->new, $t0))."<br>
            <br>";

    my $file_date = $file->filename;
    $file_date =~ s/.dump.gz//;
    $file_date = expiry_to_timestamp( $file_date );

    open my $fh, '>', $c->{cfg}{dump_dir}."last_update";
    print $fh $file_date;
    close $fh;

    unlink $unpackedname if -e $unpackedname;

    return $inserts;
}

sub unpack_dump {
    my ($c,$dumpname) = @_;
    my $buffer;
    my ($unpacked,$unpackedname) = tempfile();
    my $gz = gzopen($dumpname, "rb") or die "Cannot open $dumpname: $gzerrno\n" ;
    print $unpacked $buffer while ($gz->gzread($buffer) > 0);

    return $unpackedname;
}


1;
