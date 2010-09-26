package Games::EveOnline::MarketOrders::Helpers;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use base qw( Exporter );
our @EXPORT_OK = qw(
    get_emo_status      get_work_lock       set_key_value
);


sub get_emo_status {
    my ( $c ) = @_;
    
    my $status = $c->dbh->selectrow_array( "SELECT value FROM emo_key_value_store WHERE key = ?", undef, "updater_status" );
    
    return 'unknown' if !$status;
    
    $status = from_json( $status, { allow_nonref => 1 } );
    
    return $status;
}

sub get_work_lock {
    my ( $c, $id ) = @_;
    
    $id ||= '';
    
    my $working = trylock( $id );
    
    return $working if $working;
    
    return if !trylock( "waiting_$id" );
    
    while ( 1 ) {
        $working = trylock( $id );
        last if $working;
        
        say "Update in progress. Waiting.<br>";
        sleep 10;
    }
    
    unlock( "waiting_$id" );
    
    return $working;
}

sub set_key_value {
    my ($c, $key, $value ) = @_;
    
    $value = to_json( $value, { allow_nonref => 1 } );
    
    my $update_query = "UPDATE emo_key_value_store SET value = ? WHERE key = ?";
    
    my $updates = $c->dbh->do($update_query, undef, $value, $key );
    
    return if $updates > 0; # do returns 0E0 here, so we need to do a proper check
    
    my $query = "INSERT INTO emo_key_value_store ( key, value ) VALUES ( ?, ? )";
    
    $c->dbh->do($query, undef, $key, $value );
    
    return;
}

1;
