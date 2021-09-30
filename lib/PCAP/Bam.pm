package PCAP::Bam;

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2018 ICGC PanCancer Project
# Copyright (C) 2018-2021 Cancer, Ageing and Somatic Mutation, Genome Research Limited
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
use Const::Fast qw(const);
use File::Spec;
use Bio::DB::HTS;
use Carp qw(croak);
use List::Util qw(first);
use Data::UUID;

use PCAP::Threaded;

const my $BAMCOLLATE => q{(%s colsbs=268435456 collate=1 reset=1 exclude=SECONDARY,QCFAIL,SUPPLEMENTARY classes=F,F2 T=%s filename=%s level=1 > %s)};

const my $CRAM_CHKSUM => q{md5sum %s | perl -ne '/^(\S+)/; print "$1";' > %s.md5};
const my $BAM_STATS => q{ -i %s -o %s -@ %d};

sub new {
  my ($class, $bam) = @_;
  my $self = {};
  if(defined $bam) {
    $self->{'bam'} = $bam;
    $self->{'md5'} = $bam.'.md5' if(-e $bam.'.md5');
  }
  bless $self, $class;
  return $self;
}

sub rg_line_for_output {
  my ($bam, $sample, $uniq_id, $existing_rgid) = @_;
  my $sam = sam_ob($bam);
  my $header = $sam->header->text;
  my $rg_line;
  while($header =~ m/^(\@RG\t[^\n]+)/xmsg) {
    my $new_rg = $1;
    my ($this_id) = $new_rg =~ m/\tID:([^\t]+)/;
    next if(defined $existing_rgid && $this_id ne $existing_rgid);
    die "BAM file appears to contain data for multiple readgroups, not supported unless 'existing_rgid' is found: \n\n$header\n" if(defined $rg_line);
    $rg_line = $new_rg;
    if($uniq_id) {
      my $uuid = lc Data::UUID->new->create_str;
      $rg_line =~ s/\tID:[^\t]+/\tID:$uuid/;
    }
    if(defined $sample) {
      unless($rg_line =~ s/\tSM:[^\t]+/\tSM:$sample/) {
        $rg_line .= "\tSM:$sample";
      }
    }
    $rg_line =~ s/\t/\\t/g;
  }
  return ($rg_line, $sam); # also return the SAM object
}

sub bam_to_grouped_bam {
  # uncoverable subroutine
  my ($index, $options) = @_;
  # uncoverable branch true
  # uncoverable branch false
  return 1 if(exists $options->{'index'} && $index != $options->{'index'});
  my $tmp = $options->{'tmp'};
  # uncoverable branch true
  # uncoverable branch false
  return if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), $index);
  my $inputs = $options->{'meta_set'};
  my $bamcollate =  _which('bamcollate2') || die "Unable to find 'bamcollate2' in path";
  my $command = sprintf $BAMCOLLATE, $bamcollate, File::Spec->catfile($tmp, "collate.$index"), $inputs->[$index-1]->in, $inputs->[$index-1]->tstub.'.bam';
  PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), $command, $index);
  return PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), $index);
}

