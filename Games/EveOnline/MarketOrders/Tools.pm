package Games::EveOnline::MarketOrders::Tools;

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
    'XML::Simple' => undef,
    'WWW::IndexParser' => undef,
    'POSIX' => 'ceil',
    'File::Slurp' => undef,
    'Parallel::Downloader' => 'download_in_parallel',
    'Benchmark' => undef,
    'Memoize' => undef,
    'DateTime' => undef,
    'File::Temp' => 'tempfile',
    'Compress::Zlib' => undef,
    'enum' => 'orderid regionid systemid stationid typeid bid price minvolume volremain volenter issued duration range reportedby reportedtime expiry',
    'enum' => 'em_price em_volRemaining em_typeID em_range em_orderID em_volEntered em_minVolume em_bid em_issued em_duration em_stationID em_regionID em_solarSystemID em_jumps em_source',
    'DateTime::Format::W3CDTF' => undef,
    'DateTime::Format::MySQL' => undef,
    'DateTime' => undef,
    'XML::Simple' => undef,
    'HTTP::Request::Common' => 'POST',
    'JSON' => 'from_json to_json',
    'LockFile::Simple' => 'unlock trylock',
    'Carp' => 'cluck',
);

use Time::Local;

our @EXPORT = qw(
    lint_html extend_template_include_paths string_to_dt
    expiry_to_timestamp shorten_and_multiply shorten
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

    my $marp;
    eval {
    $marp = timelocal(0,0,0,$3,$2-1,$1)
    };
    die "$@ : $date" if $@;

    return $marp;
}

sub shorten_and_multiply {
    return 'NA' if $_[0] eq 'NA';
    return 'NA' if $_[0] eq '';
    $_[0] = $_[0] * 1;
    $_[1] = $_[1] * 1;
    sprintf '%.2f', $_[0] * $_[1];
}

sub shorten {
    return 'NA' if $_[0] eq 'NA'; sprintf '%.2f', $_[0];
}

sub string_to_dt {
    my ($string) = @_;

    my $dt;
    return if $string !~ m!^([0-9]{4,4})-([0-9]{1,2})-([0-9]{1,2})$!;

    $dt = DateTime->new(
        year   => $1,
        month  => $2,
        day    => $3,
    );

    return $dt;
}

1;
