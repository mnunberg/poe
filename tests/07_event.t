#!/usr/bin/perl -w
# $Id$

# Tests FIFO, alarm, select and Tk postback events using Event's event
# loop.

use strict;
use lib qw(./lib ../lib);
use Symbol;

# Turn on all asserts.
sub POE::Kernel::ASSERT_DEFAULT () { 1 }

# Skip if Event isn't here.
BEGIN {
  eval 'use Event';
  unless (exists $INC{'Event.pm'}) {
    eval 'use TestSetup qw(0 the Event module is not installed)';
  }
}

use TestSetup qw(5);
use POE qw(Wheel::ReadWrite Filter::Line Driver::SysRW);

# Congratulate ourselves for getting this far.
print "ok 1\n";

# I/O session

sub io_start {
  my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];

  # A pipe.

  $heap->{pipe_read}  = gensym();
  $heap->{pipe_write} = gensym();

  eval {
    pipe($heap->{pipe_read}, $heap->{pipe_write})
      or die "can't create pipe: $!";
  };

  # Can't test file events.

  if ($@ ne '') {
    print "skip 2 # $@\n";
  }

  else {
    # The wheel uses read and write file events internall, so they're
    # tested here.
    $heap->{pipe_wheel} =
      POE::Wheel::ReadWrite->new
        ( InputHandle  => $heap->{pipe_read},
          OutputHandle => $heap->{pipe_write},
          Filter       => POE::Filter::Line->new(),
          Driver       => POE::Driver::SysRW->new(),
          InputState   => 'ev_pipe_read',
        );

    # And a timer loop to test alarms.
    $kernel->delay( ev_pipe_write => 1 );
  }

  # And counters to monitor read/write progress.

  $heap->{write_count} = 0;
  $heap->{read_count}  = 0;

  # And an idle loop.

  $heap->{idle_count} = 0;
  $kernel->yield( 'ev_idle_increment' );

  # And an independent timer loop to test it separately from pipe
  # writer's.

  $heap->{timer_count} = 0;
  $kernel->delay( ev_timer_increment => 0.5 );
}

sub io_pipe_write {
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  $heap->{pipe_wheel}->put( scalar localtime );
  $kernel->delay( ev_pipe_write => 1 ) if ++$heap->{write_count} < 10;
}

sub io_pipe_read {
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  $heap->{read_count}++;

  # Shut down the wheel if we're done.
  delete $heap->{pipe_wheel} if $heap->{write_count} == 10;
}

sub io_idle_increment {
  if (++$_[HEAP]->{idle_count} < 10) {
    $_[KERNEL]->yield( 'ev_idle_increment' );
  }
}

sub io_timer_increment {
  if (++$_[HEAP]->{timer_count} < 10) {
    $_[KERNEL]->delay( ev_timer_increment => 0.5 );
  }
}

sub io_stop {
  my $heap = $_[HEAP];

  if ($heap->{read_count}) {
    print "not " unless $heap->{read_count} == $heap->{write_count};
    print "ok 2\n";
  }

  print "not " unless $heap->{idle_count};
  print "ok 3\n";

  print "not " unless $heap->{timer_count};
  print "ok 4\n";
}

# Start the I/O session.

POE::Session->create
  ( inline_states =>
    { _start             => \&io_start,
      _stop              => \&io_stop,
      ev_pipe_read       => \&io_pipe_read,
      ev_pipe_write      => \&io_pipe_write,
      ev_idle_increment  => \&io_idle_increment,
      ev_timer_increment => \&io_timer_increment,
    },
    options => { trace => 1 },
  );

# Main loop.

$poe_kernel->run();

# Congratulate ourselves on a job completed, regardless of how well it
# was done.
print "ok 5\n";

exit;
