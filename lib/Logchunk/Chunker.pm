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
  coerce  => \&coerceToHash,
);

has severities => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "severities must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&coerceToHash,
);

has hosts => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "hosts must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&coerceToHash,
);

has programs => (
  is => 'ro',
  default => sub { {} },
  isa     => sub { die "programs must be a hash" unless ref($_[0]) eq 'HASH'; },
  coerce  => \&coerceToHash,
);

has regex => (
  is       => 'ro',
  required => 1,
);

sub check {
  my $self   = shift;
  my $data = shift || return;
  
  $data->{'message'} =~ s/^\s+//;
  
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

sub coerceToHash {
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
