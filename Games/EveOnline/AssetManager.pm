package Games::EveOnline::AssetManager;
use lib '../..';
use base 'Games::EveOnline::AssetManager::CABase';
$|=1;
use Games::EveOnline::AssetManager::Tools;

use List::Util qw( shuffle reduce min max );
use Plot;

memoize( 'expiry_to_timestamp' );

my %research_types = (
    1 => 'unresearched',
    2 => 'in_progress',
    3 => 'done',
);

my %cache;
my %cfg;

my $random_colors = [ [ 198, 171, 32 ], [ 147, 63, 203 ], [ 61, 220, 254 ], [ 184, 39, 173 ], [ 104, 133, 28 ], [ 224, 212, 2 ], [ 14, 92, 144 ], [ 213, 25, 112 ], [ 31, 212, 194 ], [ 26, 71, 224 ], [ 235, 18, 229 ], [ 241, 174, 81 ], [ 35, 178, 78 ], [ 150, 110, 1 ], [ 68, 168, 220 ], [ 218, 87, 48 ], [ 12, 211, 27 ], [ 115, 52, 153 ], [ 141, 233, 35 ], [ 66, 234, 17 ], [ 19, 125, 242 ], [ 171, 18, 248 ], [ 243, 132, 24 ], [ 13, 165, 120 ], [ 153, 184, 3 ], [ 165, 71, 31 ], [ 126, 6, 191 ], [ 99, 75, 9 ], [ 3, 251, 113 ], [ 194, 10, 3 ], [ 27, 100, 17 ], [ 251, 3, 156 ], [ 100, 207, 68 ], [ 58, 141, 4 ], [ 208, 74, 217 ], [ 61, 107, 201 ], [ 12, 116, 64 ], [ 53, 240, 135 ], [ 239, 9, 50 ], [ 88, 36, 240 ], [ 178, 207, 67 ], [ 247, 73, 160 ], [ 120, 82, 241 ], [ 158, 10, 77 ], [ 1, 166, 191 ], [ 252, 53, 85 ], [ 151, 26, 137 ], [ 177, 130, 51 ], [ 86, 250, 94 ], [ 32, 253, 45 ], [ 85, 249, 175 ], [ 38, 124, 108 ], [ 3, 231, 236 ], [ 134, 171, 57 ], [ 48, 142, 164 ], [ 169, 56, 104 ], [ 88, 137, 252 ], [ 227, 58, 5 ], [ 188, 37, 52 ], [ 254, 72, 252 ], [ 71, 174, 39 ], [ 254, 205, 44 ], [ 65, 192, 118 ], [ 113, 251, 2 ], [ 141, 43, 5 ], [ 192, 0, 210 ], [ 0, 147, 23 ], [ 77, 55, 189 ] ];

my @configured_regions = qw(
    10000002 10000032 10000030 10000067 10000033 10000047 10000001 10000037
    10000043 10000065 10000020 10000042 10000016 10000064 10000068
);

my %configured_regions = map { $_ => 1 } @configured_regions;

sub setup {
    my ( $c ) = @_;

    %cfg = $c->cfg if !keys %cfg;

    $c->{cache} ||= \%cache;
    $c->{cfg} ||= \%cfg;

    $ENV{DEBUG_MODE} = $c->{cfg}{debug_mode};
    $ENV{HTML_TEMPLATE_ROOT} = $c->{cfg}{template_root};

    $XML::Simple::PREFERRED_PARSER = 'XML::Parser';

    $c->setup_tt;

    $c->mode_param('task');
    $c->dbh_config( $c->{cfg}{db_source}, $c->{cfg}{db_user}, $c->{cfg}{db_password}, {AutoCommit=>1,RaiseError=>1});

    my %config = (
        DRIVER => [ 'DBI',
            DBH         => $c->dbh,
            TABLE       => 'eaa_users',
            CONSTRAINTS => { 'eaa_users.email' => '__CREDENTIAL_1__' },
            COLUMNS     => { 'crypt:password'  => '__CREDENTIAL_2__' },
        ],
        STORE          => 'Session',
        LOGOUT_RUNMODE => 'home',
        LOGIN_RUNMODE  => 'login',
    );
    $c->authen->config(%config);
    $c->authen->protected_runmodes('two');

    $c->log_config( LOG_DISPATCH_MODULES => [ {
        module => 'Log::Dispatch::File',
        name => 'debug',
        filename => './assets_debug.log',
        min_level => 'debug',
        mode => '>>',
        append_newline => 1,
    } ] );

    $c->setup_phrasebooks;
    $c->init_tables;

    $c->run_modes({
        'login'  => 'login',
        'list_regions'  => 'list_regions',
    });

    return;
}

sub cgiapp_prerun {
    my ( $c ) = @_;

    $c->session_config( CGI_SESSION_OPTIONS => [
        "driver:PostgreSQL",
        $c->query,
        { TableName => 'eaa_sessions', Handle => $c->dbh, ColumnType => "binary" }
    ] );

    return;
}

sub setup_tt {
    my ( $c ) = @_;

    if ( $c->{cache}{__TT_CONFIG} and $c->{cache}{__TT_OBJECT} ) {

        $c->{__TT_CONFIG} = $c->{cache}{__TT_CONFIG};
        $c->{__TT_OBJECT} = $c->{cache}{__TT_OBJECT};

        return;
    }

    $c->tt_config( TEMPLATE_OPTIONS => { RECURSION => 1 } ); # has to be done before any other call to TT

    extend_template_include_paths($c);

    $c->{cache}{__TT_CONFIG} = $c->{__TT_CONFIG};
    $c->{cache}{__TT_OBJECT} = $c->{__TT_OBJECT};

    return;
}

sub setup_phrasebooks {
    my ( $c ) = @_;

    if ( $c->{cache}{__PHRASEBOOK} ) {
        $c->{__PHRASEBOOK} = $c->{cache}{__PHRASEBOOK};
        return;
    }

    my $path = $c->tt_include_path;
    my $dir = @{ $path }[1];

    $c->config_phrasebook(
        {
            __DEFAULT__ => {
                class  => 'Plain',
                loader => 'XML',
                file   => $dir.'Queries.xml',
            },
            tables => {
                class  => 'Plain',
                loader => 'XML',
                file   => $dir.'Tables.xml',
            }
        }
    );

    $c->{cache}{__PHRASEBOOK} = $c->{__PHRASEBOOK};

    return;
}

# check for HTML errors
sub cgiapp_postrun {
    my ($self, $o) = @_;

    lint_html($o) if $ENV{CGI_APP_DEBUG};
    #add_asset_update_time($o);
}


sub home : Default {
    my ( $c ) = @_;

    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    my %params = (
        emo_status => $emo_status,
        %times
    );

    return $c->tt_process( \%params );
}

sub login : Runmode {
    my ( $c ) = @_;

    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    my $box = $c->login_box;

    my %params = (
        emo_status => $emo_status,
        box => $box,
        %times
    );

    return $c->tt_process( \%params );
}

sub one : Runmode {
    my ( $c ) = @_;

    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    $c->authen->logout;

    my %params = (
        emo_status => $emo_status,
        %times
    );

    return $c->tt_process( \%params );
}

sub two : Runmode {
    my ( $c ) = @_;

    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    my %params = (
        emo_status => $emo_status,
        user_name => $c->authen->username,
        %times
    );

    return $c->tt_process( \%params );
}

sub owned {
    my ( $c ) = @_;

    return {} if !$c->{sess}{owner};

    $c->{owned} ||= $c->owned_data;

    return $c->{owned};
}

