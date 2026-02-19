use strict;
use warnings;
use Test::More;
use EV;

use_ok('EV::Websockets');

# Create context
my $ctx = EV::Websockets::Context->new();
ok($ctx, 'Context created with default loop');

# Explicitly destroy before test ends
undef $ctx;
pass('Context destroyed without error');

done_testing;
