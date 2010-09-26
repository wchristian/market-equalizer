package Games::EveOnline::AssetManager::Tools;

use base 'ToolSet';

use strict;
use warnings;

ToolSet->use_pragma( 'strict' );
ToolSet->use_pragma( 'warnings' );
ToolSet->use_pragma( qw/ feature say switch / ); # perl 5.10

ToolSet->export(
    'HTML::Lint'          => undef,
    'Data::Dumper'          => undef,
    'WebService::EveOnline'          => undef,
    'Storable' => 'freeze thaw',
    'WWW::IndexParser' => undef,
    'POSIX' => 'ceil',
    'File::Slurp' => undef,
    'Benchmark' => undef,
    'Memoize' => undef,
    'DateTime' => undef,
    'File::Temp' => 'tempfile',
    'Compress::Zlib' => undef,
    'enum' => 'orderid regionid systemid stationid typeid bid price minvolume volremain volenter issued duration range reportedby reportedtime',
    'XML::Simple' => undef,
    'List::Util' => 'max',
    'HTTP::Request::Common' => 'POST',
    'LWP::UserAgent' => undef,
    'Text::CSV::Slurp' => undef,
    'JSON' => undef,
    'Clone::Fast' => 'clone',
);

use Time::Local;

our @EXPORT = qw(
    lint_html extend_template_include_paths add_asset_update_time get_asset_update_time
    expiry_to_timestamp shorten_and_multiply shorten isk_shorten bp_shorten
);

sub lint_html {
    my ($o) = @_;
    
    return unless $ENV{DEBUG_MODE};
    
    # fix some weird character caused by JS insertion
    $$o =~ s/\x9F//g;
    
    # parse the output with HTML::Lint
    my $lint = HTML::Lint->new();
    $lint->parse($$o);
    $lint->eof();
  
    # if there were errors put them into a
    # new window
    if ($lint->errors) {
        my $err_text = join(
            "",
            map { "<li>$_</li>" }
            map {
                s/&/&amp;/g;
                s/</&lt;/g;
                s/>/&gt;/g;
                s/\\/\\\\/g;
                s/"/\\"/g;
                $_;
            }
            map { $_->as_string }
            $lint->errors
        );
        
        $err_text = "<ul>$err_text</ul>";

        my $js = <<END;
<script language="javascript">
    var html_lint_window = window.open("", "html_lint_window", "height=300,width=600");
    html_lint_window.document.write("<html><head><title>HT ML Errors Detected</title></head><body><h1>HTML Errors Detected</h1>$err_text</body></html>");
    html_lint_window.document.close();
    html_lint_window.focus();
</script>
END

        # insert the js code
        $$o =~ s/<!-- :LINT: -->/$js\n/;
    }
    
}

sub add_asset_update_time {
    my ($o) = @_;
    
    my $assets_cached_until = '';#get_asset_update_time();
    
    # insert the js code
    $$o =~ s/<!-- next_asset -->/Next asset update: $assets_cached_until/;
}

sub get_asset_update_time {
    my $assets_cached_until;
    my $dbh_time=DBI->connect('dbi:SQLite:dbname=c:\windows\temp\webservice_eveonline.db','','',{AutoCommit=>1});
    my $sth_time = $dbh_time->prepare( "select cacheuntil from eve_cache where cachekey like '%%asset%%'" );
    $sth_time->execute();
    while ( my $row = $sth_time->fetchrow_hashref() ) {
        $assets_cached_until = $row->{cacheuntil};
    }
    
    return localtime $assets_cached_until;
}

sub extend_template_include_paths {
    my $c = shift;
    
    my $template_path = $c->tt_template_name;
    $template_path =~ s@[/\\][^/\\]+?$@/@;
    my @include_paths;
    push @include_paths, '..';
    push @include_paths, '../'.$template_path;
    $c->tt_include_path( @include_paths );
}

sub expiry_to_timestamp {
    my ($date) = @_;

    $date =~ m/^(\d+)-(\d+)-(\d+)/;
   
    return timelocal(0,0,0,$3,$2-1,$1);
}

sub shorten_and_multiply {
    return 'NA' if $_[0] eq 'NA';
    return 'NA' if $_[0] eq '';
    $_[0] = $_[0] * 1;
    $_[1] = $_[1] * 1;
    my $res = sprintf '%.2f', $_[0] * $_[1];
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    return $res;
}

my %shorten_cache;
sub shorten {
    return '' if !$_[0];
    return $shorten_cache{$_[0]} if $shorten_cache{$_[0]};
    my $res = sprintf '%.2f', $_[0];
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    $shorten_cache{$_[0]} = $res;
    return $res;
}

my %isk_shorten_cache;
sub isk_shorten {
    my $res = $_[0];
    return '' if !$res;
    return $isk_shorten_cache{$res} if $isk_shorten_cache{$res};
    return isk_shorten_k(@_) if abs($res) < 100000;
    $res /= 1_000_000;
    $res = sprintf '%.3f', $res;
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    $res .= '&nbsp;M';
    $isk_shorten_cache{$res} = $res;
    return $res;
}

sub isk_shorten_k {
    my $res = $_[0];
    return isk_shorten_t(@_) if abs($res) < 100;
    $res /= 1_000;
    $res = sprintf '%.2f', $res;
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    $res .= '&nbsp;K';
    $isk_shorten_cache{$res} = $res;
    return $res;
}

sub isk_shorten_t {
    my $res = $_[0];
    $res = sprintf '%.2f', $res;
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    $isk_shorten_cache{$res} = $res;
    return $res;
}

my %bp_shorten_cache;
sub bp_shorten {
    return '' if !$_[0];
    return $bp_shorten_cache{$_[0]} if $bp_shorten_cache{$_[0]};
    my $res = $_[0] / 1_000_000;
    $res = sprintf '%.1f', $res;
    $res =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
    $bp_shorten_cache{$_[0]} = $res;
    return $res;
}

1;