sub owned_data {
    return {
        27914 => { me =>   0, pe =>  0, r => 1 }, # Bomb Launcher I             target: 193
        2046 =>  { me =>   0, pe =>  0, r => 1 }, # damage control I             target: 193
        26004 => { me =>   0, pe =>  0, r => 1 }, # Large Algid Hybrid              target: 19
        26076 => { me =>   0, pe =>  0, r => 1 }, # Large Anti-EM Screen Reinforcer I target: 15
        25906 => { me =>   0, pe =>  0, r => 1 }, # Large Core Defence Capacitor Safeguard I    target: 12
        26086 => { me =>   0, pe =>  0, r => 1 }, # Large Core Defence Operational Solidifier I    target: 12
        25972 => { me =>   0, pe =>  0, r => 1 }, # Large Energy Locus              target: 17
        26002 => { me =>   0, pe =>  0, r => 1 }, # Large Hybrid Metastasis Adjuster I          target: 18
        26038 => { me =>   0, pe =>  0, r => 1 }, # Large Projectile Ambit Extension I          target: 18
        26040 => { me =>   0, pe =>  0, r => 1 }, # Large Projectile Locus Coordinator I        target: 17
        26020 => { me =>   0, pe =>  0, r => 1 }, # Large Warhead Rigor Catalyst I        target: 17
        31528 => { me =>   0, pe =>  0, r => 1 }, # Medium Hybrid Burst Aerator I
        31288 => { me =>   0, pe =>  0, r => 1 }, # Medium Particle Dispersion Augmentor I
        31073 => { me =>   0, pe =>  0, r => 1 }, # Medium Remote Repair Augmentor I     target: 4
        31324 => { me =>   0, pe =>  0, r => 1 }, # Medium Targeting System Subcontroller I     target: 4
        11563 => { me =>   0, pe =>  0, r => 1 }, # Micro Auxiliary Power Core I
        29007 => { me =>   0, pe =>  0, r => 1 }, # Tracking Speed Disruption

        1944 =>  { me =>  13, pe =>  0, r => 3 }, # bestower
        30028 => { me =>   5, pe =>  0, r => 3 }, # Combat Scanner Probe I
        17938 => { me =>  19, pe =>  0, r => 3 }, # core probe launcher
        650 =>   { me =>  11, pe =>  0, r => 3 }, # iteron
        655 =>   { me =>   8, pe => 12, r => 3 }, # iteron mark III
        3663 =>  { me =>   8, pe =>  0, r => 3 }, # large hull repairer I
        25920 => { me =>  21, pe =>  0, r => 3 }, # large sentry damage
        25894 => { me =>  13, pe => 20, r => 3 }, # large trimark armor
        31718 => { me =>   3, pe =>  0, r => 3 }, # Medium Anti-EM Screen Reinforcer I
        31754 => { me =>   4, pe =>  0, r => 3 }, # Medium Anti-Thermal Screen Reinforcer I
        31588 => { me =>   4, pe =>  0, r => 3 }, # medium bay loading
        31790 => { me =>   3, pe =>  0, r => 3 }, # Medium Core Defence Field Extender I
        31155 => { me =>   3, pe =>  0, r => 3 }, # Medium Low Friction Nozzle Joints I
        31179 => { me =>   4, pe =>  0, r => 3 }, # Medium Polycarbon Engine Housing I
        31009 => { me =>   0, pe =>  0, r => 3 }, # Small Anti-Explosive Pump I
        31752 => { me =>   0, pe =>  0, r => 3 }, # Small Anti-Thermal Screen Reinforcer I
        31105 => { me =>   0, pe =>  0, r => 3 }, # Small Auxiliary Thrusters I
        31586 => { me =>   1, pe =>  0, r => 3 }, # small bay loading
        31370 => { me =>   0, pe =>  0, r => 3 }, # small capacitor control
        31117 => { me =>   0, pe =>  0, r => 3 }, # Small Cargohold Optimization I
        31788 => { me =>   0, pe =>  0, r => 3 }, # Small Core Defence Field Extender I
        31430 => { me =>   0, pe =>  0, r => 3 }, # Small Energy Ambit Extension I
        31213 => { me =>   0, pe =>  0, r => 3 }, # small gravity capacitor
        31526 => { me =>   0, pe =>  0, r => 3 }, # Small Hybrid Burst Aerator
        31538 => { me =>   0, pe =>  0, r => 3 }, # Small Hybrid Coll
        31159 => { me =>   0, pe =>  0, r => 3 }, # Small Hyperspatial Velocity
        31226 => { me =>   0, pe =>  0, r => 3 }, # Small Liquid Cooled Electronics I
        31153 => { me =>   0, pe =>  0, r => 3 }, # Small Low Friction Nozzle Joints I
        31177 => { me =>   0, pe =>  0, r => 3 }, # Small Polycarbon Engine Housing I
        31680 => { me =>   0, pe =>  0, r => 3 }, # Small Projectile Collision Accelerator I
        31668 => { me =>   0, pe =>  0, r => 3 }, # Small Projectile Burst Aerator I
        31083 => { me =>   0, pe =>  0, r => 3 }, # Small Salvage Tackle I
        31322 => { me =>   0, pe =>  0, r => 3 }, # Small Targeting System Subcontroller I
        24348 => { me =>  30, pe =>  0, r => 3 }, # small tractor beam I
        31620 => { me =>   0, pe =>  0, r => 3 }, # Small Warhead Calefaction
        17482 => { me =>  12, pe => 20, r => 3 }, # strip miner I

        26042 => { me =>   0, pe =>  0, r => 2 }, # Large Projectile Metastasis Adjuster I target: 18
        26106 => { me =>   0, pe =>  0, r => 2 }, # Large Particle Dispersion Augmentor I       target: 15
        26108 => { me =>   0, pe =>  0, r => 2 }, # Large Particle Dispersion Projector I       target: 17
        26082 => { me =>   0, pe =>  0, r => 2 }, # Large Anti-Thermal Screen Reinforcer I      target: 17
        25900 => { me =>   0, pe =>  0, r => 2 }, # Large Remote Repair Augmentor I       target: 18
        31600 => { me =>   0, pe =>  0, r => 2 }, # Medium Hydraulic Bay Thrusters I
        31300 => { me =>   0, pe =>  0, r => 2 }, # Medium Particle Dispersion Projector I      target: 4
        200 =>   { me =>   0, pe =>  0, r => 2 }, # phased plasma l               target: 277
    };
}

sub list_regions : Runmode {
    my ( $c ) = @_;
    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    my ( $hit_count, $all_hits ) = $c->get_hit_data;

    my @regions = shuffle @{ $c->get_region_list };
    for ( @regions ) {
        next if !$_->{configured};
        my $key = "/list/$_->{path_name}";
        my $hits = $hit_count->{$key}{count} || 0;
        $_->{competition} = sprintf "%.2f", 100 * $hits / $all_hits;

        my $value = $c->get_latest_region_value( $_->{regionid} );
        $value = isk_shorten( $value ) if $value;
        $_->{value} = $value || '?';
        $_->{value} =~ s/\.\d+//;
    }

    my %params = (
        region_list => \@regions,
        emo_status => $emo_status,
        %times,
    );

    return $c->tt_process( \%params );
}

sub get_hit_data {
    my ( $c ) = @_;

    my $week_ago = time - 604800;
    my $hit_count = $c->dbh->selectall_hashref(
        "SELECT count(path_info) as count, path_info FROM eaa_profile_log WHERE log_time > ? AND path_info LIKE '/list/%' GROUP BY path_info",
        'path_info', undef, $week_ago
    );

    my $all_hits = 0;
    $all_hits += $_->{count} for values %{$hit_count};
    $all_hits ||= 1;

    return ( $hit_count, $all_hits );
}

