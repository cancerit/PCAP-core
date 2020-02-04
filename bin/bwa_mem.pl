#!/usr/bin/perl

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

use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Cwd qw(cwd abs_path);

use File::Path qw(remove_tree make_path);
use Getopt::Long;
use File::Spec;
use Pod::Usage qw(pod2usage);
use List::Util qw(first);
use Const::Fast qw(const);
use File::Copy qw(copy move);

use PCAP::Cli;
use PCAP::Bam;
use PCAP::Bwa;
use PCAP::Bwa::Meta;
use PCAP::Threaded;
use version;

const my @VALID_PROCESS => qw(setup split bwamem mark stats);
const my %INDEX_FACTOR => ( 'setup' => 1,
                            'split' => -1,
                            'bwamem' => -1,
                            'mark'   => 1,
                            'stats'  => 1,);

{
  my $options = setup();

 	my $threads = PCAP::Threaded->new($options->{'threads'});
	&PCAP::Threaded::disable_out_err if(!exists $options->{'index'} && $options->{'threads'} == 1);

  # register processes
	$threads->add_function('split', \&PCAP::Bwa::split_in);
	$threads->add_function('bwamem', \&PCAP::Bwa::bwa_mem, exists $options->{'index'} ? 1 : $options->{'map_threads'});

  PCAP::Bwa::mem_setup($options) if(!exists $options->{'process'} || $options->{'process'} eq 'setup');

	$threads->run($options->{'max_split'}, 'split', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'split');

  if(!exists $options->{'process'} || $options->{'process'} eq 'bwamem') {
    $options->{'max_index'} = PCAP::Bwa::mem_mapmax($options);
    $threads->run($options->{'max_index'}, 'bwamem', $options);
  }

  if(!exists $options->{'process'} || $options->{'process'} eq 'mark') {
    # delete the split area if we've made it here to save space
    PCAP::Bwa::clear_split_files($options);
    PCAP::Bam::merge_and_mark_dup($options, File::Spec->catdir($options->{'tmp'}, 'sorted'));
  }
  if(!exists $options->{'process'} || $options->{'process'} eq 'stats') {
    PCAP::Bam::bam_stats($options);
    &cleanup($options);
  }
}

sub cleanup {
  my $options = shift;
  my $tmpdir = $options->{'tmp'};
  move(File::Spec->catdir($tmpdir, 'logs'), File::Spec->catdir($options->{'outdir'}, 'logs_bwamem_'.$options->{'sample'})) || die $!;
  remove_tree $tmpdir if(-e $tmpdir);
	return 0;
}

