#!/usr/bin/perl
use Modern::Perl;

use Test::Most qw( die defer_plan );
    
run_tests();
all_done();

exit;

###############################################################################

sub run_tests {
    BEGIN { use_ok( 'Parallel::Downloader', qw( download_in_parallel ) ); }

    can_ok( 'Parallel::Downloader', qw( download_in_parallel ) );
    
    #$Parallel::Downloader::talk = 0;
    
    my @downloads = prepare_downloads();
    
    my @results = download_in_parallel( @downloads );
    
    is( @results, 5, 'got 5 download results' );
    
    like( $results[0], qr/<xml/, 'first download returned xml data to memory' );
    
    return;
}

sub prepare_downloads {
    my $store_dir = "./test/";
    my $base_url = "http://eve-metrics.com/api/history.xml";
    
    my @downloads = (
        # basic GET request which gets replaced with the downloaded content and returned
        "http://eve-metrics.com/api/history.xml?type_ids=39&region_ids=10000032",
        
        # GET request with the content being stored as a file, gets updated with results and returned 
        {
            url => "$base_url?type_ids=36&region_ids=10000032",
            path => $store_dir."36_10000032",
            store => 'file',
            name => '36',
        },
        
        # GET request with the content being stored in the hash itself, gets updated with results and returned 
        {
            url => "$base_url?type_ids=25896&region_ids=10000032",
            store => 'memory',
            name => '25896',
        },
        
        # POST request with the content being stored as a file, gets updated with results and returned 
        {
            url => $base_url,
            params => { type_ids => 37, region_ids => 10000032 },
            path => $store_dir."37_10000032",
            store => 'file',
            name => '37',
        },
        
        # POST request with the content being stored in the hash itself, gets updated with results and returned 
        {
            url => $base_url,
            params => { type_ids => 38, region_ids => 10000032 },
            store => 'memory',
            name => '38',
        },
    );
    
    return @downloads;
}

sub prepare_download_to_file {
    my ( $file, $base_url, $store_dir ) = @_;
    
    my %download = (
        url => "$base_url$file",
        path => "$store_dir$file",
        store => 'file',
        name => $file,
    );
    
    return \%download;
}




