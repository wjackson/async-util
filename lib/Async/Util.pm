package Async::Util;
use strict;
use warnings;
use Carp;
use Exporter;

our @ISA               = qw(Exporter);
our @EXPORT_OK         = qw(work apply);
my  $DEFAULT_AT_A_TIME = 100;

#
# work
#
# Applies a callback to a list of inputs.
#
sub work {
    my ($worker, $inputs, $cb, $at_a_time) = @_;

    $at_a_time ||= $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'worker' is required/ if !defined $worker;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'worker' must be a CodeRef/   if ref $worker ne 'CODE';
    croak q/Argument 'cb'     must be a CodeRef/   if ref $cb ne 'CODE';

    my $inflight    = 0;
    my $cb_count    = 0;
    my $input_index = 0;
    my $any_err     = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $input_index <= $#{ $inputs }) {

            $inflight++;

            # setup this worker cb
            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            $worker->($input, $after_work);
        }
    };

    $after_work = sub {
        my (undef, $err) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            return $cb->(undef, $err);
        }

        return $cb->() if $cb_count == @{ $inputs };

        $run->();
    };

    $run->();

    return;
}

#
# Applies the provided coderef to a list of inputs one at a time.  Upon
# completion $cb is passed a list of outputs.
#
sub apply {
    my ($worker, $inputs, $cb, $at_a_time) = @_;

    $at_a_time ||= $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'worker' is required/ if !defined $worker;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'worker' must be a CodeRef/   if ref $worker ne 'CODE';
    croak q/Argument 'cb'     must be a CodeRef/   if ref $cb ne 'CODE';

    my $inflight    = 0;
    my $cb_count    = 0;
    my $input_index = 0;
    my $outputs     = [];
    my $any_err     = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $input_index <= $#{ $inputs }) {

            $inflight++;

            # setup this worker cb
            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            my $after_work_wrapper = sub {
                my $i = $index;
                $after_work->(@_, $i);
            };

            $worker->($input, $after_work_wrapper);
        }

    };

    $after_work = sub {
        my ($output, $err, $index) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            return $cb->(undef, $err);
        }

        # store the output
        $outputs->[$index] = $output;

        return $cb->($outputs) if $cb_count == @{ $inputs };

        $run->();
    };

    $run->();

    return;
}

1;
