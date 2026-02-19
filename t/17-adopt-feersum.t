use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require Feersum; 1 }
        or plan skip_all => 'Feersum not installed';
}

use EV;
use EV::Websockets;
use IO::Socket::INET;
use POSIX ();

# Test: Feersum accepts HTTP, detects WS upgrade, hands the socket
# to EV::Websockets adopt() with reconstructed HTTP upgrade as initial_data.
#
# Note: Feersum's io() detaches the connection but may retain internal
# state on the fd. The dup'd fd is used to avoid Feersum closing it.

my $ctx = EV::Websockets::Context->new();
my $feersum = Feersum->endjinn;

my $sock = IO::Socket::INET->new(
    Listen    => 10,
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    ReuseAddr => 1,
    Blocking  => 0,
) or die "Socket: $!";

my $port = $sock->sockport;
$feersum->use_socket($sock);

my (%keep, $handler_fired, $adopted_ok);

$feersum->request_handler(sub {
    my $req = shift;
    my $env = $req->env;
    $handler_fired = 1;

    unless (($env->{HTTP_UPGRADE} // '') =~ /websocket/i) {
        $req->send_response(400, [], ["Not a WebSocket"]);
        return;
    }

    # Reconstruct HTTP upgrade request from PSGI env
    my $path = $env->{REQUEST_URI} // $env->{PATH_INFO} // '/';
    my $http_req = "GET $path HTTP/1.1\r\n";
    for my $key (sort keys %$env) {
        next unless $key =~ /^HTTP_(.+)/;
        (my $hdr = $1) =~ s/_/-/g;
        $http_req .= "$hdr: $env->{$key}\r\n";
    }
    $http_req .= "\r\n";

    # dup() the fd so Feersum's cleanup doesn't close the socket
    my $io = $req->io;
    my $new_fd = POSIX::dup(fileno($io));
    die "dup failed" unless defined $new_fd;
    open(my $fh, '+<&=', $new_fd) or die "fdopen: $!";

    eval {
        $keep{ws} = $ctx->adopt(
            fh           => $fh,
            initial_data => $http_req,
            on_connect => sub { $adopted_ok = 1 },
            on_message => sub { $_[0]->send("echo:$_[1]") },
            on_close   => sub { delete $keep{ws} },
            on_error   => sub { delete $keep{ws} },
        );
    };
    diag "adopt failed: $@" if $@;
});

# Connect a native WS client
my $t = EV::timer(0.1, 0, sub {
    $keep{cli} = $ctx->connect(
        url => "ws://127.0.0.1:$port/ws",
        on_connect => sub {
            # Handshake done — test passes if we get here
            EV::break;
        },
        on_error => sub {
            diag "client error: $_[1]";
            delete $keep{cli};
            EV::break;
        },
    );
});

my $timeout = EV::timer(10, 0, sub { diag "Timeout"; EV::break });
EV::run;

ok($handler_fired, "Feersum received WebSocket upgrade request");
ok($adopted_ok, "WebSocket handshake completed via adopt(initial_data)");

done_testing;
