use strict;
use warnings;
use Test::More tests => 54;

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}
BEGIN { use_ok 'Thruk::Controller::showlog' }

my $pages = [
    '/thruk/cgi-bin/showlog.cgi',
    '/thruk/cgi-bin/showlog.cgi?archive=-1',
    '/thruk/cgi-bin/showlog.cgi?archive=+1',
    '/thruk/cgi-bin/showlog.cgi?start=2010-03-02+00%3A00%3A00&end=2010-03-03+00%3A00%3A00',
    '/thruk/cgi-bin/showlog.cgi?start=2010-03-02+00%3A00%3A00&end=2010-03-03+00%3A00%3A00&oldestfirst=on',
];

for my $url (@{$pages}) {
    TestUtils::test_page(
        'url'     => $url,
        'like'    => 'Event Log',
        'unlike'  => [ 'internal server error', 'HASH', 'ARRAY' ],
    );
}

$pages = [
# Excel Export
    '/thruk/cgi-bin/showlog.cgi?view_mode=xls',
];

for my $url (@{$pages}) {
    TestUtils::test_page(
        'url'          => $url,
        'unlike'       => [ 'internal server error', 'HASH', 'ARRAY' ],
        'content_type' => 'application/x-msexcel',
    );
}