sub merge_or_mark_lanes {
  my ($options, @bams) = @_;
  my $tmp = $options->{'tmp'};

  my $marked = File::Spec->catdir($options->{'outdir'}, $options->{'sample'});
  if($options->{'cram'}) { $marked .= '.cram'; }
  else { $marked .= '.bam'; }

  return $marked if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), 0);

  my @commands = ('set -o pipefail');

  my $helper_threads = $options->{'threads'};

  my $input_str = join q{ }, sort @bams;

  my $strmd_tmp = File::Spec->catfile($tmp, 'strmdup');
  my $brc_tmp = File::Spec->catfile($tmp, 'brcTmp');

  my %tools;
  for my $tool(qw(bam_stats samtools md5sum)) {
    $tools{$tool} = _which($tool) || die "Unable to find '$tool' in path";
  }

  my $out_fmt = 'bam';
  my $idx_type = 'bai';
  my $idx_csi_flag = q{};
  if($options->{'cram'}) {
    $idx_type = 'crai';
    $out_fmt = 'cram';
    $out_fmt .= ',seqs_per_slice='.$options->{'seqslice'};
  }
  elsif(exists $options->{'csi'}) {
    # only valid for bam
    $idx_type = 'csi';
    $idx_csi_flag = '-c';
  }

  if(defined $options->{'nomarkdup'} && $options->{'nomarkdup'} == 1) {
      my $idx = q{};
      unless($options->{'noindex'}) {
        $idx = sprintf q{%s index -@ %d %s - %s.%s},
                        $tools{samtools}, $helper_threads, $idx_csi_flag, $marked, $idx_type;
      }

      my $namesrt = q{};
      $namesrt = q{-n} if($options->{'qnamesort'});

      my $merge    = sprintf q{%s merge %s -u -@ %d - %s},
                              $tools{samtools}, $namesrt, $helper_threads, $input_str;
      my $compress = sprintf q{%s view -T %s --output-fmt %s -@ %d -},
                              $tools{samtools}, $options->{reference}, $out_fmt, $helper_threads;
      my $md5      = sprintf q{%s -b > %s.md5},
                            $tools{md5sum}, $marked;
      my $stats    = sprintf q{%s -o %s.bas -@ %d},
                              $tools{bam_stats}, $marked, $helper_threads;
      push @commands, qq{$merge | pee "$stats" "$compress | pee '$idx' '$md5' 'cat > $marked'"};
  }
  else {
    my $merge;
    my $markdup;
    if(exists $options->{legacy}) {
      my $mmflagmod = _which('mmFlagModifier') || die "Unable to find 'mmFlagModifier' in path";
      my $bammarkdups = _which('bammarkduplicates2') || die "Unable to find 'bammarkduplicates2' in path";
      my $bammerge = _which('bammerge') || die "Unable to find 'bammerge' in path";
      my $bm_tmp = File::Spec->catfile($tmp, 'bmTmp');

      $input_str =~ s/ / I=/g;
      $merge = sprintf '%s SO=%s tmpfile=%s level=0 I=%s', $bammerge, 'coordinate', $bm_tmp, $input_str;

      my $mmQcRemove = sprintf '%s --remove -l 0 -@ %d', $mmflagmod, $helper_threads;
      my $bammarkdup = sprintf '%s tmpfile=%s M=%s.met level=0 markthreads=%d', $bammarkdups, $strmd_tmp, $marked, $helper_threads;
      my $mmQcReplace = sprintf '%s --replace -l 0 -@ %d', $mmflagmod, $helper_threads;

      $markdup = sprintf q{%s | %s | %s}, $mmQcRemove, $bammarkdup, $mmQcReplace;
    }
    else {
      $merge   = sprintf q{%s merge -u -@ %d - %s},
                         $tools{samtools}, $helper_threads, $input_str;
      $markdup = sprintf q{%s markdup --mode %s --output-fmt bam,level=0 -S --include-fails -T %s -@ %d -f %s.met - -},
                         $tools{samtools}, $options->{dupmode}, $strmd_tmp, $helper_threads, $marked;
    }
    my $compress = sprintf q{%s view -T %s --output-fmt %s -@ %d -},
                           $tools{samtools}, $options->{reference}, $out_fmt, $helper_threads;
    my $idx      = sprintf q{%s index -@ %d %s - %s.%s},
                           $tools{samtools}, $helper_threads, $idx_csi_flag, $marked, $idx_type;
    my $md5      = sprintf q{%s -b > %s.md5},
                           $tools{md5sum}, $marked;
    my $stats    = sprintf q{%s -o %s.bas -@ %d},
                           $tools{bam_stats}, $marked, $helper_threads;
    push @commands, qq{$merge | $markdup | pee "$compress | pee 'cat > $marked' '$idx' '$md5'" "$stats" };
  }

  if($options->{'cram'}) {
    push @commands, sprintf $CRAM_CHKSUM, $marked, $marked;
  }

  PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), \@commands, 0);
  PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), 0);
  return $marked;
}

