package Logchunk::Output::Elasticsearch;

use Moo;
use JSON::XS;
use Data::Dumper;
use Search::Elasticsearch;
use Time::Local;

has servers => (
  is       => 'ro',
  required => 1,
  coerse   => sub { ref($_[0]) and ref($_[0]) eq 'ARRAY' ? $_[0] : [ $_[0] ]; },
);

has index_prefix => (
  is       => 'ro',
  required => 1,
  default  => sub { 'syslog' },
  coerse   => sub { lc($_[0]) },
);

has index_rotation => (
  is       => 'ro',
  required => 1,
  default  => sub { 'daily' },
  isa      => sub { 
    ( grep { $_ eq lc($_[0]) } qw( daily weekly monthly yearly ) ) or
      die "index rotation must be one of daily, weekly, monthly or yearly.";
  },
  coerce   => sub { lc($_[0]) },
);

has type => (
  is       => 'ro',
  required => 1,
  default  => sub { 'syslog' },
);

has bulk_batch_size => (
  is       => 'ro',
  required => 1,
  default  => sub { 1 },
);

has bulk_queue => (
  is       => 'rw',
  required => 1,
  default  => sub { [] },
);

has es_options => (
  is       => 'ro',
  required => 1,
  isa      => sub { ref($_[0]) and ref($_[0]) eq 'HASH' or die "es_options must be a hash"; },
  default  => sub { {} },
);

has es_object => (
  is       => 'ro',
  required => 1,
  lazy     => 1,
  default  => sub {
    my $self = shift;
    my %esoptions = (
      nodes => $self->servers(),
      %{$self->es_options()},
    );
    
    return Search::Elasticsearch->new( %esoptions );
  },
);

sub submit {
  my $self = shift;
  my $data = shift or return;
  
  $self->_queue_data($data);

  if ( scalar( @{$self->bulk_queue()} >= $self->bulk_batch_size() ) ) {
    #TODO: need to test for success and conditionally empty the queue.
    $self->es_object()->bulk(
      index => $self->_index(),
      type  => $self->type(),
      body  => [
        { index => {} },
        @{$self->bulk_queue()},
      ],
    );

    $self->bulk_queue([]);
  }
}

sub _queue_data {
  my $self  = shift;
  my $data  = shift or return;
  my $queue = $self->bulk_queue();
  push(@{$queue}, $data);
  $self->bulk_queue($queue);
}

sub _index {
  # TODO: See if theres a way to avoid running this per message.
  # Would be better to run it once per period
  my $self = shift;
  my $prefix   = $self->index_prefix();
  my $rotation = $self->index_rotation();
  my $index;

  my $now_time = time;
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($now_time);
  $month = $month + 1; $year = $year + 1900;

  if ($rotation eq 'yearly' ) {
    $index = "$prefix-$year";
  }
  elsif ($rotation eq 'monthly' ) {
    $index = "$prefix-$year-$month";
  }
  elsif ($rotation eq 'weekly' ) { 
    #               now     days since Monday in Secs
    my $monday = $now_time - (($wday - 1) * 86400); #this time monday
    my ($msec,$mmin,$mhour,$mmday,$mmonth,$myear,$mwday,$myday,$misdst) = localtime($monday);
    $mmonth = $mmonth + 1; $myear = $myear + 1900;
    $index = "$prefix-WStart-$mmday-$mmonth-$myear";
  }
  elsif ($rotation eq 'daily' ) {
    $index = "$prefix-$year-$month-$mday";
  }
  else {
    #TODO: properly shouldnt get here.  The property validation should see to it.
  }

  return $index;
}
1;
