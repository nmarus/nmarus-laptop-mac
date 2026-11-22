# nmarus-laptop-mac

Ansible playbook that manages Homebrew packages, Mac App Store apps, shell config, git, editor settings, language toolchains and macOS preferences.

## Design

- **Local-only by construction.** Before any role runs, `site.yml` asserts that the connection is local, the host is `localhost` and the system is macOS. The inventory has exactly one host.
- **Roles define behavior, `group_vars/all/` defines the machine.** Each role's `defaults/main.yml` holds empty lists, so a role does nothing until `group_vars/all/` gives it something to install or set. Emptying a list switches a feature off.
- **Only what should be present is listed.** There are no "remove this" lists. To stop managing something, delete its line and uninstall it once by hand.
- **Idempotent, and dry-run first.** Tasks use modules rather than shell commands wherever possible, and a second run reports no changes. `make check` shows a diff of what would change before every `make apply`.
- **Config is edited in place, not symlinked.** Shell files get marked `blockinfile` regions. Files with a single owner, like the global gitignore and the Zed settings, are copied whole from the owning role.
- **Nothing is tied to one user.** Home directories come from `ansible_facts['user_dir']`, shell files use `$HOME`, and the Homebrew prefix is detected (`/opt/homebrew`, then `/usr/local`).
- **Linted and checked on every commit.** Pre-commit hooks run `ansible-lint` (production profile, strict), scan staged changes for secrets (gitleaks), lint shell scripts (shellcheck), format Markdown (prettier), check YAML and JSON syntax, and fix whitespace, final newlines and line endings. `make test` runs all of it at once.
- **No secrets in the repo.** Tokens and keys live in the macOS Keychain or a password manager, and the gitleaks hook is the backstop.

## Using it

### Requirements

- macOS 15 or newer, on Apple silicon or Intel
- Xcode command line tools, Homebrew, Ansible (ansible-core 2.21+) and `ansible-lint`

`scripts/bootstrap.sh` installs all of these, plus the pinned Galaxy collections.

### Fresh machine

```sh
git clone https://github.com/nmarus/nmarus-laptop-mac.git
cd nmarus-laptop-mac

./scripts/bootstrap.sh   # Xcode CLT, Homebrew, Ansible, Galaxy collections
make check               # dry run: shows what would change
make apply               # apply it
pre-commit install       # enable the commit hooks (once per clone)
```

The ansible-lint, gitleaks, shellcheck and prettier hooks use the binaries the playbook installs from Homebrew, so enable the hooks after the first `make apply`. The other hooks come from upstream `pre-commit-hooks` and download on first run. `make test` runs every hook against the whole tree.

### Everyday use

| Command | What it does |
| --- | --- |
| `make check` | Dry run with diffs; changes nothing |
| `make apply` | Apply the configuration |
| `make apply-sudo` | Apply, prompting for the sudo password (needed for system-wide preferences) |
| `make update` | Run `brew update`, then upgrade everything from Homebrew and the App Store |
| `make lint` | Run `ansible-lint` (production profile) |
| `make test` | Run every pre-commit hook, `ansible-lint` included, against the whole tree |
| `make install` | Reinstall the pinned Galaxy collections |
| `make facts` | Show the facts Ansible gathers about this machine |

`TAGS` limits a run to part of the playbook, and `EXTRA` passes any other arguments through:

```sh
make check TAGS=homebrew
make apply TAGS=macos
make apply EXTRA="-e homebrew_update=true"
```

| Tag | Covers |
| --- | --- |
| `homebrew` | Taps, tap trust, formulae, casks, and the Homebrew shellenv block in `.zprofile` |
| `mas` | Mac App Store apps |
| `packages` | `homebrew` + `mas` |
| `ohmyzsh` / `shell` | oh-my-zsh install, theme and plugins |
| `git` | Global git config and the global gitignore |
| `zed` | Zed editor settings |
| `node` | Node versions via nvm, global npm packages, the nvm loader block |
| `python` | CLI tools installed with `uv tool install` |
| `ruby` | Gems installed with Homebrew's Ruby |
| `languages` | `node` + `python` + `ruby` |
| `macos` / `defaults` | macOS preferences |

The `preflight` checks (macOS version, Xcode CLT, Homebrew) always run.

## Layout