sub merge_and_mark_dup {
  # uncoverable subroutine
  my ($options, $source) = @_;
  my $tmp = $options->{'tmp'};

  my $marked = File::Spec->catdir($options->{'outdir'}, $options->{'sample'});
  if($options->{'cram'}) { $marked .= '.cram'; }
  else { $marked .= '.bam'; }

  return $marked if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), 0);

  my @commands = ('set -o pipefail');

  my $helper_threads = $options->{'threads'};

  my @bams;
  if(defined $source) {
    opendir(my $dh, $source);
    while(my $file = readdir $dh) {
      next unless($file =~ m/_sorted\.bam$/);
      push @bams, File::Spec->catfile($source, $file);
    }
    closedir $dh;

  }
  else {
    for(@{$options->{'meta_set'}}) {
      push @bams, $_->tstub.'_sorted.bam';
    }
  }

  my $input_str = join q{ }, sort @bams;

  my $strmd_tmp = File::Spec->catfile($tmp, 'strmdup');
  my $brc_tmp = File::Spec->catfile($tmp, 'brcTmp');

  my %tools;
  for my $tool(qw(samtools bam_stats mismatchQc md5sum)) {
    $tools{$tool} = _which($tool) || die "Unable to find '$tool' in path";
  }

  my $mismatchQc = q{};
  if(defined $options->{'mmqc'}) {
    $mismatchQc = sprintf q{ | %s -l 0 -t %.2f -p},
                      $tools{'mismatchQc'},
                      $options->{'mmqcfrac'};
  }

  my $out_fmt = 'bam';
  my $idx_type = 'bai';
  my $idx_csi_flag = q{};
  if($options->{'cram'}) {
    $idx_type = 'crai';
    $out_fmt = 'cram';
    $out_fmt .= ',seqs_per_slice='.$options->{'seqslice'};
  }
  elsif(exists $options->{'csi'}) {
    # only valid for bam
    $idx_type = 'csi';
    $idx_csi_flag = '-c';
  }

  if(defined $options->{'nomarkdup'} && $options->{'nomarkdup'} == 1) {
    my $merge    = sprintf q{%s merge -u -@ %d - %s},
                            $tools{samtools}, $helper_threads, $input_str;
    my $compress = sprintf q{%s view -T %s --output-fmt %s -@ %d -},
                            $tools{samtools}, $options->{reference}, $out_fmt, $helper_threads;
    my $idx      = sprintf q{%s index -@ %d %s - %s.%s},
                          $tools{samtools}, $helper_threads, $idx_csi_flag, $marked, $idx_type;
    my $md5      = sprintf q{%s -b > %s.md5},
                           $tools{md5sum}, $marked;
    my $stats    = sprintf q{%s -o %s.bas -@ %d},
                            $tools{bam_stats}, $marked, $helper_threads;
    push @commands, qq{$merge $mismatchQc | pee "$stats" "$compress | pee '$idx' '$md5' 'cat > $marked'"};
  }
  else {
    my $merge;
    my $markdup;
    if(exists $options->{legacy}) {
      my $mmflagmod = _which('mmFlagModifier') || die "Unable to find 'mmFlagModifier' in path";
      my $bammarkdups = _which('bammarkduplicates2') || die "Unable to find 'bammarkduplicates2' in path";
      my $bammerge = _which('bammerge') || die "Unable to find 'bammerge' in path";
      my $bm_tmp = File::Spec->catfile($tmp, 'bmTmp');

      $input_str =~ s/ / I=/g;
      $merge = sprintf '%s SO=%s tmpfile=%s level=0 I=%s', $bammerge, 'coordinate', $bm_tmp, $input_str;

      my $mmQcRemove = sprintf '%s --remove -l 0 -@ %d', $mmflagmod, $helper_threads;
      my $bammarkdup = sprintf '%s tmpfile=%s M=%s.met level=0 markthreads=%d', $bammarkdups, $strmd_tmp, $marked, $helper_threads;
      my $mmQcReplace = sprintf '%s --replace -l 0 -@ %d', $mmflagmod, $helper_threads;

      $markdup = sprintf q{%s | %s | %s}, $mmQcRemove, $bammarkdup, $mmQcReplace;
    }
    else {
      $merge   = sprintf q{%s merge -u -@ %d - %s},
                         $tools{samtools}, $helper_threads, $input_str;
      $markdup = sprintf q{%s markdup --mode %s --output-fmt bam,level=0 -S --include-fails -T %s -@ %d -f %s.met - -},
                         $tools{samtools}, $options->{dupmode}, $strmd_tmp, $helper_threads, $marked;
    }
    my $compress = sprintf q{%s view -T %s --output-fmt %s -@ %d -},
                           $tools{samtools}, $options->{reference}, $out_fmt, $helper_threads;
    my $idx      = sprintf q{%s index -@ %d %s - %s.%s},
                           $tools{samtools}, $helper_threads, $idx_csi_flag, $marked, $idx_type;
    my $md5      = sprintf q{%s -b > %s.md5},
                           $tools{md5sum}, $marked;
    my $stats    = sprintf q{%s -o %s.bas -@ %d},
                           $tools{bam_stats}, $marked, $helper_threads;
    push @commands, qq{$merge $mismatchQc | $markdup | pee "$compress | pee 'cat > $marked' '$idx' '$md5'" "$stats" };
  }

  if($options->{'cram'}) {
    push @commands, sprintf $CRAM_CHKSUM, $marked, $marked;
  }

  PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), \@commands, 0);
  PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), 0);
  return $marked;
}