sub list : Path(list/) {
    my ( $c ) = @_;

    $c->update_session( qw {
        container_sort_method_1     minimum_margin  accounting      broker_fee
        production_slots            minimum_profit  maximum_roi     owner
        industry_skill              prod_eff_level  bp_mat_level
        column_excess
    });

    $c->{sess}{$_} =~ s/[^-\d\.]//g for qw( broker_fee accounting minimum_margin );

    my( $region_name ) = $c->action_args;
    $region_name ||= '';
    my @regions = @{ $c->get_region_list };
    my ( $requested_region ) = grep { $_->{path_name} eq $region_name } @regions;
    $c->{sess}{regions} = $requested_region->{regionid} if $requested_region;

    return $c->forward( 'list_regions' ) if !$requested_region;

    my @ids;
    push @ids, $c->query_vars->{id} if $c->query_vars->{id};

    my ( $assets, $non_sold_items ) = $c->get_asset_list( @ids );

    $c->record_region_value( $assets, $requested_region );

    my $time;# = get_asset_update_time();

    for my $region ( @regions ) {
        $region->{select} = 'selected' if $c->{sess}{regions} =~ /$region->{regionid}/;
    }

    my @sort_list = (
        { val => 'none', name => ' ' },
        { val => 'itemname', name => 'Name' },
        { val => 'quantity', name => 'Quantity' },
        { val => 'value.buy_vol', name => 'Buy Order Volume' },
        { val => 'value.buy_price', name => 'Buy Order Price' },
        { val => 'value.sell_vol', name => 'Sell Order Volume' },
        { val => 'value.sell_price', name => 'Sell Order Price' },
        { val => 'value.repro_price', name => 'Reprocess Price' },
        { val => 'suggestion', name => 'Suggestion' },
        { val => 'value.margin_percentage', name => 'Margin %' },
        { val => 'value.margin_absolute', name => 'Margin Absolute' },
    );
    for my $sort ( @sort_list ) {
        for ( qw( _1 _2 _3 ) ) {
            next if !$c->{sess}{"container_sort_method$_"};
            $sort->{"select$_"} = ' selected' if $c->{sess}{"container_sort_method$_"} eq $sort->{val};
        }
    }

    my %times = $c->get_price_update_times;
    my $emo_status = $c->get_emo_status;

    my %params = (
        contents => $assets,
        #query => Dumper( $assets ),
        time => $time,
        region_list => \@regions,
        shorten => \&shorten,
        shorten_and_multiply => \&shorten_and_multiply,
        truncate => \&trunc,
        sort_list => \@sort_list,
        emo_status => $emo_status,
        non_sold_items => $non_sold_items,
        %times
    );

    return $c->tt_process( \%params );
}

sub record_region_value {
    my ( $c, $assets, $requested_region ) = @_;

    $c->update_graphs if !-e 'image_value.png' or $^O eq 'MSWin32';

    my %cfg = %{$c->{sess}};
    return if $cfg{accounting} != 3;
    return if $cfg{industry_skill} != 5;
    return if $cfg{prod_eff_level} != 5;
    return if $cfg{broker_fee} != 0.39;
    return if $cfg{production_slots} != 1;
    return if $cfg{bp_mat_level} != 0;
    return if $cfg{minimum_profit} != 1500000;
    return if $cfg{maximum_roi} != 365;
    return if $cfg{minimum_margin} != 0;

    my @items = @{ $assets->[0]{contents} };

    my $value = reduce { $a + $b->{daily_profit_num} } 0, @items;
    my $old_value = $c->get_latest_region_value( $requested_region->{regionid} );

    return if defined $old_value and defined $value and $old_value eq $value;

    my $competition = $c->get_region_competition( $requested_region );

    my $query = "INSERT INTO eaa_region_value ( regionid, value, competition, created, timestamp ) VALUES ( ?, ?, ?, UTC_TIMESTAMP(), ? )";
    $c->dbh->do($query, undef, $requested_region->{regionid}, $value, $competition, time );

    $c->update_graphs;

    return;
}

sub update_graphs {
    my ( $c ) = @_;

    my @data = $c->get_data;
    $c->summarize_xy_data($_) for @data;

    my $html = '';
    for my $region ( @data ) {
        my $color = hex_to_string( $region->{color} );
        $html .= "<span style='color: $color;'>&bull;$region->{name}</span><br />";
    }
    write_file "legend.html", {binmode => ':raw'},  $html;

    $c->chart_plot( $_, 1, @data ) for qw( value competition adjusted_value );
    $c->chart_plot( $_, 0, @data ) for qw( value competition adjusted_value );

    return;
}

sub get_data {
    my ( $c ) = @_;

    my $window_start = time - 60*60*24*30;
    my $query = "select * from eaa_region_value where timestamp > ? order by timestamp";
    my @rows = @{ $c->dbh->selectall_arrayref( $query, {Slice=>{}}, $window_start ) };

    delete $c->{$_} for qw( graph_x_offset graph_x_max );

    my %regions;
    for ( @rows ) {
        $c->{graph_x_offset} ||= $_->{timestamp};
        $_->{timestamp} -= $c->{graph_x_offset};
        $_->{value} /= 1_000_000;
        $_->{value} = int $_->{value};

        push @{$regions{$_->{regionid}}->{rows}}, $_;
        $regions{$_->{regionid}}->{id} = $_->{regionid};
    }
    $c->{graph_x_offset} ||= time - 1;

    my @rand_cols = shuffle @{$random_colors};
    $_->{color} = pop @rand_cols for values %regions;
    $_->{name} = $c->get_region_name( $_ ) for values %regions;

    $c->{graph_x_max} = time - $c->{graph_x_offset};

    return values %regions;
}

sub create_list_of_random_cols {
    my ( $c ) = @_;

    $c->{created_colors_cache} = [];
    while ( @{$c->{created_colors_cache}} < 68) { $c->random_color_hex(); }
    use Data::Dumper;
    print "\n\n\n".Dumper($c->{created_colors_cache});

    return;
}

sub get_region_name {
    my ( $c, $region ) = @_;

    my $name = $c->dbh->selectrow_array("select regionname from mapregions where regionid = ?", undef, $region->{id} );

    return $name;
}

sub summarize_xy_data {
    my ( $c, $region ) = @_;

    for ( 0 .. $#{ $region->{rows} } ) {
        my $tuple = $region->{rows}[$_];
        my $x = $tuple->{timestamp};

        my %y;
        $y{value} = $tuple->{value};
        $y{competition} = $tuple->{competition};
        $y{adjusted_value} = $tuple->{value} / max( 1, $tuple->{competition} ) if $tuple->{competition};
        $y{adjusted_value} ||= 0;

        push @{$region->{points_value}}, [ $x, $y{value} ];
        push @{$region->{points_competition}}, [ $x, $y{competition} ];
        push @{$region->{points_adjusted_value}}, [ $x, $y{adjusted_value} ];
    }

    return;
}

sub chart_plot {
    my ( $c, $target, $large, @data ) = @_;

    my ( $x, $y, $name ) = ( 600, 250, 'image_' );
    ( $x, $y, $name ) = ( 1280, 1024, 'image_large_' ) if $large;

    my $img = Plot->new( $x, $y );

    for my $region ( @data ) {
        my @dataset = map { @{$_} } @{$region->{"points_$target"}};
        $img->setData ( \@dataset, $region->{color} ) or die( $img->error() );
    }

    for my $region ( @data ) {
        my $color = hex_to_string( $region->{color} );
    }

    my %titles = (
        value => 'Cumulative possible daily profits',
        adjusted_value => 'Cumulative profits adjusted for competition',
        competition => 'Competition',
    );

    my %y_labels = (
        value => 'Mill ISK',
        adjusted_value => 'Mill ISK',
        competition => 'Percent',
    );

    my ($xmin, $ymin, $xmax, $ymax) = $img->getBounds();
    $img->{'_xmax'} = $c->{graph_x_max};
    $img->setGraphOptions ('horGraphOffset' => 40,
                            'vertGraphOffset' => 20,
                            'title' => $titles{$target},
                            'horAxisLabel' => 'Time',
                            'vertAxisLabel' => $y_labels{$target} );

    my $ticks = $c->get_time_ticks;
    $img->setGraphOptions ( 'xTickLabels' => $ticks ) or die ($img->error);

    write_file "$name$target.png", {binmode => ':raw'},  $img->draw;

    return;
}

