# Kali Ansible Playbook

Ansible playbook that provisions and configures a Kali Linux machine for penetration testing. Installs tools, applies hardened configs, and deploys helper scripts.

## Usage

### 1. Set up license keys

```bash
cp vars/licenses.yml.sample vars/licenses.yml
# Fill in your license keys
ansible-vault encrypt vars/licenses.yml
```

### 2. Configure variables

Edit `vars/vars.yml` to set the target username (default: `kali`).

### 3. Run the playbook

Run as intended:
```bash
ansible-playbook everything.yml -i "10.20.30.40," -u kali --ask-pass --ask-become-pass --ask-vault-pass --skip-tags=offline
```

Remove `--skip-tags` to add all roles.

You can of course also omit other roles:
```bash
ansible-playbook everything.yml -i "10.20.30.40," -u kali --ask-pass --ask-become-pass --ask-vault-pass --skip-tags=offline,downloads,repos
```

If you're running the playbook on the to-be-provisioned machine itself, then reference localhost as so:
```bash
ansible-playbook everything.yml -i "localhost," --connection=local -K
```

## Manual Steps (post-playbook)

These steps require a running desktop session and cannot be fully automated.

### Burp Suite Pro and Firefox

1. Launch Burp and activate the license manually (key is saved to `/opt/burpsuitepro/license_key.txt`).
2. In Firefox, open FoxyProxy settings and import `/opt/firefox-config/foxy_proxy_export.json`.
3. Run `/opt/scripts/burp-ca-to-firefox.zsh` to install the Burp CA certificate into all Firefox profiles (Burp must be running).

### Nessus Pro

```bash
/opt/scripts/nessus-install.zsh
```

Installs the downloaded package. For activation go to https://localhost:8834 and use the key in `/opt/nessus/license_key.txt`.

### Python dependencies for cloned repos

```bash
/opt/scripts/install_requirements_venvs.zsh
```

Creates a `.venv` and installs `requirements.txt` for each repo in `/opt/github-repos/` that has one.

### Post-deployment hardening

Run these on freshly cloned VMs to reset machine identity:

1. `/opt/scripts/post-deployment-1.zsh` - resets keys, IDs, history etc
2. `/opt/scripts/post-deployment-2.zsh` - after rebooting sets new keys and passwords

## Roles

| Role | Description |
|---|---|
| `system_update` | Runs apt update/upgrade/dist-upgrade. |
| `locale` | Sets locale to Swedish: en_GB.UTF-8, Europe/Stockholm. |
| `sublime` | Installs Sublime Text + Merge. |
| `packages` | Installs Kali tools, VM guest agents, and dependencies. |
| `firefox` | Configures Firefox with FoxyProxy and Burp profiles. |
| `burpsuite` | Installs Burp Suite Pro and saves license key. |
| `helper_scripts` | Deploys utility scripts to `/opt/scripts/`. |
| `nessus_pro` | Downloads Nessus Pro `.deb` to `/opt/nessus/` and saves license key. |
| `panel` | Adds Settings Manager and Sublime Text shortcuts to XFCE panel. |
| `github_repos` | Shallow-clones GitHub repos to `/opt/github-repos/` (tag: `repos`). |
| `downloads` | Downloads configured files to `/opt/downloads/` (tag: `downloads`). |
| `screensaver_disable` | Disables XFCE screensaver and screen lock. |
| `shared_folders` | Mounts QEMU or VMware shared folders. |
| `offline` | Installs Kali everything meta-package for air-gapped systems (tag: `offline`). |

## Notes

- All roles run as root (`become: true`). File ownership is set to `the_user` where appropriate.
- License keys are stored in `vars/licenses.yml`, which should be encrypted with `ansible-vault`.
- The playbook prints a reboot warning at the end if system updates require one.
- Helper scripts have not been tested on other systems (e.g in other LUKS-setups etc)
