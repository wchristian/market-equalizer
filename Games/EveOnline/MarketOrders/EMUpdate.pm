package Games::EveOnline::MarketOrders::EMUpdate;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use base qw( Exporter );
our @EXPORT_OK = qw(
    mark_history_times          drop_cold_caches    download_em_xml     get_em_price_data
    get_price_sets_from_em      sub_divide_array    prepare_em_urls     get_em_history_data
    download_em_data            compact_em_data     parse_em_json
    mark_prices_for_filling     get_history_sets_from_em
);



sub get_em_history_data {
    my ( $c, $region ) = @_;
    
    my @price_sets = $c->get_history_sets_from_em( $region );
    
    my $inserted_reports = 0;
    $inserted_reports += $c->finalize_old_batch( $_, 'skip_check' ) for @price_sets;
    
    say "$inserted_reports price sets were found to be newer than existing data and were inserted into the database.<br>";
    
    return $inserted_reports;
}

sub get_history_sets_from_em {
    my ( $c, $region ) = @_;
    
    my @history_sets = $c->download_em_data( "http://eve-metrics.com/api/history.json", $region, 90 );
    
    say "<br>Downloaded ". @history_sets ." history sets.<br>";
    
    my %histories = map &drop_cold_caches, @history_sets;
    @history_sets = values %histories;
    
    say  @history_sets ." history sets left after dropping cold caches.<br>";
    
    my %data_sets = map $c->mark_history_times( $_, $histories{$_} ), keys %histories;
    
    my @data_sets = map $c->compact_em_data( $_, 'hi' ), values %data_sets;
    
    say @data_sets." data sets left after combining price and history data.<br>";
    
    return @data_sets;
}

sub mark_history_times {
    my ( $c, $typeid, $history ) = @_;
    
    return if !$history;
    
    $history->{regions}[0]{history_reference_time} = $history->{regions}[0]{last_upload};
    return ( $typeid => $history );
}

sub get_em_price_data {
    my ( $c, $region ) = @_;
    
    my @price_sets = $c->get_price_sets_from_em( $region );
    
    my $inserted_reports = 0;
    $inserted_reports += $c->finalize_old_batch( $_, 'skip_check' ) for @price_sets;
    
    say "$inserted_reports price sets were found to be newer than existing data and were inserted into the database.<br>";
    
    return $inserted_reports;
}

sub get_price_sets_from_em {
    my ( $c, $region ) = @_;
    
    my @price_sets = $c->download_em_data( "http://eve-metrics.com/api/item.json", $region );
    
    say "<br>Downloaded ".@price_sets." price sets.<br>";
    
    my %prices = map &drop_cold_caches, @price_sets;
    @price_sets = values %prices;
    
    say @price_sets." price sets left after dropping cold caches.<br>";
    
    my %data_sets = map $c->mark_prices_for_filling( $_, $prices{$_} ), keys %prices;
    
    my @data_sets = map $c->compact_em_data( $_, 'em' ), values %data_sets;
    
    say @data_sets." data sets left after combining price and history data.<br>";
    
    return @data_sets;
}

sub mark_prices_for_filling {
    my ( $c, $typeid, $price ) = @_;
    
    return if !$price;
    
    $price->{regions}[0]{fill_history_with_old} = 1;
    return ( $typeid => $price );
}

sub download_em_data {
    my ( $c, $base_url, $region, $days ) = @_;
    
    my @em_sets;
    my $b = timeit( 1, sub {
        @em_sets = $c->download_em_xml( $base_url, $region, $days );
    } );
    say "parallel download took: ".timestr($b)."<br>";
    
    my $b2 = timeit( 1, sub {
        @em_sets = map $c->parse_em_json($_), @em_sets;
    } );
    say "XML parsing took: ".timestr($b2)."<br>";
    
    return @em_sets;
}

sub drop_cold_caches {
    my $regions = $_->{regions};
    return if !$regions;
    my $region = $regions->[0];
    return if !$region;
    return if !$region->{last_upload} or 'HASH' eq ref $region->{last_upload};
    return if $region->{last_upload} eq 'null';
    return ( $_->{type_id} => $_ );
}

sub compact_em_data {
    my ( $c, $set, $source ) = @_;
    
    my $content = $set->{regions}[0];
    $content->{typeid} = $set->{type_id};
    $content->{regionid} = $content->{region_id};
    $content->{last_upload} =~ s/ \+\d+$// if $content->{last_upload};
    
    delete $content->{region_id};
    delete $content->{oldest_data};
    delete $content->{region_name};
    
    my $content_json = to_json($content);
    
    my %new_set = (
        typeid => $content->{typeid},
        regionid => $content->{regionid},
        reportedtime => $content->{last_upload},
        source => $source,
        content => $content_json,
    );
    
    return \%new_set;
}

sub download_em_xml {
    my ( $c, $base_url, $region, $days ) = @_;
    
    my %cfg = $c->cfg;
    
    $c->{cfg}{all_items} = [ $c->{cfg}{all_items} ] if 'ARRAY' ne ref $c->{cfg}{all_items};
    
    my @type_ids = @{ $c->{cfg}{all_items} };
    
    my @type_id_lists = $c->sub_divide_array ( 6, @type_ids );
    
    say "<br>Prepared ". @type_id_lists ." type id sets.<br>";
    
    my @downloads = map $c->prepare_em_urls( $_, $base_url, $region, $days ), @type_id_lists;
    
    my @results = download_in_parallel( @downloads );
    
    return @results;
}

sub parse_em_json {
    my ( $c, $xml ) = @_;
    
    return if !$xml;
    my $xml_ref;
    eval {
        $xml_ref = from_json( $xml );
    };
    if ( $@ ) {
        #say "\n!!! XML Parsing Error:\n$!\n $@\n$xml!!!\n" if $@;
        return;
    }
    
    my @data_sets = @{ $xml_ref };
    
    return @data_sets;
}

sub sub_divide_array {
    my ( $c, $limit, @array ) = @_;
    
    my @type_id_lists;
    while ( @array ) {
        if ( @array > $limit )  {
            my @list;
            push @list, pop( @array ) for 1..$limit;
            push @type_id_lists, \@list;
        }
        else {
            push @type_id_lists, \@array;
            last;
        }
    }
    
    return @type_id_lists;
}

sub prepare_em_urls {
    my ( $c, $id_arr, $base_url, $region, $days ) = @_;
    
    my %cfg = $c->cfg;
    
    my $ids = join( ',', @{$id_arr} );
    
    my $url = "$base_url?type_ids=$ids&region_ids=$region&key=$c->{cfg}{em_dev_key}";
    $url .= "&days=$days" if $days;
    
    return $url;
}

1;