sub bam_stats {
  # uncoverable subroutine
  my $options = shift;
  my $tmp = $options->{'tmp'};
  # leagacy method, not needed
  my $ext = '.bam';
  $ext = '.cram' if($options->{'cram'});
  my $xam = File::Spec->catdir($options->{'outdir'}, $options->{'sample'}).$ext;
  my $bas = "$xam.bas";
  return $bas if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), 0);
  PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), 0);
  return $bas;
}

sub sample_name {
  my ($bam, $die_no_sample) = @_;
  my $sam = sam_ob($bam);
  my $header = $sam->header->text;
  my $sample;
  while($header =~ m/\tSM:([^\t\n]+)/xmsg) {
    my $new_sample = $1;
    die "BAM file appears to contain data for multiple samples, not supported: \n\n$header\n" if(defined $sample && $sample ne $new_sample);
    $sample = $new_sample;
  }
  unless(defined $sample) {
    if(defined $die_no_sample && $die_no_sample != 0) {
      die "ERROR: Failed to find samplename in RG headers of $bam";
    }
    warn "WARN: Failed to find samplename in RG headers of $bam\n";
  }
  return ($sample, $sam); # also return the SAM object
}

sub read_group_info {
  my ($self, $required_tags) = @_;

  # sort for convention rather than any purpose
  # de-reference for ease
  my @expected_tags;
  @expected_tags = sort @{$required_tags} if(defined $required_tags);

  if(exists $self->{'rgs'}) {
    $self->check_for_tags(\@expected_tags) if(defined $required_tags);
    return $self->{'rgs'};
  }

  my @rgs;
  for my $line (@{$self->sam_header}) {
    next unless($line =~ m/^\@RG/);
    my @elements = split /\t/, $line;
    shift @elements; # drop @RG entry
    my %rg;
    for my $element(@elements) {
      # Don't think it's possible to generate header with blank fields (\t+)
      # but lets be parnoid
      # uncoverable branch true
      next if($element eq q{});

      my ($tag, $value) = $element =~ m/^([^\:]+)\:(.+)$/;
      # tools used to generate BAM files don't allow this
      # uncoverable branch true
      die "ERROR: Malformed RG tag/value: $element\n" unless(defined $tag && defined $value);
      $rg{$tag} = $value;
    }
    push @rgs, \%rg;
  }
  die "ERROR: This BAM has no readgroups: $self->{bam}" if(scalar @rgs == 0);
  $self->{'rgs'} = \@rgs;
  $self->check_for_tags(\@expected_tags) if(defined $required_tags);
  return $self->{'rgs'};
}

