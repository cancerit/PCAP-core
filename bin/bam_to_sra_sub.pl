#!/usr/bin/perl

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014 ICGC PanCancer Project
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

use Getopt::Long;
use Pod::Usage;

use PCAP::Cli;
use PCAP::SRA;

{
  # all inputs are checked here
  my $options = &setup;
  # all bam headers are checked here
  my $sra = PCAP::SRA->new($options->{'raw_files'}, $options->{'type'});
  $sra->generate_sample_SRA($options);
}


sub setup {
  my %opts;
  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
#              'd|detail' => \$opts{'d'},
              'o|outdir=s' => \$opts{'outdir'},
              's|study=s' => \$opts{'study'},
              'g|gnos=s' => \$opts{'gnos'},
              't|type=s' => \$opts{'type'},
  ) or pod2usage(2);

  pod2usage(-message => PCAP::license, -verbose => 1) if(defined $opts{'h'});
  pod2usage(-message => PCAP::license, -verbose => 2) if(defined $opts{'m'});

  # then check for no args:
  my $defined;
  for(keys %opts) { $defined++ if(defined $opts{$_}); }
  pod2usage(-msg  => "\nERROR: Options must be defined.\n", -verbose => 1,  -output => \*STDERR) unless($defined);

  pod2usage(-msg => qq{\nERROR: 'outdir' must be defined.\n}, -verbose => 2,  -output => \*STDERR) unless(defined $opts{'outdir'});
  pod2usage(-msg => qq{\nERROR: 'gnos' must be defined.\n}, -verbose => 2,  -output => \*STDERR) unless(defined $opts{'gnos'});

  PCAP::Cli::out_dir_check('outdir', $opts{'outdir'}, 1);

  if(defined $opts{'type'}) {
    # check seq type is part of the controlled vocab
    PCAP::SRA::validate_seq_type($opts{'type'});
  }

  $opts{'study'} = 'icgc_pancancer' unless(defined $opts{'study'});

  pod2usage(-msg  => "\nERROR: Please provide a list of inputs files after any options\n", -verbose => 1,  -output => \*STDERR) unless(scalar @ARGV > 0);
  $opts{'raw_files'} = \@ARGV;
  return \%opts;
}

#    -detail    -d   Generate a detail summary file to <outdir>/detail.tsv

__END__

=head1 NAME

bam_to_sra_sub.pl - Generate SRA submission.

=head1 SYNOPSIS

bam_to_sra_sub.pl [options] [file(s)...]

  Required parameters:
    -outdir    -o   Folder to output result to.
    -gnos      -g   GNOS upload server, e.g.
                      https://gtrepo-ebi.annailabs.com

  Optional:
    -study     -s   Study reference in repository [icgc_pancancer]
    -type      -t   Only required if not encoded in readgroup LB tag.
                      [WGS|WXS|RNA-seq]
                      See '-m' for details

  Other:
    -help      -h   Brief help message.
    -man       -m   Full documentation.

  File list can be full file names, wildcards or combination, e.g.

    bam_to_sra_sub.pl -s icgc_pancancer -o myDonor/tumour_sra myDonor/tumour/*.bam

=head1 OPTIONS

=over 8

=item B<-outdir>

Directory to write output to.  All SRA XML files will be written to a 'sample' directory in this area,
Associated BAM files and MD5s will be symlinked into this area for easy upload.

Please ensure that you will be able to read from the area with GeneTorrent otherwise you will need to
copy the data into an appropriate location (remembering to follow symlinks).

=item B<-gnos>

The path to the GNOS server that this data should be submitted to.

=item B<-study>

The STUDY_REF that this data is to be assigned to in the repository.
Defaults to icgc_pancancer when not specified.

=item B<-type>

Added for convenience when sequencing type is not encoded into the RG:LB tag

  WGS     - Whole Genome Seq
  WXS     - Whole eXome Seq
  RNA-Seq - RNA seq

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back


