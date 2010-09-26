package Games::EveOnline::MarketOrders::CacheUpdate;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use base qw( Exporter );
our @EXPORT_OK = qw(
    process_cache_export_file
);

sub process_cache_export_file {
    my ($c, $file ) = @_;
    
    return if !-e $file;
    
    say "Reading file...<br>";
    
    my @report_lines = read_file( $file );
    
    say "Segmenting reports in ". @report_lines ." lines...<br>";
    
    my @reports = segment_reports( \@report_lines );
    
    say "Translating orders in ".@reports." reports...<br>";
    
    @reports = map &translate_report_em_to_ec, @reports;
    
    say "Inserting ".@reports." reports...<br>";
    
    $c->finalize_old_batch( $_, 'skip_check' ) for @reports;
    
    unlink $file if -e $file;
    
    return;
}

sub segment_reports {
    my ( $report_lines ) = @_;
    
    my @reports;
    my @report;
    my $parsing;
    
    my $store_report = sub {
            shift @report;
            push @reports, [ @report ];
            @report = ();
    };
    
    for ( @{$report_lines} ) {
        chomp;
        $parsing = 0 if !$_;
        $parsing = 1 if $_ =~ /^price/;
        
        if ( $parsing ) {
            push @report, $_;
            next;
        }
        
        $store_report->() if @report;
    }
    
    $store_report->() if @report;
    
    return @reports;
}

sub translate_report_em_to_ec {
    my $orders = $_;
    
    return if !@{$orders};
    
    my @pairs;
    $pairs[price] = em_price;
    $pairs[orderid] = em_orderID;
    $pairs[regionid] = em_regionID;
    $pairs[systemid] = em_solarSystemID;
    $pairs[stationid] = em_stationID;
    $pairs[typeid] = em_typeID;
    $pairs[bid] = em_bid;
    $pairs[minvolume] = em_minVolume;
    $pairs[volremain] = em_volRemaining;
    $pairs[volenter] = em_volEntered;
    $pairs[issued] = em_issued;
    $pairs[duration] = em_duration;
    $pairs[range] = em_range;
    
    my $dt = DateTime::Format::MySQL->format_datetime( DateTime->now );
    
    my @orders = map &translate_order_em_to_ec( $_, \@pairs, $dt ), @{$orders};
    
    my @first_order = split( / , /, $orders[0] );
    
    my %report;
    $report{content} .= join( "\n", @orders );
    $report{typeid} = $first_order[typeid];
    $report{regionid} = $first_order[regionid];
    $report{reportedtime} = $first_order[reportedtime];
    $report{source} = 'ec';
    
    return \%report;
}

sub translate_order_em_to_ec {
    my ( $order_string, $pairs, $dt ) = @_;
    # reportedby, reportedtime
    
    my @order = split( /,/, $order_string );
    
    my @new_order;
    $new_order[$_] = $order[$pairs->[$_]] for @{$pairs};
    
    $new_order[bid] = 1 if ( $new_order[bid] =~ m/True/ );
    $new_order[bid] = 0 if ( $new_order[bid] =~ m/False/ );
    $new_order[volremain] = int $new_order[volremain];
    $new_order[issued] =~ s/\.000/\.00/;
    $new_order[duration] .= ':00:00:00.00';
    $new_order[reportedby] = 0;
    $new_order[reportedtime] = $dt;
    
    $order_string = join( ' , ', @new_order );
    
    return $order_string;
}


1;