sub setup {
  my %opts = ('map_threads' => &PCAP::Bwa::bwa_mem_max_cores,
              'mmqcfrac' => 0.05,
              'threads' => 1,
              'fragment' => 10,
              'csi' => undef,
             );

  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'v|version' => \$opts{'v'},
              'j|jobs' => \$opts{'jobs'},
              't|threads=i' => \$opts{'threads'},
              'mt|map_threads=i' => \$opts{'map_threads'},
              'r|reference=s' => \$opts{'reference'},
              'o|outdir=s' => \$opts{'outdir'},
              's|sample=s' => \$opts{'sample'},
              'n|nomarkdup' => \$opts{'nomarkdup'},
              'f|fragment:i' => \$opts{'fragment'},
              'p|process=s' => \$opts{'process'},
              'i|index=i' => \$opts{'index'},
              'b|bwa=s' => \$opts{'bwa'},
              'csi' => \$opts{'csi'},
              'c|cram' => \$opts{'cram'},
              'sc|scramble=s' => \$opts{'scramble'},
              'l|bwa_pl=s' => \$opts{'bwa_pl'},
              'g|groupinfo=s' => \$opts{'groupinfo'},
              'q|mmqc' => \$opts{'mmqc'},
              'qf|mmqcfrac:f' => \$opts{'mmqcfrac'},
  ) or pod2usage(2);

  pod2usage(-verbose => 1, -exitval => 0) if(defined $opts{'h'});
  pod2usage(-verbose => 2, -exitval => 0) if(defined $opts{'m'});

  if(defined $opts{'v'}) {
    print PCAP->VERSION,"\n";
    exit 0;
  }

  my $version = PCAP::Bwa::bwamem2_version();
  die "bwa mem can only be used with bwa version 0.7+, the version found in path is: $version\n" unless(version->parse($version) >= version->parse('0.7.0'));

  # then check for no args:
  my $defined;
  for(keys %opts) { $defined++ if(defined $opts{$_}); }
  pod2usage(-msg  => "\nERROR: Options must be defined.\n", -verbose => 1,  -output => \*STDERR) unless($defined);

  PCAP::Cli::file_for_reading('reference', $opts{'reference'});
  $opts{'outdir'} = abs_path($opts{'outdir'});
  PCAP::Cli::out_dir_check('outdir', $opts{'outdir'});

  $opts{'dict'} = $opts{'reference'}.'.dict';
  unless(-r $opts{'dict'}) {
    die "ERROR: Please generate $opts{dict}, e.g.\n\t\$ samtools dict -a \$ASSEMBLY -s \$SPECIES $opts{reference} > $opts{dict}\n";
  }

  delete $opts{'process'} unless(defined $opts{'process'});
  delete $opts{'index'} unless(defined $opts{'index'});
  delete $opts{'bwa'} unless(defined $opts{'bwa'});
  delete $opts{'scramble'} unless(defined $opts{'scramble'});
  delete $opts{'bwa_pl'} unless(defined $opts{'bwa_pl'});
  delete $opts{'mmqc'} unless(defined $opts{'mmqc'});
  delete $opts{'csi'} unless(defined $opts{'csi'});

  PCAP::Cli::opt_requires_opts('scramble', \%opts, ['cram']);

  my $tmpdir = File::Spec->catdir($opts{'outdir'}, 'tmpMap_'.$opts{'sample'});
  make_path($tmpdir) unless(-d $tmpdir);
  my $progress = File::Spec->catdir($tmpdir, 'progress');
  make_path($progress) unless(-d $progress);
  my $logs = File::Spec->catdir($tmpdir, 'logs');
  make_path($logs) unless(-d $logs);
  my $links = File::Spec->catdir($tmpdir, 'links');
  make_path($links) unless(-d $links);

  $opts{'tmp'} = $tmpdir;

  my $cwd = cwd();
  for(@ARGV) {
    $_ = "$cwd/$_" unless($_ =~ m|^/|);
    push @{$opts{'raw_files'}}, $_;
  }
  pod2usage(-msg  => "\nERROR: No BAM/CRAM or FASTQ files have been defined.\n", -verbose => 1,  -output => \*STDERR) if(scalar @{$opts{'raw_files'}} == 0);

  my $max_split = PCAP::Bwa::mem_prepare(\%opts);

  if(exists $opts{'process'}) {
    PCAP::Cli::valid_process('process', $opts{'process'}, \@VALID_PROCESS);
    my $max_index = $INDEX_FACTOR{$opts{'process'}};
    if($max_index == -1) {
      $max_index = $max_split                     if($opts{'process'} eq 'split');
      $max_index = PCAP::Bwa::mem_mapmax(\%opts)  if($opts{'process'} eq 'bwamem');
    }
    $opts{'max_index'} = $max_index;
    if(exists $opts{'index'}) {
      PCAP::Cli::opt_requires_opts('index', \%opts, ['process']);
      PCAP::Cli::valid_index_by_factor('index', $opts{'index'}, \@ARGV, $max_index);
    }
    elsif(defined $opts{'jobs'}) {
      # tell me the max processes required for this step
      print "Requires: $max_index\n";
      exit 0;
    }
  }
  elsif(exists $opts{'index'}) {
    die "ERROR: -index cannot be defined without -process\n";
  }

  return \%opts;
}

__END__

=head1 NAME

bwa_mem.pl - Align a set of lanes to specified reference with single command.

=head1 SYNOPSIS

bwa_mem.pl [options] [file(s)...]

  Required parameters:
    -outdir      -o   Folder to output result to.
    -reference   -r   Path to reference genome file *.fa[.gz]
    -sample      -s   Sample name to be applied to output file.
    -threads     -t   Number of threads to use. [1]

  Optional parameters:
    -fragment    -f   Split input into fragments of X million repairs [10]
    -nomarkdup   -n   Don't mark duplicates [flag]
    -csi              Use CSI index instead of BAI for BAM files [flag].
    -cram        -c   Output cram, see '-sc' [flag]
    -scramble    -sc  Single quoted string of parameters to pass to Scramble when '-c' used
                      - '-I,-O' are used internally and should not be provided
    -bwa         -b     Single quoted string of additional parameters to pass to BWA
                         - '-t,-p,-R' are used internally and should not be provided.
                         - '-v' is set to 1 unless '-bwa' is set.
    -map_threads -mt  Number of cores applied to each parallel BWA job when '-t' exceeds this value
                      and '-i' is not in use [6]
    -groupinfo   -g   Readgroup information metadata file, values are not validated (yaml) [file]
    -mmqc        -q   Mark reads as QCFAIL (0x200, 512) if mismatch rate exceeded [flag]
                       - Please see 'bwa_mem.pl -m'
    -mmqcfrac    -qf  Mismatch fraction for -mmqc [0.05]

  Targeted processing:
    -process     -p   Only process this step then exit, optionally set -index
                        bwamem - only applicable if input is bam
                          mark - Run duplicate marking (-index N/A)
                         stats - Generates the *.bas file for the final BAM.

    -index       -i   Optionally restrict '-p' to single job
                        bwamem - 1..<lane_count>

  Performance variables
    -bwa_pl      -l   BWA runs ~8% quicker when using the tcmalloc library from
                      https://github.com/gperftools/ (assuming number of cores not exceeded)
                      If available specify the path to 'gperftools/lib/libtcmalloc_minimal.so'.

  Other:
    -jobs        -j   For a parallel step report the number of jobs required
    -help        -h   Brief help message.
    -man         -m   Full documentation.

