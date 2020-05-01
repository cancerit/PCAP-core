#!/usr/bin/perl

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2019-2020 ICGC PanCancer Project
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
use version;

const my $COORD_SORT_ORDER => 'coordinate';
const my $QUERYNAME_SORT_ORDER => 'queryname';
const my @VALID_PROCESS => qw(setup mark stats);
const my %INDEX_FACTOR => ( 'setup' => 1,
                            'mark'   => 1,
                            'stats'  => 1,);

{
  my $options = setup();

  PCAP::Bwa::mem_setup($options, 1) if(!exists $options->{'process'} || $options->{'process'} eq 'setup');

  if(!exists $options->{'process'} || $options->{'process'} eq 'mark') {
    PCAP::Bam::merge_or_mark_lanes($options, @{$options->{'raw_files'}});
  }
  if(!exists $options->{'process'} || $options->{'process'} eq 'stats') {
    PCAP::Bam::bam_stats($options);
    &cleanup($options);
  }
}

sub cleanup {
  my $options = shift;
  my $tmpdir = $options->{'tmp'};
  move(File::Spec->catdir($tmpdir, 'logs'), File::Spec->catdir($options->{'outdir'}, 'logs_merge_or_mark_'.$options->{'sample'})) || die $!;
  remove_tree $tmpdir if(-e $tmpdir);
	return 0;
}

sub setup {
  my %opts = (
              'threads' => 1,
              'csi' => undef,
              'sortorder' => $COORD_SORT_ORDER,
             );

  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'v|version' => \$opts{'v'},
              't|threads:i' => \$opts{'threads'},
              'r|reference=s' => \$opts{'reference'},
              'o|outdir=s' => \$opts{'outdir'},
              's|sample=s' => \$opts{'sample'},
              'n|nomarkdup' => \$opts{'nomarkdup'},
              'p|process=s' => \$opts{'process'},
              'q|querynamesort' => \$opts{'qnamesort'},
              'i|noindex' => \$opts{'noindex'},
              'csi' => \$opts{'csi'},
              'c|cram' => \$opts{'cram'},
              'sc|scramble=s' => \$opts{'scramble'},
  ) or pod2usage(2);

  pod2usage(-verbose => 1, -exitval => 0) if(defined $opts{'h'});
  pod2usage(-verbose => 2, -exitval => 0) if(defined $opts{'m'});

  if(defined $opts{'v'}) {
    print PCAP->VERSION,"\n";
    exit 0;
  }

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
  delete $opts{'scramble'} unless(defined $opts{'scramble'});
  delete $opts{'csi'} unless(defined $opts{'csi'});
  if($opts{'qnamesort'} && !$opts{'nomarkdup'}){
      die "ERROR: -qnamesort can only be used in conjunction with -nomarkdups\n";
  }
  if($opts{'noindex'} && !$opts{'qnamesort'}){
      die "ERROR: -noindex can only be used in conjunction with -qnamesort\n";
  }
  $opts{'sortorder'} = $QUERYNAME_SORT_ORDER if($opts{'qnamesort'});

  if($opts{'threads'} > 4) {
    warn "Setting 'threads' to 4 as higher values are of limited value\n";
    $opts{'threads'} = 4;
  }

  PCAP::Cli::opt_requires_opts('scramble', \%opts, ['cram']);

  my $tmpdir = File::Spec->catdir($opts{'outdir'}, 'tmpMark_'.$opts{'sample'});
  make_path($tmpdir) unless(-d $tmpdir);
  my $progress = File::Spec->catdir($tmpdir, 'progress');
  make_path($progress) unless(-d $progress);
  my $logs = File::Spec->catdir($tmpdir, 'logs');
  make_path($logs) unless(-d $logs);

  $opts{'tmp'} = $tmpdir;

  $opts{'raw_files'} = [];
  my $cwd = cwd();
  for(@ARGV) {
    $_ = "$cwd/$_" unless($_ =~ m|^/|);
    push @{$opts{'raw_files'}}, $_ if(-e $_);
  }
  pod2usage(-msg  => "\nERROR: No accessible BAM/CRAM files have been defined.\n", -verbose => 1,  -output => \*STDERR) if(scalar @{$opts{'raw_files'}} == 0);

  return \%opts;
}