sub get_time_ticks {
    my ( $c ) = @_;

    my $start = $c->{graph_x_offset};
    my $now_dt = DateTime->today;
    my %ticks;

    while( $now_dt->epoch > $start ) {
        my $index = $now_dt->epoch - $start;
        $ticks{$index} = $now_dt->ymd;
        $now_dt = $now_dt->subtract( days => 1 );
    }

    return \%ticks;
}

=cut
=cut



sub random_color_hex
{
    my ( $c ) = @_;

    my @hex;

    push( @hex, int rand 255 ) for ( 0 .. 2 );

    while ( !$c->is_colorful(@hex) ) {
        shift @hex;
        push @hex, int rand 255;
    }

    push @{ $c->{created_colors_cache} }, \@hex;

    return \@hex;
}

sub hex_to_string {
    my ( $hex ) = @_;
    my @hex = @{$hex};

    $_ = sprintf( "%02x", $_ ) for @hex;
    my $color = "\#" . $hex[0] . $hex[1] . $hex[2];

    return $color;
}

# function checks rgb colour against HSV constraints, returns 1 if it's sufficiently colourful, 0 if not
sub is_colorful
{
    my ( $c, @colours ) = @_;

    $_ /= 255 for (@colours);

    my $brightness = sqrt(
      $colours[0] * $colours[0] * .241 +
      $colours[1] * $colours[1] * .691 +
      $colours[2] * $colours[2] * .068);

    return 0 if $brightness > 0.85;
    return 0 if $brightness < 0.3;

    my $value 	   = max @colours;
    my $min        = min @colours;
    my $delta      = $value - $min;
    my $saturation = $delta / $value;

    return 0 if $saturation < 0.65;

    for my $ex ( @{ $c->{created_colors_cache} } ) {
        my $diff = 0;
        $diff += abs( $ex->[$_]/255 - $colours[$_] ) for 0..2;
        return 0 if $diff < .3;
    }

    return 1;
}

sub get_region_competition {
    my ( $c, $region ) = @_;

    my ( $hit_count, $all_hits ) = $c->get_hit_data;

    my $key = "/list/$region->{path_name}";
    my $hits = $hit_count->{$key}{count} || 1;
    my $competition = sprintf "%.2f", 100 * $hits / $all_hits;

    return $competition;
}

sub get_latest_region_value {
    my ( $c, $regionid ) = @_;

    my $query = "SELECT value FROM eaa_region_value WHERE regionid = ? ORDER BY created DESC LIMIT 1";
    my $value = $c->dbh->selectrow_array( $query, undef, $regionid );

    return $value;
}

sub get_region_list {
    my ( $c ) = @_;

    return clone $c->{cache}{regions} if $c->{cache}{regions};

    my @regions = values %{ $c->get_list( 'region_list', 'regionid' ) };
    @regions = sort { $a->{regionname} cmp $b->{regionname} } @regions;

    for ( @regions ) {
        $_->{path_name} = $_->{regionname};
        $_->{path_name} =~ s/ /_/g;
        $_->{configured} = $configured_regions{$_->{regionid}} || 0;
        $_->{regionname_html} = $_->{regionname};
        $_->{regionname_html} =~ s/ /&nbsp;/g;
        $_->{regionname_html} =~ s/-/&#8209;/g;
    }

    $c->{cache}{regions} = \@regions;

    return clone $c->{cache}{regions};
}

sub item : Runmode {
    my $c = shift;

    $c->update_session( qw {
        container_sort_method_1     minimum_margin  accounting      broker_fee
        production_slots            minimum_profit  maximum_roi     owner
        industry_skill              prod_eff_level  bp_mat_level    regions
        column_excess
    });

    $c->{sess}{$_} =~ s/[^\d\.]//g for qw( broker_fee accounting minimum_margin );

    my $type_id = $c->query_vars->{type_id};
    $type_id ||= 634;

    my $assets = $c->get_asset_list( $type_id );
    $assets = $assets->[0]{contents}[0];

    $assets->{bom} = [ sort { $b->{value}{sell_price} <=> $a->{value}{sell_price} } values( %{$assets->{bom}} ) ];
    for ( @{$assets->{bom}} ) {
        delete $_->{bom} if !$_->{bom};
        my $value = $_->{value};
        $value->{sell_price_batch} = isk_shorten( $value->{sell_price} );
        $value->{sell_price} /= $_->{quantity};
        $value->{sell_price} = shorten( $value->{sell_price} );
        $_->{quantity} = shorten( $_->{quantity} );
        $_->{quantity} =~ s/\.00//;
        $value->{sell_vol} = shorten( $value->{sell_vol} );
        $value->{sell_vol} =~ s/\.00//;
        $value->{move} = shorten( $value->{move} );
    }

    my $output = to_json( $assets, { pretty => 1 } );

    return $output;
}

sub get_price_update_times {
    my ( $c ) = @_;

    my $curr_min = DateTime->now->min;

    my $last = get_last_update_minute( $curr_min );
    my $time_to_prev = $curr_min - $last;
    my $time_to_next = $last + 15 - $curr_min;

    my %times = (
        time_to_prev_update => $time_to_prev,
        time_to_next_update => $time_to_next,
    );

    return %times;
}

sub get_last_update_minute {
    my ( $curr ) = @_;

    return  0 if $curr < 15;
    return 15 if $curr < 30;
    return 30 if $curr < 45;
    return 45;
}

sub trunc {
    return 45 if $_[0] < 45;
    return int $_[0];
}

sub get_asset_list {
    my ( $c, @items ) = @_;

    my $assets = $c->get_prod_item_list( @items );

    $c->collapse_duplicates( $assets );

    $c->extend_item_data( $assets );

    $c->mark_old_ids;

    $c->get_all_item_values;

    $c->fill_value_ids( $assets );

    $c->fill_missing_value_ids;

    ( $assets, my $non_sold_items ) = $c->separate_non_sold_items( $assets );

    $c->extend_value_data( $assets );

    $assets = $c->filter_asset_list( $assets ) if !@items;


    $c->{max_log} = logn( $c->{max_mult}, $c->{cfg}{log_scale} );
    $c->{normal_profit_range} = $c->calc_profit_log_range( 1 );
    $c->extend_profit_data( $assets );

    $assets = [{
        itemname => 'Assets',
        contents => $assets,
    }];

    my @sort_methods;
    push @sort_methods, $c->{sess}{container_sort_method_1} if $c->{sess}{container_sort_method_1};
    push @sort_methods, $c->{sess}{container_sort_method_2} if $c->{sess}{container_sort_method_2};
    push @sort_methods, $c->{sess}{container_sort_method_3} if $c->{sess}{container_sort_method_3};
    $c->sort_containers_by( $assets, @sort_methods );

    $c->prepare_assets_for_printing( $assets->[0]{contents} );

    return ( $assets, $non_sold_items ) if wantarray;
    return $assets;
}

sub separate_non_sold_items {
    my ( $c, $assets ) = @_;

    my ( @real_assets, @non_sold_items );

    for ( @{$assets} ) {
        my $id = $_->{typeid};
        my $target = \@real_assets;
        $target = \@non_sold_items if !$c->{caches}{item_values}{$id}{sell_price};
        push @{$target}, $_;
    }

    return ( \@real_assets, \@non_sold_items );
}

sub get_market_groups_to_skip {
    my ( $c ) = @_;

    my @to_skip = ( 493, 507..530 );
    push @to_skip, ( 812..821, 761..770, 782..791, 912..913, 1045..1048 ); # capitals
    push @to_skip, ( 1149 ); # invention
    push @to_skip, ( 1200 ); # survey probes

    my %to_skip = map { $_ , 1 } @to_skip;

    return %to_skip;
}

