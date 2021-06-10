#!/usr/bin/perl

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

use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use FindBin qw($Bin);
use lib "$Bin/../lib";

use File::Path qw(remove_tree make_path);
use Getopt::Long;
use File::Spec;
use Pod::Usage qw(pod2usage);
use List::Util qw(first);
use Const::Fast qw(const);
use File::Copy qw(copy move);

use PCAP::Cli;
use PCAP::Bam;
use PCAP::BigWig;
use PCAP::Threaded;
use version;

const my @VALID_PROCESS => qw(bamToBw generateBw);
const my %INDEX_FACTOR => ( 'bamToBw' => -1,
                            'generateBw' => 1,
                            );

{
  my $options = setup();

  $options->{'ctg_lengths'} = PCAP::ref_lengths($options->{'reference'}.'.fai');

 	my $threads = PCAP::Threaded->new($options->{'threads'});
	&PCAP::Threaded::disable_out_err if(!exists $options->{'index'} && $options->{'threads'} == 1);

  # register processes
	$threads->add_function('bamToBw', \&PCAP::BigWig::bamToBw);

	$threads->run(scalar @{$options->{'sequences'}}, 'bamToBw', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'bamToBw');

  if(!exists $options->{'process'} || $options->{'process'} eq 'generateBw') {
    PCAP::BigWig::generateBw($options);
    &cleanup($options);
  }
}

sub cleanup {
  my $options = shift;
  my $tmpdir = $options->{'tmp'};
  my $final_logs = File::Spec->catdir($options->{'outdir'}, 'logs');
  remove_tree $final_logs if(-e $final_logs);
  move(File::Spec->catdir($tmpdir, 'logs'), $final_logs) || die $!;
  remove_tree $tmpdir if(-e $tmpdir);
	return 0;
}

