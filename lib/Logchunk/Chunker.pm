package Logchunk::Chunker;

use Moo;
use Data::Dumper;

has match_count => (
  is       => 'rw',
  default  => 0,
);

has name => (
  is       => 'ro',
  required => 1,
);

has facilities => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "facilities must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&_coerceToHash,
);

has severities => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "severities must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&_coerceToHash,
);

has hosts => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "hosts must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&_coerceToHash,
);

has programs => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "programs must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&_coerceToHash,
);

has regex => (
  is       => 'ro',
  required => 1,
);

has outputs => (
  is       => 'ro',
  required => 1,
  default  => sub {
    # If no output is supplied, use the default output with the default config
    my $self        = shift;
    my $output      = Logchunk::Config->instance()->get('default_output');
    my $output_conf = Logchunk::Config->instance()->get('outputs');
    my $obj;

    if ( $output_conf->{$output} ) {
      if ( Logchunk::Output->plugin_exists($output) ) {
        $obj = Logchunk::Output->plugin($output)->new( %{ $output_conf->{$output} } );
      }
    }

    return [ $obj ];
  },
  coerce   => sub {
    if ( ref($_[0]) eq 'ARRAY' ) { return shift; }

    # Create the specified output objects combining the specific config with the default config
    my $config             = shift || {};
    my $base_output_config = Logchunk::Config->instance()->get('outputs');
    my @outputs;

    for my $o (keys %{$config}) {
      if ( Logchunk::Output->plugin_exists($o) ) {
        my $output_config = $config->{$o};
        my $base_config   = $base_output_config->{$o} || {};

        #merge chunker specific output config over the outputs default config
        my %config = ( %{$base_config}, %{$output_config} );
        push( @outputs, Logchunk::Output->plugin($o)->new( %config ) );
      }
    }

    return \@outputs;
  },
);

sub check {
  my $self   = shift;
  my $data = shift || return;
  
  $data->{'message'} =~ s/^\s+//;
  
  # Check each of the filters. Return IF the filter has been configured and it doesn't match.
  # If it has not been configured, then assume the chunker does not want to filter
  return if ( scalar( keys( %{$self->facilities} ) ) > 0 and not $self->facilities->{ $data->{'facility'} } );
  return if ( scalar( keys( %{$self->severities} ) ) > 0 and not $self->severities->{ $data->{'severity'} } );
  return if ( scalar( keys( %{$self->hosts} ) )      > 0 and not $self->hosts->{ $data->{'source_host'} } );
  return if ( scalar( keys( %{$self->programs} ) )   > 0 and not $self->programs->{ $data->{'program'} } );

  return if ( $data->{'message'} !~ $self->regex );

  # The regex has matched!
  # Merge the capture group hash with the orginal data hash.
  my %res = (%+, %{$data});

  $self->{'match_count'} ++;
  
  return \%res;
}

sub _coerceToHash {
  my %ret; 
  if ( ref $_[0] ) {
    if ( ref $_[0] eq 'ARRAY' ) {
      %ret = map { $_ => 1 } @{$_[0]};
    }
    elsif ( ref $_[0] eq 'HASH' ) {
      %ret = %{$_[0]};
    }
  }
  else {
    $ret{$_[0]} = 1;
  }
  
  return \%ret;
}

1;
