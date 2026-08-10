# Security

## Supported versions

| Version | Supported |
| :--- | :--- |
| 1.0.x | Yes |
| Older | No, upgrade to the [latest release](https://github.com/PerfectoWeb/Gibson/releases/latest) |

Fixes land on `main` and go out in the next tagged release. There is no
long term support branch.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use **[Report a vulnerability](https://github.com/PerfectoWeb/Gibson/security/advisories/new)**
on the Security tab. That opens a private advisory visible only to you and the
maintainers. If you would rather not use GitHub, the contact form at
[perfecto-web.com](https://perfecto-web.com) reaches the same person.

Useful things to include: the macOS version, whether the machine is Apple
silicon or Intel, which release you installed, and the smallest set of steps
that reproduces the problem.

Expect a first reply within a week. If the report is valid, you will get a fix
timeline with it, and credit in the release notes unless you would rather stay
anonymous.

## What the screen saver actually does

Worth knowing before deciding whether something is a vulnerability.

- **No network.** Gibson opens no sockets and sends nothing anywhere. Every
  number on screen is read from local kernel counters, and the rest is
  generated on the machine. The network panel reports throughput by reading
  interface byte counters, which is not the same as using the network.
- **No storage.** Nothing is written apart from the preferences you set in the
  options sheet, which live in the sandboxed container of the host process.
- **No elevated privileges.** The bundle asks for nothing, and macOS runs it
  inside `legacyScreenSaver.appex`. Calls that a sandbox denies degrade to an
  empty reading rather than a failure.
- **Read only sampling.** `host_processor_info`, `host_statistics64`,
  `sysctl` for the process list, `getifaddrs`, and volume capacity through
  Foundation. The process list is what any user on the machine can already see
  with `ps`, and the **Mask host name, user and addresses** option hides the
  identifying parts of it on a lock screen.
- **No dependencies.** Nothing is vendored and no package manager is involved,
  so there is no supply chain below the system frameworks.

Releases are signed with a Developer ID certificate and notarised by Apple, and
the ticket is stapled to the bundle. If macOS reports a signature problem on a
build downloaded from the releases page, treat that as a security report and
tell us, because it should never happen.

Builds you make yourself are signed ad hoc, which is why macOS asks you to
confirm them once. That is expected, not a defect.
