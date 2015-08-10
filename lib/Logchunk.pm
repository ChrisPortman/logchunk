package Logchunk;

use Moo;
use JSON::XS;
use Beanstalk::Client;
use Data::Dumper;
use Logchunk::Config;
use Logchunk::Chunker;
use Logchunk::Output;


has config => (
  is       => 'rw',
  required => 1,
);

has bsClient => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $self = shift;
    Beanstalk::Client->new( {
      server       => $self->config->get('beanstalk_server') || 'localhost',
      default_tube => $self->config->get('beanstalk_tube')   || 'syslog',
    } );
  }, 
);

has chunkers => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $self = shift;
    my @chunkers;
    
    if ( $self->config->get('chunkers') ) {
      for my $name ( keys %{$self->config->get('chunkers')} ) {
        my $c = $self->config->get('chunkers')->{$name};
        $c->{'name'} = $name;
        push @chunkers, Logchunk::Chunker->new(%{$c});
      }
    }
    
    return \@chunkers;
  },
);

has default_output => (
  is       => 'ro',
  required => 1,
  default  => sub {
    my $self        = shift;
    my $output      = Logchunk::Config->instance()->get('default_output');
    my $output_conf = Logchunk::Config->instance()->get('outputs');
    my $obj;

    if ( $output_conf->{$output} ) {
      if ( Logchunk::Output->plugin_exists($output) ) {
        $obj = Logchunk::Output->plugin($output)->new( %{ $output_conf->{$output} } );
      }
    }

    return $obj;
  },
);

sub run {
  my $self  = shift;
  my $loops = 0;
  my @optimised_chunker_list = @{$self->chunkers};

  $self->connect_beanstalk();

  while (1) {
    my $job  = $self->get_job();
    my $data = $job->data();
    $job->delete();
    
    eval {
      $data = decode_json($data);
    };
    next if $@;

    #Re-optimise the order of chunkers every 100 loops, put the ones with the most matches up front.
    unless ( $loops % 100 ) {
      @optimised_chunker_list = sort { $b->{'match_count'} <=> $a->{'match_count'} } @{$self->chunkers};
    }

    my $submitted = 0;

    CHUNKER:
    for my $chunker ( @optimised_chunker_list ) {
      if ( my $chunked = $chunker->check($data) ) {
        $data = $chunked;
        for my $output ( @{ $chunker->outputs() } ) {
          $output->submit($data);
        }
        $submitted = 1;
        last CHUNKER;
      }
    }
    
    unless ($submitted) {
      #submit using the default output
      $self->default_output() and $self->default_output()->submit($data);
    }

    $loops ++;
  }
}

sub get_job {
  my $self = shift;
  return $self->bsClient->reserve();
}

sub connect_beanstalk {
  my $self = shift;

  while ( not $self->bsClient->socket() ) {
    $self->bsClient->connect();

    if ( my $error = $self->bsClient->error() ) {
      print "ERROR: $error\n";
    }

    unless ( $self->bsClient->socket() ) {
      print "ERROR: Couldn't connect to beanstalk\n";
      sleep 10;
    }
  }
}


1;
