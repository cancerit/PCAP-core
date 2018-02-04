# Contributing

Contributions are welcome, and they are greatly appreciated! Every
little bit helps, and credit will always be given.

This project could always use more documentation, whether as part of the
README, in docstrings, or even on the web in blog posts articles, and such.

Please learn about [`semantic versioning`][semver].

# Contents

- [Contributing](#contributing)
- [Contents](#contents)
- [Development](#development)
    - [Bug reports, Feature requests and feedback](#bug-reports-feature-requests-and-feedback)
    - [Pull Request Guidelines](#pull-request-guidelines)
- [Creating a release](#creating-a-release)

# Development

Set up for local development:

1. Clone your cookiecutter-cli locally:


        git clone https://github.com/cancerit/PCAP-core.git


2. Checkout to development branch:

        git checkout develop
        git pull

3. Create a branch for local development:

        git checkout -b name-of-your-bugfix-or-feature

    Now you can make your changes locally.

4. If you contributed a new feature, create a test in:

        PCAP-core/c/c_tests/

5. Commit your changes and push your branch to GitHub:

        git add .
        git commit -m "Your meaningful description"
        git push origin name-of-your-bugfix-or-feature

6. Submit a pull request through the GitHub website.

## Bug reports, Feature requests and feedback

Go ahead and file an issue at https://github.com/cancerit/PCAP-core/issues.

If you are proposing a **feature**:

* Explain in detail how it would work.
* Keep the scope as narrow as possible, to make it easier to implement.
* Remember that this is a volunteer-driven project, and that code contributions are welcome :)

When reporting a **bug** please include:

* Your operating system name and version.
* Any details about your local setup that might be helpful in troubleshooting.
* Detailed steps to reproduce the bug.

## Pull Request Guidelines

If you need some code review or feedback while you're developing the code just make the pull request.

For merging, you should:

1. Include passing tests.
2. Update documentation when there's new API, functionality etc.

# Creating a release

Commit/push all relevant changes. Pull a clean version of the repo and use this for the following steps:

1. Update `lib/PCAP.pm` to the correct version.

2. Ensure upgrade path for new version number is added to `lib/PCAP.pm`.

3. Update `CHANGES.md` to show major items.

4. Run `./prerelease.sh`.

5. Check all tests and coverage reports are acceptable.

6. Commit the updated docs tree and updated module/version.

7. Push commits.

8. Use the GitHub tools to draft a release.

9. Update [INSTALL](INSTALL.md) and [Dockerfile](Dockerfile) if new dependencies are required.

10. Publish docker image, get `{VERSION}` from `lib/PCAP.pm`:

        docker build -t cancerit/pcap-core:{VERSION} .
        docker push cancerit/pcap-core:{VERSION}

<!-- References -->
[semver]: http://semver.org/
