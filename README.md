# Linux — CyberPatriot toolkit

Built for Linux Mint 21 and Debian 12. Works on Ubuntu and most Debian derivatives.

## The idea

A round has two kinds of work, and conflating them is why most teams' scripts end up either useless or dangerous.

**Deterministic work** is identical on every image. `kernel.randomize_va_space = 2` is correct whether the scenario is a hospital or a bank. Password aging, firewall defaults, permissions on `/etc/shadow`, sysctl, PAM policy — none of it requires reading anything. Doing it by hand costs an hour and introduces typos at hour four.

→ **Automated.** `harden.sh` applies all of it in one command.

**Judgment work** depends on this specific image. Which users are authorized, which services the scenario requires, which files are prohibited, what the attacker changed. A script that guesses here deletes real accounts and breaks required services.

→ **Reported, not acted on.** `recon.sh` and `baseline-diff.sh` tell you what's there. You decide.

The boundary is blast radius: automate what's recoverable and image-independent, keep a human on what isn't.

## Scripts

| Script | Acts? | Purpose |
|---|---|---|
| `harden.sh` | **Yes** | 13 modules of deterministic hardening. Full backup, `--rollback`, `--dry-run` |
| `users.sh` | On `--apply` | Reconciles accounts against a list you write from the README |
| `recon.sh` | No by default | Discovery: accounts, packages, persistence, forensic artifacts, prohibited content |
| `baseline-diff.sh` | No | Diffs the image against a clean-system snapshot |
| `make-baseline.sh` | No | Builds that snapshot, on a clean VM, before the season |

## Round flow

```sh
# 1. read the README, write down users / services / forensics questions
sudo cp -a /etc /home /root/backup-$(date +%s)

# 2. forensics BEFORE you change anything

# 3. discovery
sudo bash scripts/recon.sh
sudo bash scripts/baseline-diff.sh baseline/<os>

# 4. hardening - one command
sudo bash scripts/harden.sh
su - someuser && sudo -v          # ALWAYS verify login still works

# 5. users
cat > authorized.txt <<'EOF'
alice admin
bob   user
EOF
sudo bash scripts/users.sh authorized.txt
sudo bash scripts/users.sh authorized.txt --apply

# 6. open the ports the README requires, then updates
sudo ufw allow 22/tcp
sudo apt update && sudo apt dist-upgrade -y
```

Full version with timings in `checklist/0-round-flow.md`.

## Layout

```
scripts/      the tooling, with its own README for per-script usage
checklist/    the manual half, in round order (0 through 6)
baseline/     clean-system snapshots, one directory per OS version
reference/    scoring frequency data and a command lookup
mint.md       Linux Mint specifics vs plain Ubuntu
```

## Before the season

Build a baseline for each OS you might face. Without one you're running a checklist; with one you're reading a diff.

```sh
# on a CLEAN VM of the matching OS, version and desktop edition
# no updates, nothing installed
sudo bash scripts/make-baseline.sh ./baseline
```

Procedure in `checklist/3-audit.md`.

## Rules

- **Read the image README first.** It overrides everything here. Required services, authorized users, and "install software X" are all scored and all only findable there.
- **Answer forensics questions before changing anything.** Hardening destroys the evidence.
- **Keep a second root terminal open all round.** It's your way back from a bad PAM or sudoers edit.
- **Never break a required service.** It costs more than any vulnerability is worth.
- **`sshd -t` before restarting SSH.** Always.

## Credits

The baselining approach — snapshot a clean `/etc` and diff against it — comes from [oakrc/cypalinux](https://github.com/oakrc/cypalinux), whose `xx.default-config` and `xx.fs-compare` modules do the same thing inside a larger framework.

Methodology, and the argument that CyberPatriot is an incident-response competition rather than a hardening one, is from Akshay Rohatgi's [How To Win CyberPatriot](https://akshayrohatgi.com/blog/posts/How-To-Win-CyberPatriot/).

Domain coverage and forensic artifact locations draw on [tirefire's Cyber Patriot Curriculum](https://tirefire.org/posts/cyberpatriot-curriculum/).

Scoring frequency data in `reference/scoring-patterns.md` comes from my own team's scored rounds.
