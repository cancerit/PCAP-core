package PCAP::Bwa;

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2020 ICGC PanCancer Project
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
use File::Path qw(make_path remove_tree);
use File::Spec;
use Capture::Tiny qw(capture);
use File::Copy qw(copy);

use PCAP::Bwa::Meta;
use PCAP::Bam;

const my $BWA_ALN => q{ aln%s -t %s -f %s_%s.sai %s %s.%s};
const my $ALN_TO_SORTED => q{ sampe -P -a 1000 -r '%s' %s %s_1.sai %s_2.sai %s.%s %s.%s | %s fixmate=1 inputformat=sam level=1 tmpfile=%s_tmp O=%s_sorted.bam};

const my $TAG_STRIP => q{-x AM -x MD -x NM -x RT -x SM -x X0 -x X1 -x XA -x XG -x XM -x XN -x XO -x XT -x mm};

const my $FALSE_RG => q{@RG\tID:%s\tSM:%s\tLB:default\tPL:ILLUMINA};

const my $READPAIR_SPLITSIZE => 10,
const my $PAIRED_FQ_LINE_MULT => 4;
const my $INTERLEAVED_FQ_LINE_MULT => 8;
const my $BAM_MULT => 2;
const my $MILLION => 1_000_000;

const my $BWA_MEM_MAX_CORES => 6;

sub bwa_mem_max_cores {
  return $BWA_MEM_MAX_CORES;
}

sub bwamem2_version {
  my $bwa = _which('bwa-mem2');
  my $version;
  {
    my ($stdout, $stderr, $exit) = capture{ system("$bwa version"); };
    chomp $stdout;
    $version = $stdout;
  }
  return $version;
}

sub bwa_version {
  my $bwa = _which('bwa');
  my $version;
  {
    no autodie qw(system);
    my ($stdout, $stderr, $exit) = capture{ system($bwa); };
    ($version) = $stderr =~ /Version: ([[:digit:]\.]+)/m;
  }
  return $version;
}

sub mem_setup {
  my ($options, $skip_mmqc_check) = @_;
  if($options->{'reference'} =~ m/\.gz$/) {
    my $tmp_ref = $options->{'reference'};
    $tmp_ref =~ s/\.gz$//;
    if(-e $tmp_ref) {
      $options->{'decomp_ref'} = $tmp_ref;
    }
    else {
      $options->{'decomp_ref'} = "$options->{tmp}/decomp.fa";
      system([0,2], "(gunzip -c $options->{reference} > $options->{decomp_ref}) >& /dev/null") unless(-e $options->{'decomp_ref'});
      copy("$options->{reference}.fai", "$options->{tmp}/decomp.fa.fai") unless(-e "$options->{decomp_ref}.fai");
    }
  }
  return 1;
}

sub mem_prepare {
  my $options = shift;
  $options->{'meta_set'} = PCAP::Bwa::Meta::files_to_meta($options->{'tmp'}, $options->{'raw_files'}, $options->{'sample'}, $options->{'groupinfo'});
  $options->{'max_split'} = scalar @{$options->{'meta_set'}};
  return $options->{'max_split'};
}

sub clear_split_files {
  my $options = shift;
  my $split_dir = File::Spec->catdir($options->{'tmp'}, 'split');
  my @in_list = (1..$options->{'max_split'}); # get the number of folders that will exist inside of split
  for my $subd(@in_list) {
    my $folder = File::Spec->catdir($split_dir, $subd);
    opendir(my $dh, $folder);
    while(my $file = readdir $dh) {
      next if($file =~ m/^\./);
      my $item = File::Spec->catfile($folder, $file);
      next if(-l $item);
      open my $T, '>', $item;
      close $T;
    }
  }
  return;
}

sub mem_mapmax {
  my $options = shift;
  my $split_dir = File::Spec->catdir($options->{'tmp'}, 'split');
  die "Please run setup and split steps prior to bwamem\n" unless(-d $split_dir);
  my @files;
  my @in_list = (1..$options->{'max_split'}); # get the number of folders that will exist inside of split
  for my $subd(@in_list) {
    my $folder = File::Spec->catdir($split_dir, $subd);
    opendir(my $dh, $folder);
    while(my $file = readdir $dh) {
      next if($file =~ m/^\./);
      next if($file =~ m/^pairedfq2\.[[:digit:]]+/); # captured by 1.*
      next if($file =~ m/s[.]fq[.]gz_[[:digit:]]+[.]gz$/);
      next if($file eq 'unknown.bam');
      if($file =~ m/o[12][.]fq[.]gz_[[:digit:]]+[.]gz$/) {
        warn "Orphan reads found, your input BAM appears to have had duplicates 'removed' rather than 'marked': $folder/$file\n\tWARNING: This will give a sub-optimal result\n";
        next;
      }
      push @files, File::Spec->catfile($folder, $file);
    }
    closedir($dh);
  }
  @files = sort @files;
  $options->{'to_map'} = \@files;
  if(scalar @files == 0) {
    die "\n\nERROR: It appears that all input data is single ended, aborting.\n";
  }
  return (scalar @files);
}

