package PCAP;

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2018 ICGC PanCancer Project
# Copyright (C) 2018-2019 Cancer, Ageing and Somatic Mutation, Genome Research Limited
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
use Const::Fast qw(const);
use base 'Exporter';
use FindBin qw($Bin);
use File::Which qw(which);
# don't use autodie, only core perl in here

our $VERSION = '5.0.1';
our @EXPORT = qw($VERSION _which);

const my $LICENSE =>
"#################
# PCAP version %s
# PCAP comes with ABSOLUTELY NO WARRANTY
# See LICENSE for full details.
#################";

const my $DEFAULT_PATH => 'biobambam,samtools,bwa';
const my %UPGRADE_PATH => ( # just always install, it's safer
                          );

sub license {
  return sprintf $LICENSE, $VERSION;
}

sub upgrade_path {
  my $installed_version = shift;
  return $DEFAULT_PATH if(!defined $installed_version);
  chomp $installed_version;
  return $DEFAULT_PATH if(!exists $UPGRADE_PATH{$installed_version});
  return $UPGRADE_PATH{$installed_version};
}

sub _which {
  my $prog = shift;
  my $l_bin = $Bin;
  my $path = File::Spec->catfile($l_bin, $prog);
  $path = which($prog) unless(-e $path);
  die "Failed to find $prog in path or local bin folder ($l_bin)\n\tPATH: $ENV{PATH}\n" unless(defined $path && -e $path);
  return $path;
}

sub ref_lengths {
  my $fai_file = shift;
  my %ctg_lengths;
  open my $FAI, '<', $fai_file or die $!;
  while(my $l = <$FAI>) {
    my ($ctg, $len) = split /\t/, $l;
    $ctg_lengths{$ctg} = $len;
  }
  close $FAI;
  return \%ctg_lengths;
}

1;

__END__

=head1 NAME

PCAP - Base class to house version and generic functions.

=head2 Methods

=over 4

=item license

  my $brief_license = PCAP::licence;

Output the brief license text for use in help messages.

=item upgrade_path

  my $install_these = PCAP::upgrade_path('<current_version>');

Return the list of tools that should be installed by setup.sh when upgrading from a previous version.

=item ref_lengths

  my $ref_lengths = PCAP::ref_lengths($fai_file);

Return a hash ref of reference sequence lengths keyed by sequence/contig name.

=back
