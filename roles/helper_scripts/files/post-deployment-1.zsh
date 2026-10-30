#!/usr/bin/env zsh

if [[ ${ZSH_EVAL_CONTEXT:-} != *:file || ! -o interactive ]]; then
	print -u2 "Run this in your current interactive zsh session: source /opt/scripts/post-deployment-1.zsh"
	return 1 2>/dev/null || exit 1
fi

() {
	local previous_history_file="${HISTFILE:-}"
	fc -p
	HISTSIZE=0
	SAVEHIST=0

	(
		set -euo pipefail

		# Cleanup
		## Device IDs
		sudo rm -f /etc/machine-id
		sudo rm -f /var/lib/dbus/machine-id
		sudo systemd-machine-id-setup

		## Seeds
		sudo rm /var/lib/systemd/random-seed

		## Logs and history
		sudo rm -rf /var/log/*
		sudo journalctl --rotate
		sudo journalctl --vacuum-time=1s
		rm -f ~/.zsh_history ~/.bash_history
		if [[ -n "$previous_history_file" ]]; then
			rm -f -- "$previous_history_file"
		fi

		## Keys
		sudo rm -f /etc/ssh/ssh_host_*
		sudo dpkg-reconfigure openssh-server

		echo "Cleanup done! Next step is to reboot. Afterwards please run next script."
		read "REPLY?Press Enter to continue..."

		reboot
	)
}