sub split_in {
  my ($index, $options) = @_;
  return 1 if(exists $options->{'index'} && $index != $options->{'index'});

  my $tmp = $options->{'tmp'};
  return 1 if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), $index);

  my $input_meta = $options->{'meta_set'};
  my $iter = 1;
  for my $input(@{$input_meta}) {
    next if($iter++ != $index); # skip to the relevant element in the list

    # one split folder for each 'lane' of input
    my $split_folder = File::Spec->catdir($options->{'tmp'}, 'split', $index);
    my $sort_folder = File::Spec->catdir($options->{'tmp'}, 'sorted');

    make_path($split_folder) unless(-d $split_folder);
    make_path($sort_folder) unless(-d $sort_folder);

    my $fragment_size = $options->{'fragment'};
    $fragment_size ||= $READPAIR_SPLITSIZE;

    my @commands;
    # if fastq input
    if($input->fastq) {
      # paired fq input
      if($input->paired_fq) {
        my $fq1 = $input->in.'_1.'.$input->fastq;
        my $fq2 = $input->in.'_2.'.$input->fastq;
        if($input->fastq =~ m/[.]gz$/ || $fragment_size > 5000) {
          symlink $fq1, File::Spec->catfile($split_folder, 'pairedfq1.0.'.$input->fastq);
          symlink $fq2, File::Spec->catfile($split_folder, 'pairedfq2.0.'.$input->fastq);
        }
        else {
          push @commands,  sprintf 'split -a 3 -d -l %s %s %s.'
                                  , $fragment_size * $MILLION * $PAIRED_FQ_LINE_MULT
                                  , $fq1
                                  , File::Spec->catfile($split_folder, 'pairedfq1');
          push @commands,  sprintf 'split -a 3 -d -l %s %s %s.'
                                  , $fragment_size * $MILLION * $PAIRED_FQ_LINE_MULT
                                  , $fq2
                                  , File::Spec->catfile($split_folder, 'pairedfq2');
        }
      }
      # interleaved FQ
      else {
        my $fq_i = $input->in.'.'.$input->fastq;
        if($input->fastq =~ m/[.]gz$/ || $fragment_size > 5000) {
          symlink $fq_i, File::Spec->catfile($split_folder, 'i.'.$input->fastq);
        }
        else {
          push @commands,  sprintf 'split -a 3 -d -l %s %s %s.'
                                  , $fragment_size * $MILLION * $INTERLEAVED_FQ_LINE_MULT
                                  , $fq_i
                                  , File::Spec->catfile($split_folder, 'i');
        }
      }
    }
    # if bam|cram input
    else {
      my $helpers = $options->{threads_per_split};
      my $collate_folder = File::Spec->catdir($options->{'tmp'}, 'collate', $index);
      make_path($collate_folder) unless(-d $collate_folder);
      my $samtools = _which('samtools') || die "Unable to find 'samtools' in path";
      my $mmQcStrip = sprintf '%s --remove -l 0 -@ %d -i %s', _which('mmFlagModifier'), $helpers, $input->in;
      my $view = sprintf '%s view %s -bu -T %s -F 2816 -@ %d -', $samtools, $TAG_STRIP, $options->{'reference'}, $helpers; # leave
      my $collate = sprintf '%s collate -Ou -@ %d - %s/collate', $samtools, $helpers, $collate_folder;
      my $split = sprintf '%s split --output-fmt bam,level=1 -@ %d -u %s/unknown.bam -f %s/%%!_i.bam -', $samtools, $helpers, $split_folder, $split_folder;
      my $cmd = sprintf '%s | %s | %s | %s', $mmQcStrip, $view, $collate, $split;
      # treat as interleaved fastq
      push @commands, 'set -o pipefail';
      push @commands, $cmd;
      push @commands, "rm -rf $collate_folder"; # cleanup temp folder
    }

    PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), \@commands, $index);
    PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), $index);
  }
  return 1;
}