sub filter_prod_items_base {
    my ( $c, $item, $to_skip, $item_ids ) = @_;

    return if $item_ids and !$item_ids->{$item->{typeid}};

    my $market_group_id = $item->{marketgroupid};
    return if !$market_group_id; # can't be sold on market
    return if $to_skip->{$market_group_id};

    return if !$item->{blueprinttypeid}; # can't be built
    return if !$item->{bp_marketgroup_id}; # blueprint isn't sold on market
    return if $item->{techlevel} == 2;

    return $item;
}

sub extend_item_for_prod {
    my ( $c, $item ) = @_;

    my %hash = %{$item};
    $hash{quantity} = $hash{portionsize};
    $hash{locationid} = 60014917;

    $c->log->info( $hash{typeid} ) if $c->{cfg}{dump_touched};

    return \%hash;
}

sub get_prod_item_list {
    my ( $c, @item_ids ) = @_;

    my %to_skip = $c->get_market_groups_to_skip;
    my $item_ids;
    $item_ids = { map { $_ => 1 } @item_ids } if @item_ids;

    $c->{cache}{item_details} ||= $c->get_list( 'item_id_details', 'typeid' );
    $c->{cache}{blueprintTypes} ||= $c->get_list( 'blueprint_ids', 'producttypeid' );

    my @all_items = values %{$c->{cache}{item_details}};
    my @filtered_items = map $c->filter_prod_items_base( $_, \%to_skip, $item_ids ), @all_items;
    my @assets = @filtered_items = map $c->extend_item_for_prod( $_ ), @filtered_items;

    return \@assets;
}

sub filter_asset_list {
    my ( $c, $assets ) = @_;

    my @assets = map $c->filter_minimum_profit($_), @{$assets};
    @assets = map $c->filter_maximum_roi($_), @assets;
    @assets = map $c->filter_minimum_margin($_), @assets;


    $c->{hidden_item_count} = @{$assets} - @assets;
    $c->{hidden_item_percentage} = shorten( 100 * $c->{hidden_item_count} / @{$assets} );

    return \@assets;
}

sub filter_minimum_margin {
    my ( $c, $item ) = @_;

    $item->{real_unit_profit_mult} ||= 0;
    $c->{sess}{minimum_margin} = -9999 if !defined $c->{sess}{minimum_margin} or $c->{sess}{minimum_margin} eq "";

    return if ( $item->{real_unit_profit_mult} * 100 ) <= $c->{sess}{minimum_margin};
    return $item;
}

sub filter_minimum_profit {
    my ( $c, $item ) = @_;

    $item->{daily_profit} ||= 0;
    $c->{sess}{minimum_profit} = -999_999_999_999 if !defined $c->{sess}{minimum_profit} or $c->{sess}{minimum_profit} eq "";

    return if $item->{daily_profit} <= $c->{sess}{minimum_profit};
    return $item;
}

sub filter_maximum_roi {
    my ( $c, $item ) = @_;

    $item->{days_til_profit} //= 9999;
    $c->{sess}{maximum_roi} = 999_999_999 if !defined $c->{sess}{maximum_roi} or $c->{sess}{maximum_roi} eq "";

    return if $item->{days_til_profit} >= $c->{sess}{maximum_roi};
    return $item;
}

sub prepare_assets_for_printing {
    my ( $c, $assets ) = @_;

    $c->prettify_asset( $_ ) for @{$assets};

    return;
}

sub sort_containers_by {
    my ( $c, $assets, @sort_methods ) = @_;

    for my $asset ( @{ $assets } ) {

        if( $asset->{contents} ) {
            $c->sort_containers_by( $asset->{contents}, @sort_methods );
            for my $method ( reverse @sort_methods ) {
                no warnings;

                my ($m1,$m2) = split /\./, $method;
                if( $m2 ) {
                    $asset->{contents} = [ sort {
                        $b->{$m1}->{$m2} <=> $a->{$m1}->{$m2}
                                         ||
                        $a->{$m1}->{$m2} cmp $b->{$m1}->{$m2}
                    } @{ $asset->{contents} } ];
                }
                else {
                    if ( $method eq 'itemname' or $method eq 'suggestion' ) {
                        $_->{$method} ||= '' for @{ $asset->{contents} };
                        $asset->{contents} = [ sort {
                            $a->{$method} cmp $b->{$method}
                        } @{ $asset->{contents} } ];

                    }
                    else {
                        $asset->{contents} = [ sort {
                            $b->{$method} <=> $a->{$method}
                        } @{ $asset->{contents} } ];

                    }
                }

                use warnings;
            }
        }
    }
}

sub fill_value_ids {
    my ( $c, $assets ) = @_;

    for my $asset ( @{ $assets } ) {

        $c->fill_value_ids( $asset->{contents} ) if $asset->{contents};
        $c->fill_value_ids( [ values %{ $asset->{reprocess} } ] ) if $asset->{reprocess};
        $c->fill_value_ids( [ values %{ $asset->{bom} } ] ) if $asset->{bom};

        next if !$asset->{marketgroupid};

        my $id = $asset->{typeid};
        my $item_value_cache = $c->{caches}{item_values};

        if( !$item_value_cache->{$id} ) {
            $item_value_cache->{$id} = $c->get_item_value( $id );
            $item_value_cache->{$id} ||= 'fill';
        }
    }

    return;
}

sub mark_old_ids {
    my ( $c ) = @_;

    my $statement = "SELECT id FROM eaa_item_value_cache WHERE \"old\" = 0 ";
    my $ary_ref = $c->dbh->selectcol_arrayref($statement);

    my $value_cache_ids = join ',', @{ $ary_ref };

    return if !$value_cache_ids;

    my $ua = new LWP::UserAgent;
    $ua->timeout(1800);
    $ua->agent('AssetManager/1.0');

    my $req = POST 'http://prices.eve-profits.com/check_old', [ id => $value_cache_ids ];

    my $old_ids = $ua->request($req)->content;

    die "No hacking!\n$old_ids" if $old_ids =~ /[^\d,]/;

    $c->dbh->do("UPDATE eaa_item_value_cache SET \"old\"=1 WHERE id IN ( $old_ids )") if $old_ids;

    return;
}

sub fill_missing_value_ids {
    my ( $c ) = @_;

    my $item_value_cache = $c->{caches}{item_values};

    my (@list, $list_string);
    for ( keys %{ $item_value_cache } ) {
        push @list, $_ if $item_value_cache->{$_} eq 'fill';
    }

    return if !@list;

    my $ua = new LWP::UserAgent;
    $ua->timeout(1800);
    $ua->agent('AssetManager/1.0');

    $list_string = join ',', @list;

    my @params = ( id => $list_string );
    push @params, ( region => $c->{sess}{regions} ) if $c->{sess}{regions};

    my $req = POST 'http://prices.eve-profits.com/item_data', \@params;
    my $result = $ua->request($req);
    my $json = $result->content;
    die "\n\nItem data request failed:\n\n $! \n\n $@ \n\n ".Dumper($result)." \n\n" if !$json;

    my $json_ref = eval { from_json( $json ) };
    die "\n\nJSON Parsing Error:\n\n $! \n\n $@ \n\n $json \n\n" if $@;

    for ( @{ $json_ref } ) {
        my $typeid = $_->{typeid};
        $c->store_item_value_data( $_ );
        $item_value_cache->{$typeid} = $_;
    }

    for ( keys %{ $item_value_cache } ) {
        delete $item_value_cache->{$_} if $item_value_cache->{$_} eq 'fill';
    }

    return;
}

