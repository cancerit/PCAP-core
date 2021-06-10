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
use Test::More;
use Const::Fast qw(const);

const my $MODULE => 'PCAP';

subtest 'Initialisation checks' => sub {
  use_ok($MODULE);
};


ok(PCAP::license(), 'License text retrieved');
ok(PCAP->VERSION, 'Version retrieved');

is(PCAP::upgrade_path(), 'biobambam,samtools,bwa', 'Default program install when no previous version');
is(PCAP::upgrade_path('9.9.9'), 'biobambam,samtools,bwa', 'Default program install when unknown version installed');

done_testing();