sub bwa_mem {
  my ($index, $options) = @_;
  return 1 if(exists $options->{'index'} && $index != $options->{'index'});

  my $tmp = $options->{'tmp'};
  return 1 if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), $index);


  my $input_meta = $options->{'meta_set'};
  my $to_map = $options->{'to_map'};
  my $iter = 1;
  for my $split(@{$to_map}) {
    next if($iter++ != $index); # skip to the relevant element in the list

    # this needs to come from the meta_set now,
    # use the folder in the split path to determine which BAM in the input list the RG line should come from
    # need to finish defining how the split_in step should make the file list be a stubbed dataset rather than full paths
    # primarily to ensure that non-interleaved aren't counted as 2 jobs

    # determine meta by path of input
    my ($split_element) = $split =~ m|/split/([[:digit:]]+)/|;
    my $input = $input_meta->[$split_element - 1]; # as array origin 0

    my $rg_line;
    # uncoverable branch true
    # uncoverable branch false
    if($input->fastq) {
      $rg_line = q{'}.$input->rg_header(q{\t}).q{'};
    }
    else {
      my ($rg) = $split =~ m{/split/[[:digit:]]+/(.+)_i\.(?:fq_[[:digit:]]+\.)?(?:gz|bam)$};
      ($rg_line, undef) = PCAP::Bam::rg_line_for_output($input->in, $options->{'sample'}, undef, $rg);
      if($rg_line) {
        $rg_line =~ s/('+)/'"$1"'/g;
      }
      else {
        $rg_line = sprintf $FALSE_RG, $split_element, $options->{'sample'};
      }
      $rg_line = q{'}.$rg_line.q{'};
    }

    my $threads = $options->{'map_threads'};
    $threads = $options->{'threads'} if($options->{'threads'} < $options->{'map_threads'});

    my $bwa = q{};
    if(exists $options->{'bwamem2'}) {
      $bwa .= _which('bwa-mem2') || die "Unable to find 'bwa-mem2' in path";
    }
    else {
      if(exists $options->{'bwa_pl'}) {
        $bwa .= 'LD_PRELOAD='.$options->{'bwa_pl'}.' ';
      } elsif(exists $ENV{GPERF_FOR_BWA}) {
        $bwa .= 'LD_PRELOAD='.$ENV{GPERF_FOR_BWA}.' ';
      }
      $bwa .= _which('bwa') || die "Unable to find 'bwa' in path";
    }

    $ENV{SHELL} = '/bin/bash'; # ensure bash to allow pipefail

    my %tools;
    for my $tool(qw(samtools reheadSQ)) {
      $tools{$tool} = _which($tool) || die "Unable to find '$tool' in path";
    }

    my $interleaved_fq = q{};
    # uncoverable branch true
    # uncoverable branch false
    $interleaved_fq = q{ -p}, unless($input->paired_fq);

    my $add_options = q{-v 1}; # minimise output
    $add_options = $options->{'bwa'} if(exists $options->{'bwa'});
    $bwa .= sprintf q{ mem %s %s -R %s -t %s %s}, $add_options, $interleaved_fq, $rg_line, $threads, $options->{'reference'};

    # uncoverable branch true
    # uncoverable branch false
    $split =~ s/'/\\'/g;
    if($input->fastq) {
      $bwa .= ' '.$split;
      if($input->paired_fq) {
        my $split2 = $split;
        $split2 =~ s/pairedfq1(\.[[:digit:]]+)/pairedfq2$1/;
        $bwa .= ' '.$split2;
      }
    }
    else {
      # bam/cram
      my $tofastq = sprintf '%s fastq -@ %d -N %s', $tools{samtools}, $threads, $split;
      $bwa = sprintf '%s | %s /dev/stdin', $tofastq, $bwa;
    }

    my $sorted_bam_stub = $split;
    $sorted_bam_stub =~ s|/split/([[:digit:]]+)/(.+)$|/sorted/$1_$2|;
    $sorted_bam_stub =~ s/\\'/-/g;

    my $ref = exists $options->{'decomp_ref'} ? $options->{'decomp_ref'} : $options->{'reference'};

    my $rehead_sq = sprintf '%s -d %s',
                            $tools{reheadSQ}, $options->{'dict'};
    my $fixmate   = sprintf q{%s fixmate -m --output-fmt bam,level=0 -@ %d - -},
                            $tools{samtools}, $threads;
    my $sort      = sprintf q{%s sort -m 2G --output-fmt bam,level=0 -T %s_tmp -@ %d -},
                            $tools{samtools}, File::Spec->catfile($tmp, "bamsort.$index"), $threads;
    my $calmd     = sprintf q{%s calmd --output-fmt bam,level=1 -Q -@ %d - %s > %s_sorted.bam},
                            $tools{samtools}, $threads, $ref, $sorted_bam_stub;
    my $command .= "set -o pipefail; $bwa | $rehead_sq | $fixmate | $sort | $calmd";

    PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), $command, $index);
    PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), $index);
  }
  return 1;
}

