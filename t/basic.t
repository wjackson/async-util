use strict;
use warnings;
use Test::More;
use List::MoreUtils qw(any);
use AnyEvent;
use Carp;

use ok 'Async::Util', qw(work apply);

{

    my @doubled;

    my $doubler = sub {
        my ($input, $cb) = @_;

        push @doubled, $input*2;

        my $err = undef;
        $cb->(undef, $err);
    };

    my $cv = AE::cv;

    work( $doubler, [ 1..3 ], sub { $cv->send(@_) } );

    my (undef, $err) = $cv->recv;

    confess $err if $err;

    ok any( sub { $_ == 2 }, @doubled ), '1 was doubled';
    ok any( sub { $_ == 4 }, @doubled ), '2 was doubled';
    ok any( sub { $_ == 6 }, @doubled ), '3 was doubled';
}

{
    my $double = sub {
        my ($input, $cb) = @_;
        my $err = undef;
        $cb->($input*2, $err);
    };

    my $cv = AE::cv;

    apply( $double, [ 1..3 ], sub { $cv->send(@_) } );

    my ($doubled, $err) = $cv->recv;

    confess $err if $err;

    is_deeply $doubled, [ 2, 4, 6 ], 'inputs doubled';
}

done_testing;
