# PCAP-core

NGS reference implementations and helper code for mapping and mapping related stats.

This has been forked from the [ICGC-TCGA-PanCancer/PCAP-core](https://github.com/ICGC-TCGA-PanCancer/PCAP-core)
repository as this codebase was created by [cancerit](https://github.com/cancerit) and continues to be developed.
This version strips out PCAWG related elements and incorporates more efficient code.

| Master | Dev |
|---|---|
| [![Build Status](https://travis-ci.org/cancerit/PCAP-core.svg?branch=master)](https://travis-ci.org/cancerit/PCAP-core) |  [![Build Status](https://travis-ci.org/cancerit/PCAP-core.svg?branch=dev)](https://travis-ci.org/cancerit/PCAP-core) |

This repository contains code to run genomic alignments of paired end data
and subsequent calling algorithms.

The intention is to provide reference implementations and simple to execute wrappers
that are useful for the scientific community who may have little IT/bioinformatic support.

Please see the [wiki](https://github.com/cancerit/PCAP-core/wiki) for further details.

## Dependencies/Install

Please be aware that this expects basic C compilation libraries and tools to be available, most are listed in `INSTALL`.

Please install the following before running `setup.sh`:

* [cgpBigWig](https://github.com/cancerit/cgpBigWig/releases)

Dependancies installed by `setup.sh`:

* [biobambam](https://github.com/gt1/biobambam)
* [bwa](https://github.com/lh3/bwa)
* [samtools](https://github.com/samtools/samtools)

And various perl modules.

Please see the respective licence for each before use.

## Programs

Please see the [wiki](https://github.com/cancerit/PCAP-core/wiki) for details of programs.

## Creating a release

### Preparation

* Commit/push all relevant changes.
* Pull a clean version of the repo and use this for the following steps.

### Cutting the release

1. Update `lib/PCAP.pm` to the correct version.
1. Ensure upgrade path for new version number is added to `lib/PCAP.pm`.
1. Update `CHANGES.md` to show major items.
1. Run `./prerelease.sh`
1. Check all tests and coverage reports are acceptable.
1. Commit the updated docs tree and updated module/version.
1. Push commits.
1. Use the GitHub tools to draft a release.
