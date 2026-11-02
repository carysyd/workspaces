# Lima Home Lab

Creates an ARM64 Ubuntu Server VM on Apple Silicon. Installs Homebrew and dependencies if needed.

```bash
bash lima-home-lab.sh --hostname cary-home-lab-m2-max --ip 192.168.1.50
```

- Edit defaults at the top of the script, including gateway, DNS, and subnet prefix.
- Prefers connected Ethernet. Use `--interface en7` to select an adapter.
- Allocates all CPU cores, RAM minus 8 GiB, and sparse disk capacity equal to free space minus 200 GiB.
- SSH: `ssh ubuntu@192.168.1.50`, using a private key matching `carysyd`'s GitHub keys.
- Starts at Mac boot; FileVault may require disk unlock first.
- Creates a new VM only. Run as your normal Mac user; `sudo` is requested when needed.

```bash
export LIMA_HOME="$HOME/.lima-cary-home-lab-m2-max"
limactl list
limactl stop cary-home-lab-m2-max
limactl start cary-home-lab-m2-max
```