```
ansible.cfg              Local-only defaults: inventory, roles path, local transport
site.yml                 The playbook: the local-only guard, then the roles and their tags
inventory/hosts.yml      Exactly one host: localhost, connection=local
group_vars/all/          The machine description
roles/
  preflight/             macOS, Ansible, Xcode CLT and Homebrew checks; detects the Homebrew prefix
  homebrew/              Taps, trust, formulae, casks, shellenv block
  mas/                   Mac App Store apps via the mas CLI
  ohmyzsh/               Runs the oh-my-zsh installer, sets theme and plugins
  git/                   `git config --global` entries and the global gitignore
  zed/                   Zed editor settings
  node/                  Node versions, default alias, global npm packages, nvm loader
  python/                `uv tool install`
  ruby/                  `gem install --user-install` into ~/.local/bin
  macos/                 `defaults write` via osx_defaults; restarts affected apps
requirements.yml         Pinned Galaxy collections
scripts/bootstrap.sh     Prerequisites for a fresh machine
scripts/askpass          sudo password dialog for casks that ship a .pkg
```

## Adding things

**CLI tool:** add it to `homebrew_formulae` in `group_vars/all/homebrew.yml`. **GUI app:** add it to `homebrew_casks`. An app already installed by hand is taken over in place (`--adopt`) rather than downloaded again.

**Third-party taps:** Homebrew only loads entries from a non-official tap that are explicitly trusted. The tap goes in `homebrew_taps` and the fully qualified name in `homebrew_trust`:

```yaml
homebrew_taps:
  - terraform-linters/tap
homebrew_trust:
  casks:
    - terraform-linters/tap/tflint
homebrew_casks:
  - terraform-linters/tap/tflint
```

`homebrew_trust` also accepts `formulae`, `commands` and `taps`. Trusting a whole tap covers every entry in it, now and in future, so trusting individual entries is preferred.

**CLIs only published to a language's package registry:** use the matching list. Each installs for the current user only, without sudo:

```yaml
# group_vars/all/python.yml: `uv tool install`
python_uv_tools:
  - crawl4ai
# group_vars/all/ruby.yml: gems for Homebrew's Ruby, executables in ~/.local/bin
ruby_gems:
  - brakeman
# group_vars/all/node.yml: `npm install -g` into nvm's default Node
node_global_packages:
  - "@larksuite/cli"
```

**App Store app:** find the id with `mas search <app>`:

```yaml
mas_apps:
  - name: Xcode
    id: 497799835
```

**macOS preference:** find the domain and key (`defaults read com.apple.dock`, or compare `defaults read` output from before and after changing the setting in System Settings), and check the type with `defaults read-type`:

```yaml
macos_defaults:
  - domain: com.apple.dock
    key: autohide
    type: bool
    value: true

macos_defaults_restart_apps:
  - Dock
```

An entry whose domain is system-wide gets `sudo: true` and is applied with `make apply-sudo`.

Then `make check` with the matching tag, and `make apply` if the diff looks right.

## Shell and app config

- **`.zprofile`**: the `homebrew` role adds a marked block that runs `brew shellenv` for login shells.
- **`.zshrc`**: written by oh-my-zsh's official installer. The `ohmyzsh` role then edits the `ZSH_THEME` and `plugins` values in it (tools like `direnv`, `fzf` and `zoxide` are hooked in as oh-my-zsh plugins) and adds a zsh-completions block. The `node` role adds the nvm loader block.
- **Files copied whole**: `~/.config/git/ignore` and `~/.config/zed/settings.json`.
- **`.zshenv`** is not managed.

Each role uses its own block marker (`# BEGIN ANSIBLE MANAGED BLOCK - <name>`), so the blocks never overwrite each other.

> **Zed:** changing a setting in Zed's UI rewrites `settings.json`. `make check` shows that as a diff, and `make apply` puts the repo's version back. To keep a change, copy it into `roles/zed/files/settings.json`.

## Manual steps

These can't be automated cleanly, so they are done by hand once:

1. **Xcode command line tools**: `xcode-select --install` (bootstrap prompts for this).
2. **App Store sign-in**: required before any `mas_apps` entry will install.
3. **App Management permission for the terminal** (System Settings → Privacy & Security → App Management). Without it, adopting an existing app as a cask fails with `Operation not permitted`, even under sudo. Restart the terminal after granting it.
4. **`gh auth login`**, and any other per-tool sign-ins.
5. **Privacy prompts** (Full Disk Access, Screen Recording and similar): granted when macOS asks. They are deliberately not scripted.

## Out of scope

- Software installed and updated outside Homebrew, such as Docker Desktop.
- Account passwords, the login keychain, `sudoers` entries, and admin group membership.
- Remote hosts of any kind.

The roles are generic. Everything specific to this machine is in `group_vars/all/`, if you want to borrow the pattern.

## MIT License

Copyright (c) 2026 Nicholas Marus <nmarus@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
