# CLAUDE.md

Guidance for coding agents working in this repository. Read `README.md` for the overall design; this file lists the rules for changing it.

The repo is public and serves as a portfolio piece. `README.md` describes the owner's setup and how it is engineered, in an impersonal voice: no first-person "I" or "my". Don't turn it into a fork-me template or add a catalog of the installed tools. Agent-facing detail (gotchas, workarounds, troubleshooting) belongs here, not in the README.

## What this repo is

An Ansible playbook that configures the single Mac it runs on. It always runs locally: no remote inventory, no SSH, no fleet. Before any role runs, `site.yml` asserts `connection == local`, `inventory_hostname == localhost`, and `ansible_facts['system'] == 'Darwin'`.

## Hard constraints

- **Never add remote hosts.** `inventory/hosts.yml` has exactly one entry: `localhost` with `ansible_connection: local`. No groups, SSH settings, or `delegate_to` anything but localhost.
- **Never remove or weaken the guard** in `site.yml`'s `pre_tasks`.
- **Never commit secrets.** No tokens, passwords, license keys or private keys in plaintext, and nothing secret in `group_vars/`: the repo is public. Secrets live in the macOS Keychain or a password manager. Vault is not wired up (neither `ansible.cfg` nor the `Makefile` passes a vault password), so if a secret ever becomes unavoidable, add that wiring before vaulting a variable; `.vault_pass*` is already gitignored. The gitleaks pre-commit hook is a backstop, not a substitute.
- **Never hard-code a home directory, username or Homebrew prefix.** Use `ansible_facts['user_dir']` in Ansible and `$HOME` in shell files, and probe `/opt/homebrew` before `/usr/local`. In Ansible, the `preflight` role does the probing; other roles use `homebrew_prefix` and `homebrew_path`. An absolute home path quietly breaks when an account is renamed.
- **Never manage software installed outside Homebrew** (Docker Desktop), or account passwords, the login keychain, `sudoers`, or admin group membership.
- **Never run `make apply` unprompted.** It changes the user's real machine. Validate with `make check`, and apply only when explicitly asked.

## Conventions

- **FQCN everywhere:** `ansible.builtin.file`, `community.general.homebrew`.
- **Name every task** in sentence case, imperative: `Install Homebrew formulae`.
- **Idempotent by construction.** Prefer modules over `command`/`shell`. If a `command` is unavoidable, set `changed_when` and `creates`/`removes`; a task must not report `changed` on every run.
- **Roles define behavior, `group_vars/all/` defines the machine.** Role `defaults/main.yml` holds neutral fallbacks (usually empty lists) so each role does nothing until configured. Machine-specific values go only in `group_vars/all/<topic>.yml`.
- **Prefix variables with the role name** (`homebrew_formulae`, `node_versions`). ansible-lint's `var-naming[no-role-prefix]` enforces it, which is why the preferences role is `roles/macos/`: it owns `macos_defaults` and `macos_defaults_restart_apps`.
- **Tag every role in `site.yml`.** Current tags: `homebrew`, `mas`, `packages`, `ohmyzsh`/`shell`, `git`, `zed`, `node`/`python`/`ruby` (all also `languages`), `macos`/`defaults`. `preflight` is `always`.
- **`become: false` by default.** Opt in per task with `become: true` only where needed, and document that it requires `make apply-sudo`. Never put `become: true` on a brew task: brew refuses to run as root.
- **List only what should be present.** No "absent" or "blocked" lists. Software leaves the repo when its line is deleted; uninstalling it is a one-off manual step.
- **Pin dependencies.** `requirements.yml` uses bounded version ranges.
- **Read-only probes need `check_mode: false`**, or `--check` skips them and leaves registered variables undefined. See `roles/preflight/tasks/main.yml`.

## Module choices

- Formulae: `community.general.homebrew`. Casks: `community.general.homebrew_cask`. Despite the deprecation talk, the `homebrew` module does not handle casks; check the docs before switching.
- Taps: `community.general.homebrew_tap`. Tap trust: `brew trust`, via the homebrew role's `homebrew_trust` lists.
- Mac App Store: `community.general.mas`. Gems: `community.general.gem`. npm: `community.general.npm`.
- macOS preferences: `community.general.osx_defaults`.

Pass package lists to the Homebrew modules as one list, not with `loop:`: a single invocation is much faster.

## Commands

```sh
make check              # dry run with diffs: safe, use it to validate
make check TAGS=homebrew
make lint               # ansible-lint, production profile, strict
make test               # every pre-commit hook, ansible-lint included
make apply              # changes the machine: the user's call
make apply-sudo         # when system-wide preferences are involved
```