sub store_item_value_data {
    my ($c, $value_data ) = @_;

    my (@keys,@values,@placeholders);

    for my $key ( keys %{ $value_data } ) {
        push @keys, $key;
        push @values, $value_data->{$key};
        push @placeholders, '?';
    }

    my $key_string = join( ',', @keys );
    $key_string =~ s/old/"old"/;
    my $placeholder_string = join( ',', @placeholders );

    my $query = $c->def_pb->fetch( 'insert_item_value_data', { keys => $key_string, placeholders => $placeholder_string } );

    my $exists = $c->dbh->selectrow_array( "SELECT id FROM eaa_item_value_cache WHERE id = ?", undef, $value_data->{id} );
    return if $exists;

    eval { $c->dbh->do($query, undef, @values ) }; # TODO: find a way to avoid collisions here entirely
    return;
}

sub extend_profit_data {
    my ( $c, $assets ) = @_;

    my $region = $c->{sess}{regions};

    for my $asset ( @{ $assets } ) {

        $c->extend_profit_data( $asset->{contents} ) if $asset->{contents};
        $c->extend_profit_data( [ values %{ $asset->{reprocess} } ] ) if $asset->{reprocess};
        $c->extend_profit_data( [ values %{ $asset->{bom} } ] ) if $asset->{bom};

        next if !$asset->{marketgroupid};

        $c->calculate_profit_range( $asset ) if $asset->{real_unit_profit_mult};

        1;
    }

    return;
}

sub calculate_profit_range {
    my ( $c, $asset ) = @_;

    $asset->{adapt_profit_mult} = $c->calc_profit_log_range( $asset->{real_unit_profit_mult} ) if $asset->{real_unit_profit_mult} > 1;

    $asset->{adapt_profit_mult} = $c->calc_profit_range( $asset->{real_unit_profit_mult} ) if $asset->{real_unit_profit_mult} <= 1;

    $asset->{adapt_profit_mult} = int $asset->{adapt_profit_mult};

    return;
}

sub calc_profit_range {
    my ( $c, $val ) = @_;

    $val *= $c->{normal_profit_range};

    return $val;
}

sub calc_profit_log_range {
    my ( $c, $val ) = @_;

    $val = logn( $val, $c->{cfg}{log_scale} );

    $c->{max_log} ||= 1;
    my $adapt_factor = 99 / $c->{max_log};
    $val *= $adapt_factor;
    $val++;
    $val = int $val;

    return $val;
}

sub logn {
    my ( $i, $scale ) = @_;

    $i += $scale;

    my $log = log($i)/log( $scale );
    $log--;

    return $log;
}

sub extend_value_data {
    my ( $c, $assets ) = @_;

    my $region = $c->{sess}{regions};

    for my $asset ( @{ $assets } ) {
        $c->extend_value_data( $asset->{contents} ) if $asset->{contents};
        $c->extend_value_data( [ values %{ $asset->{reprocess} } ] ) if $asset->{reprocess};
        $c->extend_value_data( [ values %{ $asset->{bom} } ] ) if $asset->{bom};

        next if !$asset->{marketgroupid};

        $c->calculate_manufacture_prices( $asset );

        1;
    }

    return;
}

sub calculate_manufacture_prices {
    my ( $c, $asset ) = @_;

    my $id = $asset->{typeid};

    #$DB::single = 16278 == $id;

    %{ $asset->{value} } = %{ $c->{caches}{item_values}{$id} } if $c->{caches}{item_values}{$id};
    my $value = $asset->{value};

    if ( $asset->{bom} and !$value->{manuf_cost} ) {
        for my $component ( values %{ $asset->{bom} } ) {
            $component->{value}{sell_price} = 999999999 if !$component->{value}{sell_price};
            $value->{manuf_cost} += $component->{value}{sell_price};
        }
    }
    else {
        $value->{manuf_cost} ||= '0';
    }

    return $c->calculate_item_profits ( $asset ) if $asset->{value}{manuf_cost};

    for ( qw/ buy_price manuf_cost sell_price / ) {
        $value->{$_} ||= 0;
        $value->{$_} *= $asset->{quantity};
    }

    return;
}

sub calculate_item_profits {
    my ( $c, $asset ) = @_;

    #$DB::single = $id == 24694;

    $c->{sess}{broker_fee} =~ s/\.+/./g;

    my $broker_mult = $c->{sess}{broker_fee}/100;
    my $sales_tax_mult = 0.01 * ( 1 - ( $c->{sess}{accounting} / 10 ) );

    my $value = $asset->{value};

    $asset->{value}{sell_price} ||= ( $asset->{value}{manuf_cost} * 1.5 );

    $asset->{prod_per_day} = $c->get_prod_per_day( $asset );

    my $daily_movement;
    $daily_movement = $value->{move} if $value->{move} > -1;

    $asset->{sales} = $daily_movement * .5 if $daily_movement;
    $asset->{real_sales} = $asset->{prod_per_day};
    $asset->{real_sales} = $asset->{sales} if $asset->{sales} and $asset->{sales} < $asset->{prod_per_day};
    if ( !$asset->{sales} ) {
        $asset->{sales_guess} = 0.25 * ( $asset->{value}{buy_vol} + $asset->{value}{sell_vol} );
        $asset->{sales_guess} = 0.00001 if !$asset->{sales_guess};
        $asset->{real_sales} = $asset->{sales_guess} if $asset->{sales_guess} and $asset->{sales_guess} < $asset->{real_sales};
    }

    $asset->{unit_profit} =
        $asset->{value}{sell_price}
        - $asset->{value}{manuf_cost}
        - ( $asset->{value}{sell_price} * $broker_mult )
        - ( $asset->{value}{sell_price} * $sales_tax_mult );

    $asset->{excess} = 999;
    if ( $asset->{sales} ) {
        $asset->{excess} = $asset->{prod_per_day} / $asset->{sales};
        $asset->{excess} -= 1;
        $asset->{excess} *= 100;
    }

    my $bp = $c->{cache}{item_details}{$asset->{blueprinttypeid}};
    $asset->{bp_price} = $bp->{baseprice} * $c->{sess}{production_slots};

    $asset->{daily_profit} = $asset->{unit_profit} * $asset->{real_sales};

    $asset->{days_til_profit} = $asset->{bp_price} / $asset->{daily_profit};
    $asset->{days_til_profit} = 9999.99 if $asset->{days_til_profit} > 9999.99;
    $asset->{days_til_profit} = 0 if $asset->{days_til_profit} <= 0;

    $asset->{real_unit_profit_mult} = $asset->{unit_profit} / $asset->{value}{manuf_cost};
    $asset->{real_unit_profit_mult} = 0 if $asset->{real_unit_profit_mult} < 0;
    $c->{max_mult} ||= 0;
    $c->{max_mult} = $asset->{real_unit_profit_mult} if $asset->{real_unit_profit_mult} > $c->{max_mult};

    $asset->{log_real_unit_profit_mult} = log( $asset->{real_unit_profit_mult} ) if $asset->{real_unit_profit_mult};

    $asset->{unit_profit_mult} = 1.2 * $asset->{real_unit_profit_mult};

    $asset->{unit_profit_mult} = 1 if $asset->{unit_profit_mult} > 1;

    return;
}

