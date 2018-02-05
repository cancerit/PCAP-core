# PCAP-core

NGS reference implementations and helper code for mapping and mapping related stats.

This has been forked from the [ICGC-TCGA-PanCancer/PCAP-core][old_repo] repository as this codebase was created by [cancerit][cancerit_github] and continues to be developed. This version strips out `PCAWG` related elements and incorporates more efficient code.

| Master                                        | Develop                                         |
| --------------------------------------------- | ----------------------------------------------- |
| [![Master Badge][travis-master]][travis-base] | [![Develop Badge][travis-develop]][travis-base] |


This repository contains code to run genomic alignments of paired end data and subsequent calling algorithms.

The intention is to provide reference implementations and simple to execute wrappers that are useful for the scientific community who may have little IT/bioinformatic support.

Please see the [wiki][wiki] for further details and available programs.

# Contents

- [PCAP-core](#pcap-core)
- [Contents](#contents)
- [Installation](#installation)
- [Contributing](#contributing)

# Installation

Please install the following before running `setup.sh`:

* [cgpBigWig][cgpBigWig]

To install this package run:

    setup.sh /path/to/installation

⚠️ Be aware that this expects basic C compilation libraries and tools to be available, check the [`INSTALL`](INSTALL.md) for system specific dependencies (e.g. Ubuntu, OSX, etc.).

`setup.sh` will install the following external dependencies and various perl modules:

* [biobambam][biobambam]
* [bwa][bwa]
* [samtools][samtools]

Its important that you review the respective licence for each before use.

# Contributing

Contributions are welcome, and they are greatly appreciated, check our [contributing guidelines](CONTROBUTING.md)!

<!-- References -->

[cgpBigWig]: https://github.com/cancerit/cgpBigWig/releases
[biobambam]: https://github.com/gt1/biobambam
[bwa]: https://github.com/lh3/bwa
[samtools]: https://github.com/samtools/samtools
[wiki]: https://github.com/cancerit/PCAP-core/wiki
[cancerit_github]: https://github.com/cancerit
[old_repo]: https://github.com/ICGC-TCGA-PanCancer/PCAP-core

<!-- Travis -->
[travis-base]: https://travis-ci.org/cancerit/PCAP-core
[travis-master]: https://travis-ci.org/cancerit/PCAP-core.svg?branch=master
[travis-develop]: https://travis-ci.org/cancerit/PCAP-core.svg?branch=develop
