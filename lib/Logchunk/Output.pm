package Logchunk::Output;

use Moo;
use Module::Pluggable search_path => ['Logchunk::Output'], require => 1;
use Data::Dumper;

my %plugin_lookup = map { my $o = $_; $o =~ s/^.+:://; lc($o) => $_ } Logchunk::Output->plugins();

sub plugin_exists {
  my $self   = shift;
  my $plugin = shift;
  $plugin or return;
  return $plugin_lookup{$plugin} ? 1 : 0;
}

sub plugin {
  my $self   = shift;
  my $plugin = shift;
  $plugin or return;
  return $plugin_lookup{$plugin} ? $plugin_lookup{$plugin} : undef;
}

1;
