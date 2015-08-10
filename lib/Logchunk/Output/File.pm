package Logchunk::Output::File;

use Moo;
use File::Spec;
use File::Path qw(make_path);
use File::Basename;
use JSON::XS;
use Data::Dumper;

has file => (
  is       => 'ro',
  required => 1,
  isa      => sub { 
    File::Spec->file_name_is_absolute($_[0]) or 
      die "Logchunk::Output::File: file must be an absolute path";
  },
  trigger  => sub {
    my $self = shift;
    my $val  = shift;

    my $full_file = $val;
    my ($file, $dir) = fileparse($full_file);
    make_path($dir, {owner => 'root', group => 'root'});
  },
);

has sort_keys => (
  is       => 'ro',
  required => 0,
  default  => sub { 0 },
  coerce   => \&_truthiness,
);

#Create and store a JSON::XS object.  Only use if sorting is enabled
#Saves creating the object every time we want to encode key sorted json.
has json_obj => (
  is       => 'ro',
  required => 1,
  default  => sub { JSON::XS->new()->utf8()->canonical(); },
);

sub submit {
  my $self = shift;
  my $data = shift || return;
  my $file = $self->file();
  my $json;
  
  if ( $self->sort_keys() ) {
    $json = $self->json_obj()->encode($data);
  }
  else {
    #Faster.
    $json = encode_json($data);
  }

  if ( open(my $fh, '>>', $self->file()) ) {
    print $fh $json."\n";
  }
  else {
    print "Failed to open $file: $!";
  }
}

sub _truthiness {
  my $val     = shift or return 0;
  my $default = shift or 0;
  my $bool;

  my @true_values  = ( 1, '1', 'yes', 'y', 'true'  );
  my @false_values = ( 0, '0', 'no' , 'n', 'false' );

  if ( $default ) {
    #Default to true, test for false values
    $bool = (grep { "$_" eq lc("$val") } @false_values) ? 0 : 1;
  }
  else {
    #Default to false, test for true values
    $bool = (grep { "$_" eq lc("$val") } @true_values) ? 1 : 0;
  }
  
  return $bool;
}

1;
