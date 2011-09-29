package Async::Util;
use strict;
use warnings;
use Carp;
use Exporter;
use Scalar::Util qw(weaken);

our @ISA               = qw(Exporter);
our @EXPORT_OK         = qw(apply apply_ignore apply_each chain);
my  $DEFAULT_AT_A_TIME = 100;

#
# Applies the provided coderef to a list of inputs one at a time.  Upon
# completion $cb is passed a list of outputs.
#
sub apply {
    my (%args) = @_;

    my $action    = $args{action};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'action' is required/ if !defined $action;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'action' must be a CodeRef/   if ref $action ne 'CODE';
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

            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            my $after_work_wrapper = sub {
                my $i = $index;
                $after_work->(@_, $i);
            };

            $action->($input, $after_work_wrapper);

            weaken $after_work_wrapper;
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

#
# apply_ignore
#
# Like a apply except that any output passed to the action's callback is
# ignored.  It isn't tracked and it isn't passed to $cb.  For this reason
# apply_ignore() is faster than apply();
#
sub apply_ignore {
    my (%args) = @_;

    my $action    = $args{action};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/ if !defined $inputs;
    croak q/Argument 'action' is required/ if !defined $action;
    croak q/Argument 'cb' is required/     if !defined $cb;

    croak q/Argument 'inputs' must be an ArrayRef/ if ref $inputs ne 'ARRAY';
    croak q/Argument 'action' must be a CodeRef/   if ref $action ne 'CODE';
    croak q/Argument 'cb'     must be a CodeRef/   if ref $cb ne 'CODE';

    my $inflight    = 0;
    my $cb_count    = 0;
    my $input_index = 0;
    my $any_err     = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $input_index <= $#{ $inputs }) {

            $inflight++;

            my $index = $input_index;
            my $input = $inputs->[ $index ];
            $input_index++;

            $action->($input, $after_work);
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
# apply_each
#
sub apply_each {
    my (%args) = @_;

    my $actions   = $args{actions};
    my $inputs    = $args{inputs};
    my $cb        = $args{cb};
    my $at_a_time = $args{at_a_time} || $DEFAULT_AT_A_TIME;

    croak q/Argument 'inputs' is required/  if !defined $inputs;
    croak q/Argument 'actions' is required/ if !defined $actions;
    croak q/Argument 'cb' is required/      if !defined $cb;

    croak q/Argument 'actions' must be an ArrayRef/ if ref $actions ne 'ARRAY';
    croak q/Argument 'cb' must be a CodeRef/        if ref $cb ne 'CODE';

    $inputs //= map { undef } 1..@{ $actions };

    my $inflight = 0;
    my $cb_count = 0;
    my $work_idx = 0;
    my $outputs  = [];
    my $any_err  = 0;
    my $after_work;

    my $run = sub {

        while ($inflight < $at_a_time && $work_idx <= $#{ $actions }) {

            $inflight++;

            my $index  = $work_idx;
            my $action = $actions->[ $index ];
            my $input  = $inputs->[ $index ];
            $work_idx++;

            my $after_work_wrapper = sub {
                my $i = $index;
                $after_work->($_[0], $_[1], $i);
            };

            $action->($input, $after_work_wrapper);

            weaken $after_work_wrapper;
        }
    };

    $after_work = sub {
        my ($output, $err, $index) = @_;

        $cb_count++;
        $inflight--;

        return if $any_err;

        if ($err) {
            $any_err = 1;
            $cb->(undef, $err);
        }

        $outputs->[$index] = $output;

        return $cb->($outputs) if $cb_count == @{ $actions };

        $run->();
    };

    $run->();

    return;
}

sub chain {
    my (%args) = @_;

    my $input  = $args{input};
    my $cb     = $args{cb};
    my $steps  = $args{steps};

    croak q/Argument 'finished' is required/ if !defined $cb;
    croak q/Argument 'steps' is required/    if !defined $steps;

    croak q/Argument 'finished' must be a CodeRef/ if ref $cb ne 'CODE';
    croak q/Argument 'steps' must be an ArrayRef/  if ref $steps ne 'ARRAY';

    my $run; $run = sub {
        my ($result, $err) = @_;

        return $cb->(undef, $err) if $err;

        my $next_cb = shift @{ $steps };

        return $cb->($result) if !defined $next_cb;

        $next_cb->($result, $run);
    };

    $run->($input);
    weaken $run;

    return;
}

1;
