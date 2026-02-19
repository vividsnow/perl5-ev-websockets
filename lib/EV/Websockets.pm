package EV::Websockets;
use strict;
use warnings;

use EV;

BEGIN {
    use XSLoader;
    our $VERSION = '0.01';
    XSLoader::load __PACKAGE__, $VERSION;
}

package EV::Websockets::Context;

sub new {
    my ($class, %args) = @_;
    my $loop = $args{loop} // EV::default_loop;

    my $proxy      = $args{proxy};
    my $proxy_port = $args{proxy_port};

    if (!defined $proxy) {
        my $env_proxy = $ENV{https_proxy} // $ENV{http_proxy} // $ENV{all_proxy};
        if ($env_proxy && $env_proxy =~ m{^(?:https?://)?(?:[^@]+\@)?(\[[\w:]+\]|[^:/]+)(?::(\d+))?}) {
            $proxy      = $1;
            $proxy_port = $2 // 1080;
        }
    }
    
    $proxy      //= "";
    $proxy_port //= 0;
    
    return $class->_new($loop, $proxy, $proxy_port,
        $args{ssl_cert} // "", $args{ssl_key} // "", $args{ssl_ca} // "");
}

package EV::Websockets::Connection;

1;

__END__

=head1 NAME

EV::Websockets - WebSocket client/server using libwebsockets and EV

=head1 SYNOPSIS

    use EV;
    use EV::Websockets;

    my $ctx = EV::Websockets::Context->new(loop => EV::default_loop);

    my $conn = $ctx->connect(
        url        => 'ws://example.com/ws',
        on_connect => sub { my ($conn) = @_; print "Connected!\n" },
        on_message => sub {
            my ($conn, $data, $is_binary) = @_;
            print "Got: $data\n";
        },
        on_close   => sub {
            my ($conn, $code, $reason) = @_;
            print "Closed: $code $reason\n";
        },
        on_error   => sub {
            my ($conn, $err) = @_;
            print "Error: $err\n";
        },
    );

    $conn->send("Hello, WebSocket!");
    $conn->send_binary($binary_data);

    EV::run;

=head1 DESCRIPTION

EV::Websockets provides WebSocket client and server functionality using the
libwebsockets C library integrated with the EV event loop.

This module uses libwebsockets' foreign loop integration to run within an
existing EV event loop, making it suitable for applications already using EV.

=head1 CLASSES

=head2 EV::Websockets::Context

Manages the libwebsockets context and event loop integration.

=head3 new(%options)

Create a new context.

    my $ctx = EV::Websockets::Context->new(
        loop     => EV::default_loop,  # optional, defaults to EV::default_loop
        ssl_cert => 'client.pem',      # optional, for mTLS client certificates
        ssl_key  => 'client-key.pem',  # required if ssl_cert is set
        ssl_ca   => 'ca.pem',          # optional CA chain
    );

=head3 connect(%options)

Create a new WebSocket connection.

    my $conn = $ctx->connect(
        url              => 'wss://example.com/ws',
        protocol         => 'chat',              # optional subprotocol
        headers          => { Authorization => 'Bearer token' },
        ssl_verify       => 1,                   # 0 to allow self-signed certs
        max_message_size => 1048576,             # optional, 0 = unlimited
        on_connect  => sub { my ($conn, $headers) = @_; ... },
        on_message  => sub { my ($conn, $data, $is_binary, $is_final) = @_; ... },
        on_close    => sub { my ($conn, $code, $reason) = @_; ... },
        on_error    => sub { my ($conn, $err) = @_; ... },
        on_pong     => sub { my ($conn, $payload) = @_; ... },
    );

Returns an EV::Websockets::Connection object. C<$is_final> is always 1
(messages are fully reassembled before delivery).

C<$headers> in C<on_connect> is a hashref of response headers from the server
(Set-Cookie, Content-Type, Server).

=head3 listen(%options)

Create a WebSocket listener. Returns the port number being listened on
(useful if port 0 was requested).

    my $port = $ctx->listen(
        port             => 0,          # 0 to let OS pick a port
        name             => 'server',   # optional vhost name (default: 'server')
        ssl_cert         => 'cert.pem', # optional, enables TLS
        ssl_key          => 'key.pem',  # required if ssl_cert is set
        ssl_ca           => 'ca.pem',   # optional CA chain
        max_message_size => 1048576,    # optional, 0 = unlimited
        headers          => { 'Set-Cookie' => 'session=abc123' }, # response headers
        on_connect  => sub { my ($conn, $headers) = @_; ... },
        on_message  => sub { my ($conn, $data, $is_binary, $is_final) = @_; ... },
        on_close    => sub { my ($conn, $code, $reason) = @_; ... },
        on_error    => sub { my ($conn, $err) = @_; ... },
        on_pong     => sub { my ($conn, $payload) = @_; ... },
    );

C<$headers> in C<on_connect> is a hashref of client request headers
(Path, Host, Origin, Cookie, Authorization, Sec-WebSocket-Protocol, User-Agent).
C<Path> is the request URI (e.g., C</chat>).

C<headers> is an optional hashref of headers to inject into the HTTP upgrade
response (e.g., C<Set-Cookie>).

=head3 connections

Returns a list of all currently connected Connection objects.

    my @conns = $ctx->connections;
    $_->send("broadcast!") for @conns;

=head3 adopt(%options)

Adopt an existing IO handle (socket).

    my $conn = $ctx->adopt(
        fh               => $socket_handle,
        initial_data     => $already_read_bytes, # optional pre-read data
        max_message_size => 1048576,
        on_connect => sub { my ($conn, $headers) = @_; ... },
        on_message => sub { my ($conn, $data, $is_binary, $is_final) = @_; ... },
        on_close   => sub { my ($conn, $code, $reason) = @_; ... },
        on_error   => sub { my ($conn, $err) = @_; ... },
        on_pong    => sub { my ($conn, $payload) = @_; ... },
    );

Once adopted, C<libwebsockets> takes ownership of the file descriptor. You should
stop using the Perl handle for IO. C<$headers> in C<on_connect> is always
C<undef> for adopted connections.

If you already read data from the socket (e.g., the HTTP upgrade request),
pass it via C<initial_data> so lws can process the handshake.

=head2 EV::Websockets::Connection

Represents a WebSocket connection.

=head3 send($data)

Send text data over the connection.

=head3 send_binary($data)

Send binary data over the connection.

=head3 send_ping($data)

Send a Ping frame. Payload is silently truncated to 125 bytes per RFC 6455.

=head3 send_pong($data)

Send a Pong frame. Payload is silently truncated to 125 bytes per RFC 6455.

=head3 get_protocol

Returns the negotiated C<Sec-WebSocket-Protocol> value, or C<undef>.

=head3 peer_address

Returns the peer IP address as a string, or C<undef>.

=head3 close($code, $reason)

Close the connection with the given status code and reason.

=head3 pause_recv

Stop receiving data from this connection (flow control).

=head3 resume_recv

Resume receiving data after C<pause_recv>.

=head3 is_connected

Returns true if the connection is established and open.

=head3 is_connecting

Returns true if the connection is in progress.

=head3 state

Returns the current state as a string: "connecting", "connected", "closing",
"closed", or "destroyed".

=head1 DEBUGGING

    EV::Websockets::_set_debug(1);

Enables verbose debug output from both the module and libwebsockets.
In tests, gate on C<$ENV{EV_WS_DEBUG}>:

    EV::Websockets::_set_debug(1) if $ENV{EV_WS_DEBUG};

=head1 URL FORMATS

The module supports both C<ws://> and C<wss://> (TLS) URLs.

=head1 SEE ALSO

L<EV>, L<Alien::libwebsockets>, L<libwebsockets|https://libwebsockets.org/>

=head1 AUTHOR

vividsnow

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