sub setup {
  my %opts;
  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'v|version' => \$opts{'v'},
              't|threads=i' => \$opts{'threads'},
              'b|bam=s' => \$opts{'bam'},
              'o|outdir=s' => \$opts{'outdir'},
              'r|reference=s' => \$opts{'reference'},
              'p|process=s' => \$opts{'process'},
              'i|index=i' => \$opts{'index'},
              'f|filter=i' => \$opts{'filter'},
              'j|jobs' => \$opts{'jobs'},
              'a|overlap' => \$opts{'overlap'},
  ) or pod2usage(2);

  pod2usage(-message => PCAP::license, -verbose => 1) if(defined $opts{'h'});
  pod2usage(-message => PCAP::license, -verbose => 2) if(defined $opts{'m'});

  if(defined $opts{'v'}) {
    print PCAP->VERSION,"\n";
    exit 0;
  }

  # then check for no args:
  my $defined;
  for(keys %opts) { $defined++ if(defined $opts{$_}); }
  pod2usage(-msg  => "\nERROR: Options must be defined.\n", -verbose => 1,  -output => \*STDERR) unless($defined);

  PCAP::Cli::file_for_reading('bam', $opts{'bam'});
  PCAP::Cli::file_for_reading('reference', $opts{'reference'});
  PCAP::Cli::out_dir_check('outdir', $opts{'outdir'});

  pod2usage(-msg  => "\nERROR: 'bam' must be bam or cram file.\n", -verbose => 1,  -output => \*STDERR) unless($opts{'bam'} =~ m/\..{1,2}am$/);

  delete $opts{'process'} unless(defined $opts{'process'});
  delete $opts{'index'} unless(defined $opts{'index'});
  delete $opts{'filter'} unless(defined $opts{'filter'});
  delete $opts{'overlap'} unless(defined $opts{'overlap'});

  # now safe to apply defaults
  $opts{'threads'} = 1 unless(defined $opts{'threads'});

  my $bam = PCAP::Bam->new($opts{'bam'});

  ($opts{'sample'}, undef) = PCAP::Bam::sample_name($opts{'bam'}, 1);

  my $tmpdir = File::Spec->catdir($opts{'outdir'}, 'tmpBigWig');
  make_path($tmpdir) unless(-d $tmpdir);
  my $progress = File::Spec->catdir($tmpdir, 'progress');
  make_path($progress) unless(-d $progress);
  my $logs = File::Spec->catdir($tmpdir, 'logs');
  make_path($logs) unless(-d $logs);

  $opts{'tmp'} = $tmpdir;
  $opts{'sequences'} = $bam->header_sq;

  if(exists $opts{'process'}) {
    PCAP::Cli::valid_process('process', $opts{'process'}, \@VALID_PROCESS);
    my $max_index = $INDEX_FACTOR{$opts{'process'}};
    if($max_index == -1) {
      $max_index = scalar @{$opts{'sequences'}};
    }
    if(exists $opts{'index'}) {
      PCAP::Cli::opt_requires_opts('index', \%opts, ['process']);
      PCAP::Cli::valid_index_by_factor('index', $opts{'index'}, 1, $max_index);
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

bamToBw.pl - Generate BigWig file from BAM/CRAM, parallel processing where possible.

=head1 SYNOPSIS

bamToBw.pl [options] [file(s)...]

  Required parameters:
    -bam       -b   BAM/CRAM file to be processed.
    -outdir    -o   Folder to output result to.
    -reference -r   Path to genome.fa and genome.fa.fai.

  Optional parameters:
    -overlap   -a   Cleanup overlaping read fragment counts.
    -threads   -t   Number of threads to use. [1]
    -filter    -f   Ignore reads with the filter flags [int]

  Targeted processing:
    -process   -p   Only process this step then exit, optionally set -index
                         bamToBw - Per chromosome BigWigs
                      generateBw - Generates merged BigWig

    -index     -i   Optionally restrict '-p' to single job
                      bwamem - 1..<lane_count>

  Other:
    -jobs      -j   For a parallel step report the number of jobs required
    -help      -h   Brief help message.
    -man       -m   Full documentation.

  Basic usage:
    bamToBw.pl -t 16 -b in.bam -o out.bw

  Advanced/farm usage:
    bamToBw.pl -b in.bam -o out.bw -p bamToBw -i 1..X
     # X can be determined with 'bamToBw.pl -b in.bam -o out.bw -j'
     # once all above steps completed
    bamToBw.pl -b in.bam -o out.bw -p generateBw -i 1


  Run with '-m' for possible input file types.

=head1 OPTIONS

=over 8

=item B<-bam>

Path to BAM or CRAM file to be processed.

=item B<-outdir>

Directory to write output to.  During processing a temp folder will be generated in this area,
should the process fail B<only delete this if> you are unable to resume the process.

Final output files include: <SAMPLE>.bam, <SAMPLE>.bam.bai, <SAMPLE>.md5, <SAMPLE>.met

=item B<-reference>

Path to genome.fa file and associated .fai file.

=item B<-overlap>

Use fragment based counting rather than read based counting.  Gives better represetation
of unique sequence coverage when reads in pair overlap.

=item B<-threads>

Number of threads to be used in processing.

If perl is not compiled with threading some steps will not run in parallel..

=item B<-filter>

Filter input data based on these flags.
See https://broadinstitute.github.io/picard/explain-flags.html

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head2 TARGETED PROCESSING

If you want to run the code in a more efficient manner then this allows each procesing type and
element to be executed in isolation.

=over 8

=item B<-process>

Limit processing to a single element of the process flow.  Work elements within this will
"round-robin" using the available cores until complete (unless B<-index> is defined).

Elements include:
  bamToBw: jobs = number of chromosomes
  generateBw: 1 job

=item B<-index>

Can be used in conjunction with B<-process> to send individual elements for parallel processing.

e.g. bamToBw.pl .... -t 1 -p bamToBw -i 1

Will process the first chromosome only.

=item B<-jobs>

Reports the number of jobs required for a step to complete.  Use this to determine range of
values required for B<-index>.

=back

=head1 DESCRIPTION

B<bamToBw.pl> will attempt to generate a BigWig file per chromosome and then concatenate them into a single file.

=cut
