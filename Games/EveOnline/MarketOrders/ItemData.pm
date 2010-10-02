package Games::EveOnline::MarketOrders::ItemData;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use Data::Dumper;

use base qw( Exporter );
our @EXPORT_OK = qw(
    calculate_market_movement_from_report   insert_item_value_data  expire_old_orders
    get_size_of_history_range               get_old_movement_data   get_order_list
    process_ec_export_orders                prepare_order_insert    get_item_value
    process_em_export_orders                calculate_item_value    import_ec_orders
    refresh_orders_for_item                 process_orders_sim      get_old_volume_data
    fill_missing_value_data                 try_to_get_item_values
    make_history_days_unique
);


sub try_to_get_item_values {
    my ( $c, $item_id, $region_id, $no_value_item_list ) = @_;

    my $item_data = $c->get_item_value( $item_id, $region_id, 0 );
    return $item_data if $item_data;

    return if !$no_value_item_list;

    push @{$no_value_item_list}, $item_id;
    return;
}

sub get_item_value {
    my ($c, $id, $region, $old ) = @_;

    my $query = $c->def_pb->fetch( 'get_item_value' );

    return $c->dbh->selectrow_hashref( $query, undef, $id, $region, $old );
}

sub refresh_orders_for_item {
    my ($c, $typeid, $regionid ) = @_;

    my $query = 'select * from emo_exports where typeid = ? and regionid = ? and "old"=0 order by reportedtime asc';
    my @exports = @{ $c->dbh->selectall_arrayref( $query, {Slice=>{}}, $typeid, $regionid ) };
    return if !@exports;

    my %exp_processors = (
        ec => \&process_ec_export_orders,
        em => \&process_em_export_orders,
        hi => \&process_em_export_orders,
    );

    my @generated_values;

    for ( @exports ) {
        next if !$exp_processors{$_->{source}};
        my $value = $exp_processors{$_->{source}}->( $c, $_ );
        push @generated_values, $value;
    }

    my $value_data = flatten_hashes( @generated_values );

    $c->fill_missing_value_data( $value_data );

    $c->insert_item_value_data( $value_data );

    $c->dbh->do( "UPDATE emo_exports SET \"old\"=1 WHERE typeid=? AND regionid = ?", undef, $typeid, $regionid );

    return;
}

sub fill_missing_value_data {
    my ( $c, $value ) = @_;

    if ( !defined $value->{move} )  {
        my $market_movement = $c->get_old_movement_data( $value->{typeid}, $value->{region} );
        $value->{move} = $market_movement;
    }

    if ( !defined $value->{sell_vol} or !defined $value->{buy_vol} )  {
        my ( $sell_vol, $buy_vol ) = $c->get_old_volume_data( $value->{typeid}, $value->{region} );
        $value->{sell_vol} = $sell_vol;
        $value->{buy_vol} = $buy_vol;
    }

    return;
}

sub flatten_hashes {
    my ( @hashes ) = @_;
    my %target;

    for my $hash ( @hashes ) {
        $target{$_} = $hash->{$_} for keys %{$hash};
    }

    return \%target;
}

sub process_ec_export_orders {
    my ($c, $export ) = @_;

    $c->import_ec_orders( $export );
    my $value = $c->calculate_item_value( $export->{typeid}, $export->{regionid} );

    return $value;
}

sub import_ec_orders {
    my ($c, $export ) = @_;

    $c->dbh->do( "DELETE FROM emo_item_orders WHERE typeid=? AND region_id = ?", undef, $export->{typeid}, $export->{regionid} );

    my @orders = split/\n/, $export->{content};

    my $sth = $c->prepare_order_insert;

    $c->dbh->do( "BEGIN;" );

    for ( @orders ) {
        my @order = split ' , ', $_;

        die "Market Order Input Error:\n\n$export->{content}\n\n" unless defined $order[bid] and ($order[bid] == 0 or $order[bid] == 1);

        $order[duration] =~ s/:00:00:00.00//;
        $order[duration] =~ s/ days*, 0:00:00//;
        $order[issued] =~ s/\.\d+$//;

        my $expired = DateTime::Format::MySQL->parse_datetime( $order[issued] );
        $expired->add( days => $order[duration] );
        $expired = DateTime::Format::MySQL->format_datetime( $expired );

        $sth->execute(
            $export->{typeid}, $order[bid], $export->{regionid}, $order[volremain],
            $order[stationid], $order[price], $order[duration], $order[issued],
            $expired
        );
    }

    $c->dbh->do( "COMMIT;" );

    return;
}

sub process_em_export_orders {
    my ($c, $export ) = @_;

    my $report = from_json( $export->{content} );

    my %value_data = (
        typeid => $export->{typeid},
        region => $export->{regionid},
        sell_price => $report->{sell}{simulated},
        buy_price => $report->{buy}{simulated},
    );

    my $market_movement = $c->calculate_market_movement_from_report( $report );
    $value_data{move} = $market_movement if defined $market_movement;

    return \%value_data;
}

