package Games::EveOnline::MarketOrders;

$|=1;
use lib '../..';

use base 'Games::EveOnline::AssetManager::CABase';

use Games::EveOnline::MarketOrders::Tools;
use Games::EveOnline::MarketOrders::Setup qw(
    setup_phrasebooks   setup           setup_tt    def_pb
    cgiapp_postrun      init_tables     table_pb
);
use Games::EveOnline::MarketOrders::ECUpdate qw(
    get_newest_dump_filenames   download_dumps  process_ec_dump_file    unpack_dump
);
use Games::EveOnline::MarketOrders::EMUpdate qw(
    mark_history_times          drop_cold_caches    download_em_xml     get_em_price_data
    get_price_sets_from_em      sub_divide_array    prepare_em_urls     get_em_history_data
    download_em_data            compact_em_data     parse_em_json
    mark_prices_for_filling     get_history_sets_from_em
);
use Games::EveOnline::MarketOrders::CacheUpdate qw(
    process_cache_export_file
);
use Games::EveOnline::MarketOrders::ItemData qw(
    calculate_market_movement_from_report   insert_item_value_data  expire_old_orders
    get_size_of_history_range               get_old_movement_data   get_order_list
    process_ec_export_orders                prepare_order_insert    get_item_value
    process_em_export_orders                calculate_item_value    import_ec_orders
    refresh_orders_for_item                 process_orders_sim      get_old_volume_data
    fill_missing_value_data                 try_to_get_item_values
    make_history_days_unique
);
use Games::EveOnline::MarketOrders::ReportInsert qw(
    finalize_old_batch      report_is_older_than_db     compare_report_size_with_db
    expire_item_value_data  insert_market_export
);
use Games::EveOnline::MarketOrders::Helpers qw(
    get_emo_status      get_work_lock       set_key_value
);

use List::Util qw( shuffle );

my @configured_regions = qw(
    10000002 10000032 10000030 10000067 10000033 10000047 10000001
    10000043 10000065 10000020 10000042 10000016 10000064 10000068
);

sub home : Default {
    my ( $c ) = @_;

    my $status = $c->get_emo_status;
    $c->set_key_value( 'updater_status', 'idle' ) if $status eq 'unknown';

    return $c->tt_process;
}

sub item_data : Runmode {
    my ( $c ) = @_;

    my %q = $c->query->Vars;
    $q{id} ||= '25910';
    $q{region} ||= 10000002;

    my @id_list = split /,/, $q{id};
    my $no_value_items = [];

    my @output = map $c->try_to_get_item_values( $_, $q{region}, $no_value_items ), shuffle @id_list;

    $c->refresh_orders_for_item( $_, $q{region} ) for shuffle @{$no_value_items};

    push @output, map $c->try_to_get_item_values( $_, $q{region} ), shuffle @{$no_value_items};

    my $output =  to_json( \@output, { pretty => 1 } );
    cluck "no output for:\n".Dumper( \@id_list, \%q, \!@output) if !$output;

    return $output;
}

sub check_old : Runmode {
    my $c = shift;

    my %q = $c->query->Vars;

    $q{id} ||= '34,35,36,37';

    die "No hacking!" if $q{id} =~ /[^\d,]/;

    my $statement = "SELECT id FROM emo_item_value_cache WHERE id IN ( $q{id} ) AND \"old\" = 1 ";
    my $ary_ref = $c->dbh->selectcol_arrayref($statement);

    my $output = join ',', @{ $ary_ref };

    return $output;
}

sub market_update : Runmode {
    my ( $c ) = @_;

    return $c->tt_process;
}

sub perform_market_update : Runmode {
    my ($c) = @_;

    $c->header_type( 'none' );
    print $c->query->header(-nph=>1);
    say ${ $c->tt_process( ) };

    my $lock_id = "working_em_prices";

    if ( !$c->get_work_lock( $lock_id ) ) {
        say "Update in progress and other process already waiting. Aborting.<br>";
        return;
    }

    $c->set_key_value( 'updater_start', time );
    $c->set_key_value( 'updater_status', 'working' );

    my $new_prices = 0;
    $new_prices += $c->get_em_price_data( $_ ) for @configured_regions;

    say "<br><br><br><br>UPDATE DONE!<br><br><br><br><br>";
    say "</span></body></html>";

    $c->set_key_value( 'updater_end', time );
    $c->set_key_value( 'updater_status', "idle ($new_prices new prices last run)" );

    unlock( $lock_id );

    return;
}

sub perform_history_update : Runmode {
    my ($c) = @_;

    $c->header_type( 'none' );
    print $c->query->header(-nph=>1);
    say ${ $c->tt_process( ) };

    my $lock_id = "working_em_history";

    if ( !$c->get_work_lock( $lock_id ) ) {
        say "Update in progress and other process already waiting. Aborting.<br>";
        return;
    }

    $c->set_key_value( 'history_updater_start', time );
    $c->set_key_value( 'history_updater_status', 'working' );

    my $new_prices = 0;
    $new_prices += $c->get_em_history_data( $_ ) for @configured_regions;

    say "<br><br><br><br>UPDATE DONE!<br><br><br><br><br>";
    say "</span></body></html>";

    $c->set_key_value( 'history_updater_end', time );
    $c->set_key_value( 'history_updater_status', "idle ($new_prices new prices last run)" );

    unlock( $lock_id );

    return;
}

sub perform_ec_update : Runmode {
    my ($c) = @_;

    $c->header_type( 'none' );
    print $c->query->header(-nph=>1);
    say ${ $c->tt_process( ) };

    my $lock_id = "working_ec";

    if ( !$c->get_work_lock( $lock_id ) ) {
        say "Update in progress and other process already waiting. Aborting.<br>";
        return;
    }

    say "<br><br>Identifying new files.<br><br>";

    my @files = $c->get_newest_dump_filenames;
    $c->download_dumps( \@files );
    say "<br><br>Processing ". @files ." dump files.<br><br>";

    my $new_prices = 0;
    $new_prices += $c->process_ec_dump_file( $_ ) for @files;

    say "<br><br><br><br>UPDATE DONE!<br><br><br><br><br>";
    say "</span></body></html>";

    unlock( $lock_id );

    return;
}

1;
