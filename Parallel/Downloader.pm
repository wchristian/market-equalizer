package Parallel::Downloader;
$|=1;
use base 'Exporter';
our @EXPORT_OK = qw( download_in_parallel );

use Modern::Perl;
use autodie;

#use threads ( stack_size => 0 );
#use threads::shared;
#use Thread::Queue;
use List::Util 'min';
use File::Slurp;

our ( $talk, $html ) = (1,1);

sub talk {
    return if !$talk;
    print $_[0];
}

sub talk_line {
    return if !$talk;
    my $msg = $_[0];
    $msg .= "<br>" if $html;
    print "$msg\n";
}

sub download_in_parallel {
    my @downloads = @_;
    
    my $pending = @downloads;
    my @results;
    for ( @downloads ) {
        push @results, download_item( $_, $pending );
        $pending--;
    }
    return @results;
    
    # following code disabled pending better implementation

=cut
    my $thread_count = 5;
    $thread_count = min( scalar @downloads, $thread_count );
    
    my $Q = new Thread::Queue;
    $Q->enqueue( $_ ) for @downloads;
    
    talk_line "Starting $thread_count threads.";
    my @threads = map threads->create( \&download_queue_items, $Q ), (1..$thread_count);
    my @results = map $_->join, @threads;
    
    return @results;
=cut
}

sub download_queue_items {
    my ( $Q ) = @_;
    
    require LWP::UserAgent;
    
    my @results;
    while( my $download = $Q->dequeue_nb ) {
        my $pending = $Q->pending + 1;
        push @results, download_item( $download, $pending );
    }
    
    talk_line "No more downloads left, thread returning.";
    
    return @results;
}

sub download_item {
    my ( $download, $pending ) = @_;
    
    my $ua = LWP::UserAgent->new;
    
    if ( ref( $download ) ne 'HASH' ) {
        talk_line "$pending items on queue, downloading: $download";
        my $data = get_simple( $ua, $download, $pending );
        return $data;
    }
    
    return if !$download->{store};
    
    talk_line "$pending items on queue, downloading '$download->{name}' from $download->{url}";
    return download_item_to_file   ( $ua, $download, $pending ) if $download->{store} eq 'file';
    return download_item_to_memory ( $ua, $download, $pending ) if $download->{store} eq 'memory';
    
    return;
}

sub get_simple {
    my ( $ua, $download, $pending ) = @_;
    
    my $response = $ua->get( $download );
    
    return $response->content;
}

sub download_item_to_file {
    my ( $ua, $download, $pending ) = @_;
    
    my $response;
    $response = $ua->get ( $download->{url}, ':content_file' => $download->{path}                      )  if !$download->{params};
    $response = $ua->post( $download->{url}, $download->{params}, ':content_file' => $download->{path} )  if $download->{params};
    
    $download->{response} = $response->code;
    $download->{success} = 1 if $response->is_success and -e $download->{path};
    
    return $download;
}

sub download_item_to_memory {
    my ( $ua, $download, $pending ) = @_;
    
    my $response;
    $response = $ua->get ( $download->{url}                      )  if !$download->{params};
    $response = $ua->post( $download->{url}, $download->{params} )  if $download->{params};
    
    $download->{response} = $response->code;
    $download->{content} = $response->decoded_content;
    $download->{success} = 1 if $response->is_success;
    
    return $download;
}


1;