sub prettify_asset {
    my ( $c, $item ) = @_;
    my $batch = 0;

    # $DB::single = $item->{typeid} == 230;

    if( !$batch ) {
        $item->{batch_buy_price} = isk_shorten( $item->{value}{buy_price} );
        $item->{single_buy_price} = isk_shorten( $item->{value}{buy_price} * $item->{real_sales} );
        $item->{batch_sell_price} = isk_shorten( $item->{value}{sell_price} );
        $item->{single_sell_price} = isk_shorten( $item->{value}{sell_price} * $item->{real_sales} );
        $item->{batch_manuf_cost} = isk_shorten( $item->{value}{manuf_cost} );
        $item->{single_manuf_cost} = isk_shorten( $item->{value}{manuf_cost} * $item->{real_sales} );
    }

    if( $batch ) {
        $item->{single_buy_price} = isk_shorten( $item->{value}{buy_price} );
        $item->{batch_buy_price} = isk_shorten( $item->{value}{buy_price} * $item->{real_sales} );
        $item->{single_sell_price} = isk_shorten( $item->{value}{sell_price} );
        $item->{batch_sell_price} = isk_shorten( $item->{value}{sell_price} * $item->{real_sales} );
        $item->{single_manuf_cost} = isk_shorten( $item->{value}{manuf_cost} );
        $item->{batch_manuf_cost} = isk_shorten( $item->{value}{manuf_cost} * $item->{real_sales} );
    }

    $item->{value}{buy_vol} = '' if $item->{value}{buy_vol} <= 0;
    $item->{value}{sell_vol} = '' if $item->{value}{sell_vol} <= 0;

    $item->{daily_profit_num} = $item->{daily_profit};
    $item->{daily_profit} = isk_shorten( $item->{daily_profit} );
    $item->{unit_profit_green} = trunc( 255 * $item->{unit_profit_mult} );
    $item->{excess_green} = trunc( $c->get_production_green( $item ) );
    $item->{sales_green} = trunc( $c->get_sales_green( $item ) );
    $item->{excess} = shorten( $item->{excess} );
    $item->{sales} = shorten( $item->{sales} );
    $item->{prod_per_day} = shorten( $item->{prod_per_day} );
    $item->{days_til_profit} = shorten( $item->{days_til_profit} );
    $item->{bp_price} = bp_shorten( $item->{bp_price} );
    $item->{margin} = shorten( $item->{real_unit_profit_mult} * 100 ) if $item->{real_unit_profit_mult};

    $item->{margin} ||= '';

    return;
}

sub get_sales_green {
    my ( $c, $item ) = @_;

    return 0 if !$item->{sales};

    $item->{prod_per_day} ||= 0;

    my $factor = $item->{prod_per_day} / $item->{sales};
    $factor = $c->make_color_value( $factor );

    return $factor;
}

sub get_production_green {
    my ( $c, $item ) = @_;

    return 0 if !$item->{prod_per_day};

    $item->{sales} ||= 0;

    my $factor = $item->{sales} / $item->{prod_per_day};
    $factor = $c->make_color_value( $factor );

    return $factor;
}

sub make_color_value {
    my ( $c, $factor ) = @_;

    $factor -= 0.5;
    $factor = 0 if $factor < 0;
    $factor = 1 if $factor > 1;
    $factor *= 255;

    return $factor;
}

sub get_prod_per_day {
    my ( $c, $asset ) = @_;

    my $prod_time_mod = $c->{sess}{industry_skill};
    $prod_time_mod *= 0.04;
    $prod_time_mod = 1 - $prod_time_mod;

    my $owned = $c->owned;

    my $prod_efficiency = $owned->{$asset->{typeid}}{pe} || 0;
    $prod_efficiency = $prod_efficiency / ( 1 + $prod_efficiency );

    my $prod_time = $asset->{productiontime};
    $prod_time = $asset->{productivitymodifier} / $prod_time;
    $prod_time *= $prod_efficiency;
    $prod_time = 1 - $prod_time;
    $prod_time *= $asset->{productiontime};
    $prod_time *= $prod_time_mod;

    my $prod_per_day = 86400 / $prod_time;
    $prod_per_day *= $asset->{quantity};
    $prod_per_day *= $c->{sess}{production_slots};

    return $prod_per_day;
}

sub get_item_value {
    my ( $c, $id ) = @_;

    return undef if !$id;

    return $c->{caches}{item_values}{$id};
}

sub get_all_item_values {
    my ( $c ) = @_;

    my $query = $c->def_pb->fetch( 'get_all_item_values' );

    my $values = $c->dbh->selectall_hashref( $query, 'typeid', undef, $c->{sess}{regions}, 0 );

    $c->{caches}{item_values} = $values || {};

    return;
}

sub extend_item_data {
    my ($c, $assets) = @_;

    for my $asset ( @{ $assets } ) {

        $asset->{itemid} ||= 0;
        my $typeid = $asset->{typeid};
        my $details = $c->{cache}{item_details}{$typeid};
        $asset->{itemname}          = $details->{typename};
        $asset->{portionsize}       = $details->{portionsize};
        $asset->{marketgroupid}       = $details->{marketgroupid} if $details->{marketgroupid};
        $asset->{blueprinttypeid} = $details->{blueprinttypeid} if defined $details->{bp_marketgroup_id};
        $asset->{wastefactor} = $details->{wastefactor}/100 if defined $details->{bp_marketgroup_id};
        $asset->{productiontime} = $details->{productiontime} if defined $details->{productiontime};
        $asset->{productivitymodifier} = $details->{productivitymodifier} if defined $details->{productivitymodifier};

        $asset->{bom} = $c->get_bom( $asset );

        $c->extend_item_data( $asset->{contents} ) if( $asset->{contents} );
        $c->log->info( $asset->{typeid} ) if $c->{cfg}{dump_touched};
    }

}

sub get_simple_manufacturing {
    my ( $c, $typeid ) = @_;

    $c->{cache}{simple_manufacturing}{$typeid} ||= $c->get_list( 'simple_manufacturing', 'typeid', $typeid );

    return clone( $c->{cache}{simple_manufacturing}{$typeid} );
}

sub get_extra_manufacturing {
    my ( $c, $typeid ) = @_;

    $c->{cache}{extra_manufacturing}{$typeid} ||= $c->get_list( 'extra_manufacturing', 'typeid', $typeid );

    return clone( $c->{cache}{extra_manufacturing}{$typeid} );
}

sub get_bom {
    my ($c, $asset) = @_;

    return if !$asset->{blueprinttypeid}; # can't be built
    return if !$asset->{marketgroupid}; # can't be sold
    return if $asset->{techlevel} and $asset->{techlevel} == 2;

    my $prod_eff = $c->{sess}{prod_eff_level};
    my $me_level = $c->get_me_level( $asset );
    my $bom_cache = $c->{caches}{bom}{$prod_eff}{$me_level};

    return clone( $bom_cache->{$asset->{typeid}} ) if $bom_cache->{$asset->{typeid}};

    my %bom = %{ $c->get_simple_manufacturing( $asset->{typeid} ) };
    my %extra_bom = %{ $c->get_extra_manufacturing( $asset->{blueprinttypeid} ) };

    my $waste_modifier = $c->get_waste_modifier( $asset, $me_level );

    #$DB::single = 1 if 27912 == $asset->{typeid};

    if ( values %bom ) {
        $c->extend_item_data( [ values %bom ] );
        for ( values %bom ) {
            $_->{quantity} *= $waste_modifier;
            if ( $extra_bom{$_->{typeid}} ) {
                $_->{quantity} += $extra_bom{$_->{typeid}}{quantity};
                delete $extra_bom{$_->{typeid}};
            }
            $_->{quantity} = sprintf "%.0f", $_->{quantity};
            $_->{quantity} /= $asset->{portionsize};
            $c->log->info( $_->{typeid} ) if $c->{cfg}{dump_touched};
        }
    }

    if ( values %extra_bom ) {
        $c->extend_item_data( [ values %extra_bom ] );
        for ( values %extra_bom ) {
            $_->{quantity} = sprintf "%.0f", $_->{quantity};
            $_->{quantity} /= $asset->{portionsize};
            $bom{$_->{typeid}} = $_;
            $c->log->info( $_->{typeid} ) if $c->{cfg}{dump_touched};
        }
    }

    #$DB::single = 1 if 27912 == $asset->{typeid};

    $bom_cache->{$asset->{typeid}} = \%bom;

    return clone(  $bom_cache->{$asset->{typeid}} );
}

