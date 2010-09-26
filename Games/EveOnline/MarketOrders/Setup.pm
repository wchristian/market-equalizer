package Games::EveOnline::MarketOrders::Setup;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use base qw( Exporter );
our @EXPORT_OK = qw(
    setup_phrasebooks   setup           setup_tt    def_pb
    cgiapp_postrun      init_tables     table_pb     
); 



my %cache;
my %cfg;

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
    
    $c->session_config( CGI_SESSION_OPTIONS => [
        "driver:PostgreSQL",
        $c->query,
        { TableName => 'eaa_sessions', Handle => $c->dbh, ColumnType => "binary" }
    ] );
    
    $c->log_config( LOG_DISPATCH_MODULES => [ {
        module => 'Log::Dispatch::File',
        name => 'debug',
        filename => './market_debug.log',
        min_level => 'debug',
        mode => '>>',
        append_newline => 1,
    } ] );
    
    $c->setup_phrasebooks;
    $c->init_tables;
    
    return;
}

sub cgiapp_postrun {
    my ($self, $o) = @_;
    
    lint_html($o) if $ENV{CGI_APP_DEBUG};
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


sub init_tables {
    my ( $c ) = @_;
    
    return if $c->{cache}{table_init_done};
    
    my $table_check = $c->table_pb->fetch( 'init_tables_dic' );
    my @keywords = $c->table_pb->keywords( 'tables' );

    for my $table ( @keywords ) {
        next if $table !~ m/^emo_/;
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


1;
