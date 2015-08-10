#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use lib './lib';
use Logchunk;

my $workers    = 1;
my $configFile = '/etc/logchunks.conf';
my @pids;

GetOptions (
  "workers=i"     => \$workers,
  "config_file=s" => \$configFile,
);

my $config = Logchunk::Config->instance( file => $configFile );

while ( scalar(@pids) < $workers ) {
  if (my $pid = fork()) {
    push(@pids, $pid);
  }
  else {
    Logchunk->new( config => $config )->run();
    exit 0;
  }
}

for my $p (@pids) {
  waitpid $p, 0;
}

exit 0;