# will use thread count to speed up align but each set of fastq are processed in series
sub bwa_aln {
  # uncoverable subroutine
  my $options = shift;
  my $tmp = $options->{'tmp'};
  my $input_meta = $options->{'meta_set'};
  my $input_counter = 0;
  my $index_counter = 0;
  for my $input(@{$input_meta}) {
    $input_counter++;
    for my $end(1..2) {
      $index_counter++;
      # uncoverable branch true
      # uncoverable branch false
      next if(defined $options->{'index'} && $index_counter != $options->{'index'});
      # uncoverable branch true
      # uncoverable branch false
      next if(PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), $input_counter, $end));
      my $this_stub = $input->tstub;

      my $command = _which('bwa') || die "Unable to find 'bwa' in path";

      # uncoverable branch true
      # uncoverable branch false
      if($input->fastq) {
        $command .= sprintf $BWA_ALN, q{}, $options->{'threads'}, $this_stub, $end, $options->{'reference'}, $input->in.'_'.$end, $input->fastq;
      }
      else {
        $command .= sprintf $BWA_ALN, ' -b -'.$end, $options->{'threads'}, $this_stub, $end, $options->{'reference'}, $this_stub, 'bam';
      }
      PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), $command, $input_counter, $end);
      PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), $input_counter, $end);
    }
  }
  return 1;
}

sub sampe {
  # uncoverable subroutine
  my ($index, $options) = @_;
  my $tmp = $options->{'tmp'};
  my $input_meta = $options->{'meta_set'};
  my $ref = $options->{'reference'};

  # uncoverable branch true
  # uncoverable branch false
  return 1 if(exists $options->{'index'} && $index != $options->{'index'});
  # uncoverable branch true
  # uncoverable branch false
  return if PCAP::Threaded::success_exists(File::Spec->catdir($tmp, 'progress'), $index);

  my $pathstub = $input_meta->[$index-1]->tstub;
  my $fastq = $input_meta->[$index-1]->fastq;


  my $command = _which('bwa') || die "Unable to find 'bwa' in path";;
  my $bamsort = _which('bamsort') || die "Unable to find 'bwa' in bamsort";;

  # uncoverable branch true
  # uncoverable branch false
  if(defined $fastq) {
    $command .= sprintf $ALN_TO_SORTED, $input_meta->[$index-1]->rg_header(q{\t}),
                                      $ref,
                                      $pathstub,
                                      $pathstub,
                                      $input_meta->[$index-1]->in.'_1', $fastq,
                                      $input_meta->[$index-1]->in.'_2', $fastq,
                                      $bamsort,
                                      $pathstub,
                                      $pathstub;
  }
  else {
    $command .= sprintf $ALN_TO_SORTED, $input_meta->[$index-1]->rg_header(q{\t}),
                                      $ref,
                                      $pathstub,
                                      $pathstub,
                                      $pathstub, 'bam',
                                      $pathstub, 'bam',
                                      $bamsort,
                                      $pathstub,
                                      $pathstub;
  };
  PCAP::Threaded::external_process_handler(File::Spec->catdir($tmp, 'logs'), $command, $index);
  return PCAP::Threaded::touch_success(File::Spec->catdir($tmp, 'progress'), 'sampe', $index);
}

1;

__END__

=head1 NAME

PCAP::Bwa - Generate BWA mappings

=head2 Methods

=over 4

=item bwa_version

  my $version = PCAP::Bwa::bwa_version();

Not a prefect representation of version as any text has to be removed to allow comparison.

=item bwa_aln

  PCAP::Bwa::bwa_aln($options);

Runs a 'bwa aln' process for a single end of sequencing data.

  options - Hashref, requires the following entries:
    -tmp        : working/output directory depending on application
    -meta_set   : array reference of objects as generated by PCAP::Bwa::Meta::files_to_meta
    -reference  : Path to reference fa[.gz]
    -threads    : Total threads available to process

See L<PCAP::Bwa::Meta::files_to_meta|PCAP::Bwa::Meta/files_to_meta>.

=item bwa_mem

  PCAP::Bwa::bwa_mem($options);

  options - Hashref, requires the following entries:
    -tmp        : working/output directory depending on application
    -meta_set   : array reference of objects as generated by PCAP::Bwa::Meta::files_to_meta
    -reference  : Path to reference fa[.gz]
    -threads    : Total threads available to process

=item sampe

  Pan::Cancer::Bwa::sampe($index, $options)

Runs a 'bwa sampe' process on the specified element of the meta_set found in $options.

  options - Hashref, requires the following entries:
    -tmp        : working/output directory depending on application
    -meta_set   : array reference of objects as generated by PCAP::Bwa::Meta::files_to_meta
    -reference  : Path to reference fa[.gz]

=back
