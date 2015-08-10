package Logchunk::Config;

use Moo;
with 'MooX::Singleton';
use YAML 'LoadFile';

has file => (
  is       => 'ro',
  required => 1,
  isa      => sub {
    die "Config file does not exist\n" unless -f $_[0];
  },
);

has config => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $c;
    eval {
      $c = LoadFile($_[0]->file);
    };
    die "Can't load config from file: $@" if $@;
    return $c;
  },
);

sub get {
  my $self = shift;
  my $key  = shift || return;
  return $self->config->{$key};
}

1;