After editing YAML, run `make lint`. After editing role logic, run `make check` to confirm it parses and is idempotent.

## Adding things

New software, an App Store app, a preference or a dotfile: edit the matching file in `group_vars/all/`; the roles already handle it. README.md shows the exact shapes. Prefer a Homebrew formula over an npm, uv or gem install.

Before adding a package, confirm where its vendor publishes it now. Formulae leave homebrew/core when their license changes to BUSL (terraform, packer, tflint) and move to a vendor tap, which also needs a `homebrew_trust` entry. Some tools move from formula to cask (Azure CLI since 2.85.0). Check the vendor's macOS install page.

When the cask is for an app already installed by hand, `--adopt` has limits:

- For a cask that doesn't update itself, the installed version must match the cask's or brew refuses. The fix is a one-off `brew install --cask --force <cask>`, which replaces the app and keeps its settings. It's the user's call, so ask first. The same fix applies when the installed app is too old to contain a file the cask links to (Obsidian's `obsidian-cli`).
- `.pkg` casks can't be adopted: brew reruns the installer, and the cask install shows the askpass password dialog.
- Don't add Microsoft Office casks over an existing install: the licensing package's postinstall aborts the whole install. Microsoft AutoUpdate manages Office.

A new _category_ of configuration warrants a new role: `roles/<name>/{tasks,defaults}/main.yml`, a matching `group_vars/all/<name>.yml`, a tagged entry in `site.yml`, and a README section.

Current roles: `preflight`, `homebrew`, `mas`, `ohmyzsh`, `git`, `zed`, `node`, `python`, `ruby`, `macos`.

## Shell and app config

There is no dotfiles role and nothing is symlinked. `.zshrc` and `.zprofile` are edited in place:

- Additive config goes in marked `ansible.builtin.blockinfile` regions.
- Values another tool already owns are changed with `ansible.builtin.replace`.
- Shell integrations that oh-my-zsh ships as plugins (`direnv`, `fzf`, `zoxide`) go in `ohmyzsh_plugins`, not in new blocks.

Each role owns its own marker (`# {mark} ANSIBLE MANAGED BLOCK - <name>`); never reuse one across roles. The `ohmyzsh` role runs oh-my-zsh's official installer rather than a bare clone, because the installer's `umask` keeps `~/.oh-my-zsh` out of compinit's insecure-directories check.

Files with a single owner are copied whole from `roles/<role>/files/`. `.zshenv` is not managed.

## Code-level gotchas

Each of these was learned the hard way. Keep the workaround unless the cause is gone.

- Any brew task that can touch casks needs `environment: SUDO_ASKPASS: "{{ playbook_dir }}/scripts/askpass"`. `.pkg` casks run `sudo` with no TTY; `become: true` can't help because brew refuses to run as root, and `-K` never reaches brew's own `sudo`.
- `make update` runs `brew upgrade ansible` before the playbook. Don't remove it: if brew upgrades Ansible mid-run, the controller can't load its own modules (`Unknown profile name`) even though brew succeeded.
- The `mas` role installs the CLI when `mas_apps | length > 0 or mas_upgrade_all | bool`, and guards `upgrade_all` with a `stat` on the binary. Keep both: `community.general.mas` with `upgrade_all` aborts the play if `mas` is missing, and under `--check` the install only pretends to happen.
- Tap trust is a `command` task, so `--check` skips it, and the first `make check` after trusting a new entry fails with "untrusted tap". That's expected; one `make apply` fixes it. Don't work around it.
- `nvm install` reports "already installed" on stderr, so its output can't decide `changed`. Gate on `nvm version <alias>` returning `N/A`, and write versions as `lts/*`: `--lts` installs but doesn't resolve with `nvm version`, so it looks missing on every run.
- `$HOMEBREW_PREFIX` exists only in login shells (from `.zprofile`). The `.zshrc` blocks doing nothing in non-login subshells is intentional; don't add a guard that re-derives the prefix.
- Use `ansible_facts['env']['PATH']`, not the deprecated `ansible_env.PATH`.
- Check `defaults read-type` before adding a `macos_defaults` entry: a type mismatch fails the task (`com.apple.dock tilesize` is a float, not an int).

## Things that resist automation

Some macOS configuration can't be automated cleanly: Full Disk Access and App Management grants, other TCC prompts, App Store sign-in, Apple ID. Don't invent fragile `shell` workarounds, such as `sqlite3` against TCC.db. Document the manual step in the README instead.
