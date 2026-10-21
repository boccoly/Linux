# cyberpatriot-linux

Linux checklists and recon tooling for CyberPatriot. Built for **Linux Mint** (Ubuntu-based), works on Ubuntu/Debian images with minor changes.

Read `checklist/0-round-flow.md` first. Everything else is detail for one step of that flow.

## Directory index

| Path | What's in it |
|---|---|
| `checklist/` | The round, broken into ordered steps. Work them in numbered order. |
| `mint.md` | Linux Mint specifics — things that differ from plain Ubuntu. Read before the first round. |
| `scripts/recon.sh` | Read-only enumeration. Run it first, read the output, then start fixing. |
| `reference/scoring-patterns.md` | What has actually scored in past rounds, roughly by frequency. |
| `reference/commands.md` | Command lookup for when you know what you want but not the syntax. |

## How to use this during a round

1. Read the README on the image. Write down the authorized users, the admins, and every service the scenario says must keep running.
2. Answer the forensics questions **before** you change anything — hardening destroys the evidence they ask about.
3. Run `scripts/recon.sh`. Read the output. It tells you what's unusual on *this* image rather than what's on a generic checklist.
4. Work `checklist/` in order, 0 through 6.
5. Reboot after kernel updates, then re-check that required services still run.

## Rules this repo follows

- **Nothing here deletes files.** Recon is read-only. Where a step removes something, you run it yourself after reading the output.
- **Restart the service after you change its config**, or the change doesn't count.
- **Never break a required service.** A broken critical service costs more than any vulnerability is worth. Check the README's list before disabling anything.
- **One change at a time on anything auth-related** (PAM, sudoers, sshd). Keep a second terminal open and logged in while you edit them.