File list can be full file names or wildcard, e.g.

=over 4

=item mutiple BAM inputs

 bwa_mem.pl -t 16 -r some/genome.fa.gz -o myout -s sample input/*.bam

=item multiple paired fastq inputs

 bwa_mem.pl -t 16 -r some/genome.fa.gz -o myout -s sample input/*_[12].fq[.gz]

=item multiple interleaved paired fastq inputs

 bwa_mem.pl -t 16 -r some/genome.fa.gz -o myout -s sample input/*.fq[.gz]

=item mixture of BAM and CRAM

 bwa_mem.pl -t 16 -r some/genome.fa.gz -o myout -s sample input/*.bam input/*.cram

=back

=head1 DESCRIPTION

B<bwa_mem.pl> will attempt to run all mapping steps for BWA-mem, as well as subsequent merging
and duplicate marking automatically.

=head1 OPTION DETAILS

=over 4

=item B<-outdir>

Directory to write output to.  During processing a temp folder will be generated in this area,
should the process fail B<only delete this if> you are unable to resume the process.

Final output files include: <SAMPLE>.bam, <SAMPLE>.bam.bai, <SAMPLE>.md5, <SAMPLE>.met

=item B<-reference>

Path to genome.fa[.gz] file and associated indexes for BWA.

=item B<-sample>

Name to be applied to output files.  Special characters will not be magically fixed.

=item B<-threads>

Number of threads to be used in processing.

If perl is not compiled with threading some steps will not run in parallel, however much of the
script calls other tools that will still utilise this appropriately.

This also impacts the number of threads used by BWA mapping steps.

=back

=head2 OPTIONAL parameters

=over 4

=item B<-fragment>

Split input into fragements of X million repairs.  To prevent variability in data processing either
set this to a very large number or ensure that it is not changed.  Values > 5000 indicate that data
should not be split.

=item B<-nomarkdup>

Disables duplicate marking, switching bammarkduplicates2 for bammerge.

=item B<-csi>

User CSI style index for final BAM file instead of default BAI.

=item B<-cram>

Final output file will be a CRAM file instead of BAM.  To tune the the compression methods see then
B<-scramble> option.

=item B<-scramble>

Single quoted string of parameters to pass to Scramble when '-c' used.  Please see the Scramble
documentation for details.

Please note: '-I,-O' are used internally and should not be provided.

=item B<-bwa>

Single quoted string of additional parameters to pass to BWA.  Please see the 'bwa mem'
documentation for details.

Please note: '-t,-p,-R' are used internally and should not be provided.

If you want the default verbosity of BWA set '-v 3'.

=item B<-map_threads>

Number of cores applied to each parallel BWA job when '-t' exceeds this value and '-i' is not in use.

e.g. -t 8, -mt 4 results in 2x 4*thread mapping jobs when possible.

Recommend leaving this as the default and using increments of 6 for '-threads'.

=item B<-groupinfo>

Readgroup information metadata file, please see the PCAP wiki for format:

https://github.com/cancerit/PCAP-core/wiki/File-Formats-groupinfo.yaml

=item B<-mmqc>

Mark reads as QCFAIL (0x200, 512) using the mismatchQc program, also adds aux tag 'mm:A:Y'.

WARNING:
bwa_mem.pl will exclude all QCFAIL reads from mapping. If a BAM/CRAM file has been created using
this option please ensure that you pre-process the file to remove the flag 512 if you intend to
reprocess based on that output.

The script mmFlagModifier -m (--remove) can process a bam file to remove any occurences of
flag 512 where the read also has the tag mm:A:Y .

e.g.

mmFlagModifier -m -i mmqc.bam > cleaned.bam

=item B<-mmqcfrac>

Mismatch fraction to pass through to mismatchQc

=back

=head2 TARGETED PROCESSING

=over 4

=item B<-process>

If you want to run the code in a more efficient manner then this allows each procesing type to be
executed in isolation.  You can restrict to a single process within the block by specifying
B<-index> as well.

=back

=head2 INPUT FILE TYPES

There are several types of file that the script is able to process.

=over 4

=item f[ast]q

A standard uncompressed fastq file.  Requires a pair of inputs with standard suffix of '_1' and '_2'
immediately prior to '.f[ast]q' or an interleaved f[ast]q file where read 1 and 2 are adjacent
in the file.


=item f[ast]q.gz

As *.f[ast]q but compressed with gzip.

=item bam

Single lane BAM files, RG line is transfered to aligned files.  Also accepts multi lane BAM.

=item cram

Single lane BAM files, RG line is transfered to aligned files.  Also accepts multi lane CRAM.

=back

=cut