__END__

=head1 NAME

merge_or_mark.pl - Merge multiple lanes generated by bwa_mem.pl into sample level file

=head1 SYNOPSIS

merge_or_mark.pl [options] [file(s)...]

  Required parameters:
    -outdir      -o   Folder to output result to.
    -reference   -r   Path to reference genome file *.fa[.gz]
    -sample      -s   Sample name to be applied to output file.

  Optional parameters:
    -threads     -t   Number of threads to use (max=4). [1]
    -nomarkdup   -n   Don't mark duplicates [flag]
    -qnamesort   -q   Use queryname sorting flag in bammerge rather than coordinate. [flag].
                      To be used in conjunction with -nomarkdup only
    -noindex     -i   Don't attempt to index the merged file. Only available in conjunction with 
                      -qnamesort.
    -csi              Use CSI index instead of BAI for BAM files [flag].
    -cram        -c   Output cram, see '-sc' [flag]
    -scramble    -sc  Single quoted string of parameters to pass to Scramble when '-c' used
                      - '-I,-O' are used internally and should not be provided

  Targeted processing:
    -process     -p   Only process this step then exit, optionally set -index
                        bwamem - only applicable if input is bam
                          mark - Run duplicate marking (-index N/A)
                         stats - Generates the *.bas file for the final BAM.

  Other:
    -help        -h   Brief help message.
    -man         -m   Full documentation.
    -version     -v   Print version and exit

File list can be full file names or wildcard, e.g.

=over 4

=item mutiple BAM or CRAM inputs, not mixed

 merge_or_mark.pl -t 4 -r some/genome.fa.gz -o myout -s sample input/*.bam

=back

=head1 DESCRIPTION

B<merge_or_mark.pl> will merge multiple lane BAM/CRAM files together, appropriately handling mismatchQc if duplicate
marking is active.

=head1 OPTION DETAILS

=over 4

=item B<-outdir>

Directory to write output to.  During processing a temp folder will be generated in this area,
should the process fail B<only delete this if> you are unable to resume the process.

Final output files include: <SAMPLE>.bam, <SAMPLE>.bam.bai, <SAMPLE>.bam.bas, <SAMPLE>.md5, <SAMPLE>.met

(substitute cram, crai, csi as appropriate)

=item B<-reference>

Path to genome.fa[.gz] file (for cram)

=item B<-sample>

Name to be applied to output file.  Special characters will not be magically fixed.

=item B<-threads>

Number of helper threads to be used in processing, values >=4 are ignored.

=back

=head2 OPTIONAL parameters

=over 4

=item B<-nomarkdup>

Disables duplicate marking, switching bammarkduplicates2 for bammerge.

=item B<-csi>

User CSI style index for final BAM file instead of default BAI.

=item B<-qnamesort>

Use queryname sorting in bammerge calls rather than the default coordinate.
Can only be used in combination with B<-nomarkdup>

=item B<-noindex>

Don't attempt to generate an index for the merged file.
Can only be used in combination with B<-qnamesort>

=item B<-cram>

Final output file will be a CRAM file instead of BAM.  To tune the the compression methods see then
B<-scramble> option.

=item B<-scramble>

Single quoted string of parameters to pass to Scramble when '-c' used.  Please see the Scramble
documentation for details.

Please note: '-I,-O' are used internally and should not be provided.

=back

=head2 TARGETED PROCESSING

=over 4

=item B<-process>

If you want to run the code in a more efficient manner then this allows each procesing type to be
executed in isolation.

=back

=head2 INPUT FILE TYPES

There are several types of file that the script is able to process.

=over 4

=item bam

Single lane BAM files, RG lines are transfered merged files.  Also accepts multi lane BAM.

=item cram

Single lane CRAM files, RG lines are transfered merged files.  Also accepts multi lane CRAM.

=back

=cut