sub get_old_volume_data {
    my ($c, $typeid, $regionid ) = @_;

    my $query = "
        SELECT sell_vol, buy_vol
        FROM emo_item_value_cache
        WHERE
            typeid = ?
            AND region = ?
            AND move != -1
        ORDER BY created DESC
        LIMIT 1
    ";
    my ( $sell_vol, $buy_vol ) = $c->dbh->selectrow_array( $query, undef, $typeid, $regionid );

    $sell_vol ||= 0;
    $buy_vol ||= 0;

    return ( $sell_vol, $buy_vol );
}

sub prepare_order_insert {
    my ($c) = @_;
    my $query = $c->def_pb->fetch( 'insert_into_order_table' );
    return $c->dbh->prepare( $query );
}

sub calculate_market_movement_from_report {
    my ( $c, $report ) = @_;

    return if !$report->{history_reference_time} or !$report->{history};

    my @history = @{ $report->{history} };
    return 0 if !@history or !$history[0];

    $c->make_history_days_unique( $report );

    my $days = $c->get_size_of_history_range( $report );

    my @averages = map { ( $_->{amount} || $_->{movement} ) / $days } @history;

    my $average_movement = 0;
    $average_movement += $_ for @averages;

    return $average_movement;
}

sub make_history_days_unique {
    my ( $c, $report ) = @_;

    my @history = @{ $report->{history} };
    my @unique_history;
    my %present_dates;

    for ( @history ) {
        next if $present_dates{$_->{date}};
        $present_dates{$_->{date}} = 1;
        push @unique_history, $_;
    }

    $report->{history} = \@unique_history;

    return;
}

sub get_old_movement_data {
    my ($c, $typeid, $regionid ) = @_;

    my $query = "
        SELECT move
        FROM emo_item_value_cache
        WHERE
            typeid = ?
            AND region = ?
            AND move != -1
        ORDER BY created DESC
        LIMIT 1
    ";
    my $movement = $c->dbh->selectrow_array( $query, undef, $typeid, $regionid );

    return -1 if !$movement;
    return $movement;
}

sub insert_item_value_data {
    my ($c, $value_data ) = @_;

    my (@keys,@values);

    for my $key ( keys %{ $value_data } ) {
        push @keys, $key;
        push @values, $value_data->{$key};
    }

    my $key_string = join( ',', @keys );
    my $placeholder_string = join( ',', ('?') x @keys );

    my $query = $c->def_pb->fetch( 'insert_item_value_data', { keys => $key_string, placeholders => $placeholder_string } );

    $c->dbh->do($query, undef, @values );

    return;
}

sub get_size_of_history_range {
    my ( $c, $report ) = @_;

    my @history = @{ $report->{history} };

    if ( $report->{history_reference_time} =~ m/ / ) {
        $report->{history_reference_time} =~ s/ /T/;
        $report->{history_reference_time} .= '+00:00';
    }

    my $report_dt = DateTime::Format::W3CDTF->parse_datetime( $report->{history_reference_time} );
    my $last_date = $history[$#history]{date} || $history[$#history]{content};
    my $first_dt = string_to_dt( $last_date );

    my $days = $report_dt->delta_days( $first_dt )->{days} - 2;

    $days = 90 if $days < 90;

    return $days;
}

sub calculate_item_value {
    my ( $c, $id, $region ) = @_;

    my %value_data = (
        typeid => $id,
        region => $region,
    );

    my @order_types = ( { bid=>0, name=>'sell_', }, { bid=>1, name=>'buy_', } );

    for my $type ( @order_types ) {
        $type->{orders} = $c->get_order_list( $id, $region, $type->{bid});

        next if !@{ $type->{orders} };

        my $summary = $c->process_orders_sim( $type->{orders} );

        $value_data{"$type->{name}$_"} = $summary->{$_} for keys %{ $summary };
    }

    return \%value_data;
}

sub get_order_list {
    my ($c, $id, $region, $bid) = @_;

    my %cfg = $c->cfg;

    $region = join( ',', @{$c->{cfg}{all_regions}} ) if $region eq 'all';
    $region = join( ',', @{$c->{cfg}{empire_regions}} ) if $region eq 'empire';

    my $query = $c->def_pb->fetch( 'get_order_list', { region => $region } );

    my $order_ref = $c->dbh->selectall_arrayref( $query, {Slice=>{}}, $bid, $id );
    my @orders = @{ $order_ref };
    @orders = reverse @orders if $bid;

    return \@orders;
}

sub process_orders_sim {
    my ( $c, $orders ) = @_;

    my $volume = 0;
    $volume += $_->{vol_remain} for @{ $orders };

    my $volume_limit = ceil( $volume * 0.05 );

    my %value_data;
    $value_data{vol} = 0;
    for my $order ( @{ $orders } ) {
        my $insert = $order->{vol_remain};

        # if this insert would go over the limit, set it to fill exactly to the limit
        if ( $insert + $value_data{vol} >= $volume_limit ) {
            $insert = $volume_limit;
            $insert -= $value_data{vol};
        }

        $value_data{vol} += $insert;
        $value_data{price} += $order->{price} * $insert;

        last if( $value_data{vol} >= $volume_limit );
    }
    $value_data{price} /= $value_data{vol};

    return \%value_data;
}

1;