sub get_me_level {
    my ( $c, $asset ) = @_;

    my $owned = $c->owned;

    my $bp_inventory = $owned->{$asset->{typeid}};

    $asset->{rt} = $research_types{$bp_inventory->{r}} if $bp_inventory;

    my $material_efficiency = $c->{sess}{bp_mat_level};

    $material_efficiency = $bp_inventory->{me} if $bp_inventory;

    $material_efficiency ||= 0;

    return $material_efficiency;
}

sub get_waste_modifier {
    my ( $c, $asset, $me_level ) = @_;

    my $waste_modifier = (
        (
            1 + (
                $asset->{wastefactor} / (
                        1 + $me_level
                )
            )
        )
        +
        (
            0.25 - ( 0.05 * $c->{sess}{prod_eff_level} )
        )
    );

    return $waste_modifier;
}

sub collapse_duplicates {
    my ($c, $assets) = @_;

    my %combinations;
    my @remove_list;

    for my $i ( 0 .. $#{ $assets } ) {
        if( $assets->[$i]{rowset} ) {
            $assets->[$i]{contents} = $assets->[$i]{rowset}{row};
            delete $assets->[$i]{rowset};
            $c->collapse_duplicates( $assets->[$i]{contents} );
            next;
        }
        my $location = $assets->[$i]{locationid} || '';
        push @{ $combinations{"$location $assets->[$i]{typeid}"} }, $i;
    }

    for my $list ( values %combinations ) {
        next unless @{$list} > 1;
        my $original = shift @{$list};

        for my $item ( @{$list} ) {
            $assets->[$original]{quantity} += $assets->[$item]{quantity};
            push @remove_list, $item;
        }
    }

    return if !@remove_list;

    @remove_list = sort  {$b <=> $a} @remove_list;

    for my $item ( @remove_list ) {
        splice @{ $assets }, $item, 1;
    }

    return;
}

sub get_list {
    my ($c, $name, $key, $selector) = @_;
    $selector ||= '';

    my @input = ( $c->def_pb->fetch( $name ), $key );
    push @input, ( undef, $selector ) if $selector;

    my $list = $c->dbh->selectall_hashref( @input );

    return $list;
}

sub init_tables {
    my ( $c ) = @_;

    return if $c->{cache}{table_init_done};

    my $table_check = $c->table_pb->fetch( 'init_tables_dic' );
    my @keywords = $c->table_pb->keywords( 'tables' );

    for my $table ( @keywords ) {
        next if $table !~ m/^eaa_/ and $table !~ m/^emo_/;
        next if $c->dbh->selectrow_array($table_check, undef, $table);

        my $query = $c->table_pb->fetch( $table );
        $c->dbh->do( $query ) or die "halp";
    }

    $c->{cache}{table_init_done} = 1;

    return;
}

sub table_pb {
    my ( $c ) = @_;

    $c->{cache}{table_pb} ||= $c->phrasebook('tables');

    return $c->{cache}{table_pb};
}

sub def_pb {
    my ( $c ) = @_;

    $c->{cache}{def_pb} ||= $c->phrasebook;

    return $c->{cache}{def_pb};
}

sub query_vars {
    my ( $c ) = @_;

    $c->{query_vars} ||= { $c->query->Vars };

    return $c->{query_vars};
}

sub update_session {
    my ( $c, @settings ) = @_;

    my %q = %{ $c->query_vars };
    my %sess = %{ $c->session->dataref };

    if ( $q{reset_settings} ) {
        $c->session->clear;
        undef %q;
        undef %sess;
    }

    for ( @settings ) {
        $c->session->param( $_, $c->{cfg}{$_}  ) if !exists $sess{$_}; # set defaults if session setting non-existant
        next if !exists $q{$_};
        $q{$_} =~ s/\0/,/g;                 # make lists easier to parse
        $c->session->param( $_, $q{$_} );   # insert settings from query
    }

    $c->{sess} = $c->session->dataref;

    return;
}

sub get_emo_status {
    my ( $c ) = @_;

    my $status = $c->dbh->selectrow_array( "SELECT value FROM emo_key_value_store WHERE key = ?", undef, "updater_status" );

    return 'unknown' if !$status;

    $status = from_json( $status, { allow_nonref => 1 } );

    return $status;
}


sub login_box {
    my ( $c ) = @_;
    my $self        = $c->authen;
    my $credentials = $self->credentials;
    my $runmode     = $self->_cgiapp->get_current_runmode;
    my $destination = $self->_detaint_destination || $self->_detaint_selfurl;
    my $action      = $self->_detaint_url;
    my $username    = $credentials->[0];
    my $password    = $credentials->[1];
    my $login_form  = $self->_config->{LOGIN_FORM} || {};
    my %options = (
        COMMENT                 => 'Please enter your username and password in the fields below.',
        REMEMBERUSER_OPTION     => 1,
        REMEMBERUSER_LABEL      => 'Remember User Name',
        REMEMBERUSER_COOKIENAME => 'CAPAUTHTOKEN',
        REGISTER_URL            => '',
        REGISTER_LABEL          => 'Register Now!',
        FORGOTPASSWORD_URL      => '',
        FORGOTPASSWORD_LABEL    => 'Forgot Password?',
        INVALIDPASSWORD_MESSAGE => 'Invalid username or password<br />(login attempt %d)',
        INCLUDE_STYLESHEET      => 1,
        FORM_SUBMIT_METHOD      => 'post',
        %$login_form,
    );

    my $messages = '';
    if ( my $attempts = $self->login_attempts ) {
        $messages .= '<li class="warning">' . sprintf($options{INVALIDPASSWORD_MESSAGE}, $attempts) . '</li>';
    }

    my $tabindex = 3;
    my ($rememberuser, $username_value, $register, $forgotpassword, $javascript, $style) = ('','','','','','');
    if ($options{FOCUS_FORM_ONLOAD}) {
        $javascript .= "document.loginform.${username}.focus();\n";
    }
    if ($options{REMEMBERUSER_OPTION}) {
        $rememberuser = qq[<input id="authen_rememberuserfield" tabindex="$tabindex" type="checkbox" name="authen_rememberuser" value="1" />$options{REMEMBERUSER_LABEL}<br />];
        $tabindex++;
        $username_value = $self->_detaint_username($username, $options{REMEMBERUSER_COOKIENAME});
        $javascript .= "document.loginform.${username}.select();\n" if $username_value;
    }
    my $submit_tabindex = $tabindex++;
    if ($options{REGISTER_URL}) {
        $register = qq[<a href="$options{REGISTER_URL}" id="authen_registerlink" tabindex="$tabindex">$options{REGISTER_LABEL}</a>];
        $tabindex++;
    }
    if ($options{FORGOTPASSWORD_URL}) {
        $forgotpassword = qq[<a href="$options{FORGOTPASSWORD_URL}" id="authen_forgotpasswordlink" tabindex="$tabindex">$options{FORGOTPASSWORD_LABEL}</a>];
        $tabindex++;
    }
    if ($options{INCLUDE_STYLESHEET}) {
        my $login_styles = $self->login_styles;
        $style = <<EOS;
<style type="text/css">
<!--/* <![CDATA[ */
$login_styles
/* ]]> */-->
</style>
EOS
    }
    if ($javascript) {
        $javascript = qq[<script type="text/javascript" language="JavaScript">$javascript</script>];
    }

    my %params = (
        options => \%options,
        action => $action,
        messages => $messages,
        username => $username,
        username_value => $username_value,
        password => $password,
        submit_tabindex => $submit_tabindex,
        register => $register,
        forgotpassword => $forgotpassword,
        destination => $destination,
        runmode => $runmode,
    );

    my $html = ${$c->tt_process( \%params )};

    $html = <<END;
$style
$html
$javascript
END

    return $html;
}

1;
