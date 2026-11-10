# Security policy

## Reporting a vulnerability

Please report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/cyang2020/brk/security/advisories/new)
(the repository's **Security** tab, then **Report a vulnerability**). Do not open a public issue,
discussion or pull request for a vulnerability until a fix has shipped.

If that form is not available, open an issue that only asks for a private way to reach the maintainer,
without any details of the problem.

A useful report has:

- the Brk version and commit (Help › Troubleshooting › Copy Brk Info, minus the data folder line);
- macOS version and Mac (Apple silicon or Intel);
- what an attacker can do, and the steps or a page that shows it.

You will get a reply when the report has been read. Once a fix is merged, the advisory is published with
credit to you unless you prefer otherwise.

## What counts

Brk is a browser, so the most important problems are ones a web page can trigger:

- a page reading or changing data it should not reach (other sites, other profiles, incognito windows,
  files on the Mac);
- a page or link getting Brk to run commands, open local files, or talk to the user's AI agent without the
  user's approval;
- Brk's AI features sending tabs, page text or files anywhere the user did not choose;
- secrets (API keys, agent sign-ins) being written where other apps or pages can read them.

Bugs in Chromium itself belong to the [Chromium project](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/).
Tell us too if Brk ships a Chromium version with a known fix missing.

## Supported versions

Only the newest build is supported: the rolling
[Latest build](https://github.com/cyang2020/brk/releases/tag/latest) and the newest `v*` release.
