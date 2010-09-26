package Games::EveOnline::MarketOrders::ReportInsert;
use strict;
use warnings;

use lib '../../..';

use Games::EveOnline::MarketOrders::Tools;

use base qw( Exporter );
our @EXPORT_OK = qw(
    finalize_old_batch      report_is_older_than_db     compare_report_size_with_db
    expire_item_value_data  insert_market_export
);



sub finalize_old_batch {
    my ( $c, $report, $skip_check ) = @_;
    
    return 0 if $c->report_is_older_than_db( $report );
    
    return 0 if !$skip_check and $c->compare_report_size_with_db ( $report ) < 0.75;
    
    $c->expire_item_value_data( $report );
    $c->insert_market_export( $report );
    
    return 1;
}

sub report_is_older_than_db {
    my ($c, $report ) = @_;
    
    my $id =  $c->dbh->selectrow_array(
        "SELECT typeid from emo_exports WHERE typeid=? AND regionid=? AND reportedtime >= ? AND source=? ",
        undef, $report->{typeid}, $report->{regionid}, $report->{reportedtime}, $report->{source}
    );
    
    return $id;
}

sub compare_report_size_with_db {
    my ($c, $report ) = @_;
    
    return 0 if !$report->{content};
    
    my $query = "SELECT content from emo_exports WHERE typeid=? AND regionid=? AND source=?";
    my $db_content = $c->dbh->selectrow_array(
        $query, undef, $report->{typeid}, $report->{regionid}, $report->{source}
    );
    
    return 1 if !$db_content;
    
    my $db_content_length = length( $db_content );
    my $new_content_length = length( $report->{content} );
    my $diff_factor = $new_content_length / $db_content_length;
    
    return $diff_factor;
}

sub expire_item_value_data {
    my ($c, $meta ) = @_;
    
    my $query = $c->def_pb->fetch( 'expire_item_value_data' );
    
    $c->dbh->do( $query, undef, $meta->{typeid}, "%$meta->{regionid}%" );
    
    return;
}

sub insert_market_export {
    my ($c, $meta ) = @_;
    
    my $update_query = $c->def_pb->fetch( 'update_market_export' );
    
    my $updates = $c->dbh->do($update_query, undef, $meta->{content}, $meta->{reportedtime}, $meta->{source}, $meta->{typeid}, $meta->{regionid}, $meta->{source} );
    
    return if $updates > 0; # do returns 0E0 here, so we need to do a proper check
    
    my (@keys,@values);
    
    for my $key ( keys %{ $meta } ) {
        push @keys, $key;
        push @values, $meta->{$key};
    }
    
    my $key_string = join( ',', @keys );
    my $placeholder_string = join( ',', ('?') x @keys );
    
    my $query = $c->def_pb->fetch( 'insert_market_export', { keys => $key_string, placeholders => $placeholder_string } );
    
    $c->dbh->do($query, undef, @values );
    
    return;
}


1;
