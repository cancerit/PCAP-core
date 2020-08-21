package PCAP::Bwa::Meta;

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2018 ICGC PanCancer Project
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not see:
#   http://www.gnu.org/licenses/gpl-2.0.html
##########LICENCE##########


use PCAP;

use strict;
use autodie qw(:all);
use English qw( -no_match_vars );
use warnings FATAL => 'all';
use Carp qw( croak );

use Const::Fast qw(const);
use List::Util qw(first);
use File::Spec;
use Data::UUID;
use File::Basename;
use YAML qw(LoadFile);

use PCAP::Bam;

const my @INIT_KEYS => qw(in temp fastq paired_fq illumina_fq cram bam);
const my @REQUIRED_KEYS => qw(in temp);
const my @REQUIRED_RG_ELEMENTS => qw(SM);
const my @ALLOWED_RG_ELEMENTS => qw(ID CN DS DT FO KS LB PG PI PL PM PU SM);

our $rg_index = 1;

sub new {
  my ($class, $opts, $rg_info) = @_;
  my $self = {};
  bless $self, $class;
  $self->_init($opts, $rg_info);
  return $self;
}

sub _init {
  my ($self, $opts, $rg_info) = @_;
  croak "'rg' is auto-populated, to initialise a start value see PCAP::Bwa::Meta::set_rg_index"
    if(exists $opts->{'rg'});
  for my $key(keys %{$opts}) {
    croak "'$key' is not a valid parameter for object initialisation" unless(first {$key eq $_} @INIT_KEYS);
    croak "'$key' is not a scalar, only simple values are expected" if(ref $opts->{$key} ne q{});
    $self->{$key} = $opts->{$key};
  }

  $self->rg; # initialise RG as used by tsub and must correlate
  $self->rg_header('.', $rg_info) if($rg_info);

  for my $required(@REQUIRED_KEYS) {
    croak "'$required' must be exist" unless(exists $opts->{$required});
    croak "'$required' must be defined" unless(defined $opts->{$required});
    croak "'$required' must have value with non-0 length" unless(length $opts->{$required} > 0);
  }
  return;
}

sub in {
  my $self = shift;
  croak "'in' can only be set via new()" if(scalar @_ > 0);
  return $self->{'in'};
}

sub tstub {
  my $self = shift;
  croak "'tstub' is autopopulated" if(scalar @_ > 0);
  $self->{'tstub'} = File::Spec->catdir($self->{'temp'}, $self->rg) unless(exists $self->{'tstub'});
  return $self->{'tstub'};
}

sub fastq {
  my $self = shift;
  croak "'fastq' can only be set via new()" if(scalar @_ > 0);
  return $self->{'fastq'}; # this will create a key but not worth adding overhead to prevent
}

sub paired_fq {
  my $self = shift;
  croak "'paired_fq' can only be set via new()" if(scalar @_ > 0);
  return $self->{'paired_fq'}; # this will create a key but not worth adding overhead to prevent
}

sub illumina_fq {
  my $self = shift;
  croak "'illumina_fq' can only be set via new()" if(scalar @_ > 0);
  return $self->{'illumina_fq'};
}

sub bam_or_cram {
  my $self = shift;
  if(exists $self->{'bam'} && defined $self->{'bam'} && $self->{'bam'} == 1) {
    return 'bam';
  }
  if(exists $self->{'cram'} && defined $self->{'cram'} && $self->{'cram'} == 1) {
    return 'cram';
  }
  return q{};
}

sub rg {
  my $self = shift;
  croak "'rg' is autopopulated" if(scalar @_ > 0);
  $self->{'rg'} = $rg_index++ unless(exists $self->{'rg'});
  return $self->{'rg'};
}