sub comments {
  my $self = shift;
  return $self->{'comments'} if(exists $self->{'comments'});
  my @comments;
  for my $line(@{$self->sam_header}) {
    next unless($line =~ m/^\@CO\t(.*)/);
    push @comments, $1;
  }
  $self->{'comments'} = \@comments;
  return $self->{'comments'};
}

sub sam_header {
  my $self = shift;
  return $self->{'header'} if(exists $self->{'header'});
  my $sam = sam_ob($self->{'bam'});
  my @header_lines = split /\n/, $sam->header->text;
  $self->{'header'} = \@header_lines;
  return $self->{'header'};
}

sub header_sq {
  my $self = shift;
  my $header = $self->sam_header;
  my @sq_names;
  for(@{$header}) {
    if($_ =~ m/^[@]SQ.*[\t]SN:([^\t]+)/) {
      push @sq_names, $1;
    }
  }
  return \@sq_names;
}

sub single_rg_value {
  my ($self, $tag) = @_;
  my $rgs = $self->read_group_info([$tag]);
  croak "ERROR: This BAM includes multiple readgroups: $self->{bam}" if(scalar @{$rgs} > 1);
  return $rgs->[0]->{$tag};
}

sub check_for_tags {
  my ($self, $sorted_tags) = @_;
  my @errors;
  for my $rg(@{$self->{'rgs'}}) {
    my @tags_found = keys %{$rg};
    for my $i(0..(scalar @{$sorted_tags})-1) {
      unless(first { $sorted_tags->[$i] eq $_ } @tags_found) {
        if($sorted_tags->[$i] eq 'PM' && exists $self->{'info'}->{'PM'}) {
          $rg->{'PM'} = $self->{'info'}->{'PM'};
          next;
        }
        my @pairs;
        push @pairs, "$_:$rg->{$_}" for(@tags_found);
        push @errors, "ERROR: $sorted_tags->[$i] not found in RG of $self->{bam}\n\t".(join q{,}, @pairs);
      }
    }
  }
  die (join "\n", @errors) if(scalar @errors > 0);
  return 1;
}

sub sam_ob {
  my $bam = shift;
  my $sam;
  if(ref $bam eq 'Bio::DB::HTS') {
    $sam = $bam;
  }
  elsif(-e $bam) {
    $sam = Bio::DB::HTS->new(-bam => $bam);
  }
  else {
    my $caller = (caller(1))[3];
    croak "$caller requires either a BAM file or Bio::DB::HTS object.\n";
  }
  return $sam;
}

sub check_paired {
  my $self = shift;
  my $sam = sam_ob($self->{'bam'});
  my $bam = $sam->hts_file;
  my $header = $bam->header_read;
  my $read = $bam->read1($header);
  die "ERROR: Input BAM|CRAMs should be for paired end sequencing: $self->{bam}\n" unless(1 & $read->flag);
  return 1;
}

sub mismatchQc_checks {
  my $raw_files = shift;
  for my $to_chk(@{$raw_files}) {
    next if($to_chk !~ m/\.[bc]r?am$/i);
    my ($mismatchQc, $bammaskflag) = (0, 0);
    my $sam = sam_ob($to_chk);
    my @header_lines = split /\n/, $sam->header->text;
    while(my $line = shift @header_lines) {
      next if($line !~ m/^\@PG/);
      if($line =~ m/\tPN:PCAP-core-mismatchQC/) {
        $mismatchQc = 1;
        $bammaskflag = 0; # reset each time we see mismatchQc
      }
      $bammaskflag = 1 if($mismatchQc == 1 && $line =~ m/\tPN:bammaskflags/ && $line =~ m/maskflags=512/);
      $bammaskflag = 1 if($mismatchQc == 1 && $line =~ m/\tPN:PCAP-core-mmFlagModifier/ && ($line =~ m/CL:[^\t]+ -m/ || $line =~ m/CL:[^\t]+ --remove/));
    }
    if($mismatchQc == 1 && $bammaskflag == 0) {
      die <<ERRORDOC;
ERROR:
      This input file appears to have been processed with mismatchQc and has not been cleaned with
      bammaskflags.  Please see the long description for '-mmqc' via 'bwa_mem.pl -m' for more details.
ERRORDOC
    }
  }
}

