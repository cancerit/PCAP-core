# PCAP-core

NGS reference implementations and helper code for mapping and mapping related stats.

This has been forked from the [ICGC-TCGA-PanCancer/PCAP-core][PCAP-core]
repository as this codebase was created by [cancerit](cancerit_github) and continues to be developed.
This version strips out PCAWG related elements and incorporates more efficient code.

| Master                                        | Develop                                         |
| --------------------------------------------- | ----------------------------------------------- |
| [![Master Badge][travis-master]][travis-base] | [![Develop Badge][travis-develop]][travis-base] |

This repository contains code to run genomic alignments of paired end data
and subsequent calling algorithms.

The intention is to provide reference implementations and simple to execute wrappers
that are useful for the scientific community who may have little IT/bioinformatic support.

<!-- TOC depthFrom:2 depthTo:6 withLinks:1 updateOnSave:1 orderedList:0 -->

- [General usage](#general-usage)
- [Docker, Singularity and Dockstore](#docker-singularity-and-dockstore)
- [Dependencies/Install](#dependenciesinstall)
- [Creating a release](#creating-a-release)
	- [Preparation](#preparation)
	- [Cutting the release](#cutting-the-release)

<!-- /TOC -->

## General usage

Available programs are described in the [wiki][wiki].

## Docker, Singularity and Dockstore

There are docker and dockstore.org wrappers for this project at [dockstore-cgpmap][dockstore-cgpmap].

The docker image is held on [quay.io][quay-io-cgpmap].

The CWL bindings of `dockstore-cgpmap` specifically target execution of the BWA mem mapping flow,
however all tools are contained in the image and can be used if you construct the relevant docker
commands.

The docker image is know to work correctly after import into a singularity image.

See the [dockstore-cgpmap][dockstore-cgpmap] documentation for more detail.

## Dependencies/Install

Please be aware that this expects basic C compilation libraries and tools to be available, most are listed in `INSTALL`.

Please install the following before running `setup.sh`:

* [cgpBigWig][cgpBigWig]

Dependancies installed by `setup.sh`:

* [biobambam][biobambam]
* [bwa][bwa]
* [samtools][samtools]

And various perl modules.

Please see the respective licence for each before use.

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

<!-- References -->

[cgpBigWig]: https://github.com/cancerit/cgpBigWig/releases
[biobambam]: https://github.com/gt1/biobambam
[bwa]: https://github.com/lh3/bwa
[samtools]: https://github.com/samtools/samtools
[wiki]: https://github.com/cancerit/PCAP-core/wiki
[cancerit_github]: https://github.com/cancerit
[old_repo]: https://github.com/ICGC-TCGA-PanCancer/PCAP-core
[dockstore-cgpmap]: https://github.com/cancerit/dockstore-cgpmap
[quay-io-cgpmap]: https://quay.io/repository/wtsicgp/dockstore-cgpmap

<!-- Travis -->
[travis-base]: https://travis-ci.org/cancerit/PCAP-core
[travis-master]: https://travis-ci.org/cancerit/PCAP-core.svg?branch=master
[travis-develop]: https://travis-ci.org/cancerit/PCAP-core.svg?branch=develop