sub rg_header {
  my ($self, $separator, $elements) = @_;
  if(exists $self->{'rg_header'}) {
    croak "'rg_header' has already been set" if(defined $elements);
  }
  else {
    # use the BAM object to grab existing header
    my $bam_elements = {};
    unless(exists $self->{'fastq'}) {
      my $bam = PCAP::Bam->new($self->{'in'});
      my $header_set = $bam->read_group_info->[0];
      $bam_elements = $header_set;
    }

    for my $required(@REQUIRED_RG_ELEMENTS) {
      croak "'$required' is manditory for RG header" unless(exists $elements->{$required} || exists $bam_elements->{$required});
    }

    my %all_keys;
    for my $key(sort keys %{$bam_elements}){ $all_keys{$key} = 1; }
    for my $key(sort keys %{$elements}){ $all_keys{$key} = 1; }

    my @elements = ('@RG');
    my %ids_seen;
    if(exists $elements->{'ID'}) {
      push @elements, 'ID:'.$elements->{'ID'};
    }
    else {
      if(exists $ids_seen{$self->rg}) {
        push @elements, 'ID:'._getuuid_for_rg();
      }
      else {
        push @elements, 'ID:'.$self->rg;
      }
    }
    $ids_seen{$elements[-1]} = 1;

    for my $key(sort keys %all_keys) {
      next if($key eq 'ID');
      if(exists $elements->{$key}) {
        push @elements, sprintf '%s:%s', $key, $elements->{$key};
      }
      elsif(exists $bam_elements->{$key}) {
        push @elements, sprintf '%s:%s', $key, $bam_elements->{$key};
      }
    }

    $self->{'rg_header'} = \@elements;
  }
  return join $separator, @{$self->{'rg_header'}};
}

## non-object methods

sub set_rg_index {
  my $idx = shift;
  croak "set_rg_index requires a value" unless(defined $idx);
  croak "Value must be a positive integer : $idx" if($idx !~ m/^[[:digit:]]+$/xms || $idx < 1);
  $rg_index = $idx;
  return -1;
}

sub reset_rg_index {
  return set_rg_index(1);
}

sub _getuuid_for_rg {
  my $ug = Data::UUID->new;
  $ug->create_str() =~ m/^([^-]+)/;
  return lc $1;
}

sub _validate_yaml {
  my ($meta_yaml) = @_;
  my $yaml_obj = LoadFile( $meta_yaml );
  # if all ID's aren't unique we generate time based UUID and take the first section as the new ID
  # this will not prevent universal clash but will within a BAM file.
  my %ids;
  for my $rg_key(keys %{$yaml_obj->{'READGRPS'}}) {
    my $rg_rec = $yaml_obj->{'READGRPS'}->{$rg_key};

    for my $ele_key(keys %{$rg_rec}) {
      my $uc_key = uc $ele_key;
      unless(first {$uc_key eq $_} @ALLOWED_RG_ELEMENTS) {
        croak sprintf q{Key '%s' is not a valid RG field}, $ele_key;
      }
      if($ele_key ne $uc_key) {
        # upper/lower mismatch
        $rg_rec->{$uc_key} = $rg_rec->{$ele_key};
        delete $rg_rec->{$ele_key};
      }

      # replace any tabs with space:
      $rg_rec->{$uc_key} =~ s/\t/ /g;
    }

    # common error, force upper
    if(exists $rg_rec->{'PL'}) {
      $rg_rec->{'PL'} = uc $rg_rec->{'PL'};
    }

    if(! exists $rg_rec->{'ID'} || exists $ids{$rg_rec->{'ID'}} ) {
      $rg_rec->{'ID'} = _getuuid_for_rg();
    }
    $ids{$rg_rec->{'ID'}} = 1;
  }
  return $yaml_obj;
}