1;

__END__

=head1 NAME

PCAP::Bam - Methods that process BAM files

=head2 Object Methods

=over 4

=item new

  my $bam = PCAP::Bam->new($bam_file);

Generate a BAM object to allow access to object based functions.  Primarily added to allow efficient
access to header information without re-parsing once populated.

=item read_group_info

  my $rg_data = $bam->read_group_info($required_tags);

Returns an arrayref (one entry per readgroup) of hashes where the keys are the RG tags found in the @RG header line.
Providing an arrayref of required_tags causes an error to be raised if any are not found:

  my $rg_data = $bam->read_group_info([qw(CN LB SN)]);

Resulting data structure:

  [ { CN => 'SI',
      LB => 'LIBRARY_ID',
      SM => 'Sample_name},
    { CN => ...
    },
    ...];

=item single_rg_value

  my $sample_name = $bam->single_rg_value('SM');

Gets the value of a single RG tag.  Errors if multiple readgroups detected.

=item check_for_tags

  $bam->check_for_tags([list of required tags]);

Check that all readgroups in this BAM have the specified tags.
Errors if any are not detected.

=item check_paired

  $bam->check_paired;

Will error if BAM file doesn't contain paired reads.

=item comments

  my @comments = @{$bam->comments};

Returns an array ref of the value of each comment line.
'@CO\t' is pre-stripped.

=item sam_header

  my @header_lines = @{$bam->sam_header};

Returns array ref of all header lines.  One entry perl line.

=back

=head2 Non Object Methods

=over 4

=item bam_to_grouped_bam

  PCAP::Bam::bam_to_grouped_bam($index, $options);

Convert a BAM for a single readgroup to a readname grouped BAM.

  index   - Which element of the 'bams' array reference found in options should be processed
              NOTE: index is origin 1

  options - Hashref, requires the following entries:

          -tmp  : working/output directory depending on application
          -bams : array reference to a B<sorted> list of BAM files (to allow resume function)

On successful completion of a run a file is created in tmp/progress/bamcollate.$index.  If the
program is re-run without clearing of this progress folder the execution of the command is skipped.

=item merge_and_mark_dup

  PCAP::Bam::merge_and_mark_dup($options);

Takes a list of sorted BAM files, marks duplicates and produces single output BAM in one pass.

  options - Hashref, requires the following entries:

          -tmp      : working/output directory depending on application
          -bams     : array reference to a B<sorted> list of BAM files (for consistent results)
          -outdir   : output files written to this folder
          -sample   : prefix of output file
          -threads  : Total threads available to process

  returns - path_to_marked_bam

Resulting data is of the form:

  $outdir/$sample.bam
  $outdir/$sample.bam.bai
  $outdir/$sample.bam.md5
  $outdir/$sample.met

=item sample_name

Takes BAM or Bio::DB::HTS object as input and returns the sample name found in the header.

The SAM object is also returned should it be useful for other calls

=item rg_line_for_output

Takes BAM or Bio::DB::HTS object as input and returns the string representation for the RG line.
Intended for use when adding RG to BWA MEM output and is only useful in single RG BAMs

Optional second boolean arg causes ID to be replaced with a UUID.

The SAM object is also returned should it be useful for other calls

=item sam_ob

  my $sam_ob = sam_ob('file.bam');

Generate a Bio::DB::HTS object from the provided BAM|CRAM file.

=item mismatchQc_checks

  mismatchQc_checks($array_ref_of_files);

Checks BAM/CRAM file headers for presence of mismatchQc PG line.  If found errors if subsequent
bammaskflags to clean flag 512 is not found.

=back