sub files_to_meta {
  my ($tmp, $files, $sample, $meta_yaml) = @_;
  croak "Requires tmpdir and array-ref of files" unless(defined $tmp && defined $files);
  croak "Directory must exist: $tmp" unless(-d $tmp);
  croak '\$files must be an array-ref' unless(ref $files eq 'ARRAY');
  croak "Some files must be provided" unless(scalar @{$files} > 0);
  my %seen_paired_stub;
  my $are_xxams = 0;
  my $are_paired_fq = 0;
  my $are_inter_fq = 0;
  my @meta_files;

  my $link_tmp = File::Spec->catdir($tmp, 'links');
  mkdir($link_tmp) unless(-e $link_tmp);
  my @linked_files;
  for my $file(@{$files}) {
    my $fname = fileparse($file);
    my $link = File::Spec->catfile($link_tmp, $fname);
    croak "Multiple files have the same filename (not path), name must be unique: $file" if(first { $_ eq $link } @linked_files);
    symlink($file, $link) unless(-l $link);
    push @linked_files, $link;
  }

  my $yaml_obj;
  if($meta_yaml) {
    $yaml_obj = _validate_yaml( $meta_yaml );
  }

  if($yaml_obj && exists $yaml_obj->{'SM'} && $sample ne $yaml_obj->{'SM'}) {
    croak sprintf q{Sample name provided at command line (%s) doesn't match metadata entry for 'SM' (%s)}, $sample, $yaml_obj->{'SM'};
  }

  # ensure ordered in way that makes end 1 of fastq first in list
  @linked_files = sort {fileparse($a) cmp fileparse($a)} @linked_files;

  for my $file(@linked_files) {
    my $fname = fileparse($file);
    my $meta = {'temp' => $tmp};

    my ($fq, $fq_ext) = is_fastq_ext($file);
    if(defined $fq_ext) {
      my ($fq_stub, $end) = parse_fastq_filename($fq);
      if(defined $end) {
        # must be paired fq
        next if(exists $seen_paired_stub{$fq_stub});
        $seen_paired_stub{$fq_stub} = 1;
        die "Unable to find file for read 1, for ${fq_stub}_X.${fq_ext}\n" unless(-e "${fq_stub}_1.$fq_ext" || -e "${fq_stub}_R1_001.$fq_ext");
        die "Unable to find file for read 2, for ${fq_stub}_X.${fq_ext}\n" unless(-e "${fq_stub}_2.$fq_ext" || -e "${fq_stub}_R2_001.$fq_ext");
        die "File for read 1 is empty: ${fq_stub}_X.${fq_ext}\n" unless(-s "${fq_stub}_1.$fq_ext" || -s "${fq_stub}_R1_001.$fq_ext");
        die "File for read 2 is empty: ${fq_stub}_X.${fq_ext}\n" unless(-s "${fq_stub}_2.$fq_ext" || -s "${fq_stub}_R2_001.$fq_ext");
        $meta->{'illumina_fq'} = ( $end=~m/R[12]_001/ ? 1 : 0 );
        $meta->{'paired_fq'} = 1;
        $are_paired_fq = 1;
      }
      else { # interleaved fq
        die "File does not exist: $fq_stub.$fq_ext\n" unless(-e "$fq_stub.$fq_ext");
        die "File is empty: $fq_stub.$fq_ext\n" unless(-s "$fq_stub.$fq_ext");
        $are_inter_fq = 1;
      }

      $meta->{'in'} = $fq_stub;
      $meta->{'fastq'} = $fq_ext;

    }
    elsif($file =~ m/\.bam$/) {
      die "File does not exist: $file\n" unless(-e $file);
      die "File is empty: $file\n" unless(-s $file);
      $are_xxams = 1;
      $meta->{'in'} = $file;
      $meta->{'bam'} = 1;
    }
    elsif($file =~ m/\.cram$/) {
      die "File does not exist: $file\n" unless(-e $file);
      die "File is empty: $file\n" unless(-s $file);
      $are_xxams = 1;
      $meta->{'in'} = $file;
      $meta->{'cram'} = 1;
    }
    else {
      die "$file is not an expected input file type.\n";
    }

    if($are_xxams + $are_paired_fq + $are_inter_fq > 1) {
      die "ERROR: BAM|CRAM, paired FASTQ and interleaved FASTQ file types cannot be mixed, please choose one type\n";
    }

    my $rg_rec;
    if($yaml_obj) {
      $rg_rec = $yaml_obj->{'READGRPS'}->{$fname};
      unless($rg_rec) {
        croak sprintf q{No readgroup info defined for input data %s in file %s}, $fname, $meta_yaml;
      }
      $rg_rec->{'SM'} = $sample;
    }

    my $meta_ob = PCAP::Bwa::Meta->new($meta, $rg_rec);
    push @meta_files, $meta_ob;

    unless($yaml_obj) {
      # until we have proper meta file support need to add sample
      $meta_ob->rg_header('.', { 'SM' => $sample }) if(defined $sample);
    }

  }
  return \@meta_files;
}

sub is_fastq_ext {
  my $file = shift;
  my $ext;
  if($file =~ s/\.(f(?:ast)?q(?:\.gz)?)$//) {
    $ext = $1;
  }
  return ($file, $ext);
}

sub parse_fastq_filename {
  my $fastq = shift; # shouldn't have extension by now
  my $end;
  if($fastq =~ s/_([12]|R[12]_001)$//) {
    $end = $1;
  }
  return ($fastq, $end);
}

1;

__END__

=head1 NAME

PCAP::Bwa::Meta - Object to contain information about input files for mapping.

=head2 Synopsis

Please use the following to generate these objects:

  PCAP::Bwa::Meta::files_to_meta($tmp, \@files)

This accepts bam, paired fastq and interleaved fastq.  Fastq files can be gzip compressed.
The calling program should decide which type of files it is able to process.

=head2 Constructor

=over 4

=item new

Generates the object when called with hashref of options, please use
L<files_to_meta|PCAP::Bwa::Meta/files_to_meta> to generate the objects.

=item files_to_meta

Generates a set of PCAP::Bwa::Meta objects based on the input files.

  my $meta_set = PCAP::Bwa::Meta::files_to_meta($tmpdir, \@files);

Returns a array reference of checked and pre-processed information.

=head2 Object Methods

=over 4

=item in

Can store BAM, FASTQ or INTERLEAVED FASTQ

Retrieve the original file path.  In the case of a paired FASTQ file this will be truncated back to
the common part of the filename so that both elements are represented by one object.

  FASTQ 1: /somepath/xxx_1.fq.gz
  FASTQ 2: /somepath/xxx_2.fq.gz

  in = /somepath/xxx

=item tstub

A path for files generated from the input file represented here.  The path is constructed from
'temp' and the rg_id.

=item fastq

Extension type of fastq file, see L<parser_fastq_filename|PCAP::Bwa::Meta/parse_fastq_filename>.

=item paired_fq

Flag to indicate that content of L<in()|PCAP::Bwa::Meta/in> is a stub for paired fastq rather
than an interleaved fastq, see L<parser_fastq_filename|PCAP::Bwa::Meta/parse_fastq_filename>.

Added for future compatibility with files that can be used with 'BWA mem'.

=item fastq

When input is some form of fastq this returns the extension, otherwise undef.

=item illumina_fq

If paired FASTQ names end with _R[12]_001, this returns true. Returns false if they end with _[12].

=item rg

Returns the RG_ID that has been applied to this input.

=item rg_header

Call this with a hash of RG header tags to generate and retrieve the header, e.g.

  $meta->rg_header(q{\t}, -SN => 'some_sample_name', -LB => 'library_name');

After generation you can retrieve with the required separator ('\t' for passing string to bwa on
command line, "\t" for direct use):

  print $meta->rg_header(qq{\t})."\n";

  $to_pass_to_command = $meta->rg_header(q{\t});

SN is the only required element at present.  See the Samtools L<specification|http://samtools.sourceforge.net/SAMv1.pdf>
for details.

=back

=head2 Utility Methods

=over 4

=item set_rg_index

  PCAP::Bwa::Meta::set_rg_index($int);

Initialise the RG ID value to start at this INTEGER.

=item reset_rg_index

  PCAP::Bwa::Meta::next_rg_index();
    # or
  &PCAP::Bwa::Meta::next_rg_index;

Reset the RG ID value to 1.

=item is_fastq_ext

Determines if the file is some form of fastq file.  If not fastq original filename is returned. When
fastq the file extension is removed from the end of the filename and returned as the second argument.

  my ($new_name, $ext) = PCAP::Bwa::Meta::is_fastq_ext('1_1.fq');
    # $new_name = 1_1
    # $ext = 'fq'

  my ($new_name, $ext) = PCAP::Bwa::Meta::is_fastq_ext('1_1.bam');
    # $new_name = 1_1.bam
    # $ext = undef

Understands the following as fastq files:

  fastq
  fastq.gz
  fq
  fq.gz

=item parse_fastq_filename

Takes a fastq filename after removal of the extension (see L<is_fastq_ext()/PCAP::Bwa::Meta/is_fastq_ext>
and determines if file is read1, read2 or interleaved fastq.

Expects paired FASTQ names to end with one the following. Assumes interleaved FASTQ otherwise.

  _1 and _2 - PCAP's original naming requirement
  _R1_001 and _R2_001 - Illumina's naming requirement; Require 3 digit suffix to be 001 to avoid split FASTQs

=back
