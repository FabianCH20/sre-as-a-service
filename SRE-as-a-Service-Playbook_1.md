---
title: SRE as a Service Playbook
tags: [SRE, playbook, infrastructure, hardening, k3s, podman, observability, automation, security]
proyecto: "[[00-MOC-SRE-HOME-LAB]]"
incidentes: "[[INC-00-SRE-AS-A-SERVICE]]"
fecha: 2026-09-07
estado: activo
---

# Playbook: SRE as a Service — From Homelab to a Real Service

**Base:** Rocky Linux / AlmaLinux 9 (simulating RHEL, headless server, "minimal install")
**Reference project:** `FabianCH20/sre-homelab-portfolio`
**Goal:** Turn the homelab (Podman + k3s + Ansible + monitoring) into a stack that *simulates* an SRE-as-a-Service offering: infrastructure, security, CI/CD and support.

⚠️ **Testing/lab environment.** This playbook simulates what an SRE-as-a-Service setup would look like — it is not a production service offered to real clients. Its purpose is skill-building and hands-on practice.

---

## 🏗️ General Project Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Free-tier cloud (Oracle / GCP / Azure)                  │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Rocky Linux / AlmaLinux 9 (headless, RHEL-like)  │    │
│  │  ├── Hardening: SSH, sudo, firewalld, SELinux     │    │
│  │  ├── Podman (rootless, daemonless)                │    │
│  │  │    └── k3s (server, single-node)               │    │
│  │  │         ├── Workloads (client apps)            │    │
│  │  │         ├── Prometheus + Grafana + Loki        │    │
│  │  │         └── ArgoCD (GitOps)                    │    │
│  │  └── Ansible (provisions everything above)        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
        ▲
        │ CI/CD (GitHub Actions / GitLab CI) pushes config
        │ Auditing: CIS Benchmarks, OpenSCAP, Lynis, kube-bench
        │
   Your repo: sre-homelab-portfolio (GitHub)
```

---

## 🛡️ PHASE 0 — Base Server: Rocky Linux / AlmaLinux

### 0.1 Minimal Installation (Headless)
**Goal:** Install the base OS simulating a real RHEL server.
- **Action**: minimal ISO $\rightarrow$ "Minimal Install (Basic functionality)".
- **Commands**:
  ```bash
  wget https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-minimal.iso
  sha256sum -c CHECKSUM --ignore-missing
  ```

### 0.2 SSH Hardening
**Goal:** Allow remote root login, but remove password authentication.
- **Decision**: `PermitRootLogin prohibit-password` (root only with a key).
- **Action**:
  ```bash
  ssh-keygen -t ed25519
  ssh-copy-id root@server
  ```
- **`/etc/ssh/sshd_config` config**:
  ```
  PermitRootLogin prohibit-password
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  ```
- **Verification**: `systemctl restart sshd` $\rightarrow$ Connect via MobaXterm with the key (should work) $\rightarrow$ Try with password (should fail).
**🚨 Access Recovery (Troubleshooting):**
If you lose remote access ("Connection refused" or "Network connection not found"):
1. Access via VM Console $\rightarrow$ `nano /etc/ssh/sshd_config`.
2. Temporarily enable: `PermitRootLogin yes` and `PasswordAuthentication yes`.
3. Restart the service: `systemctl restart sshd`.
4. Check the firewall: `firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload`.
5. Once access is restored, push the key with `ssh-copy-id` and disable passwords again.

- **Compensating Controls**:
  - Restrict port 22 by IP via `firewalld`.
  - Install `fail2ban`: `dnf install epel-release && dnf install fail2ban && systemctl enable --now fail2ban`.

### 0.3 Sudo & Administration
**Goal:** Administrative management without using root directly, following SRE best practices.

**1. Administrative Group Assignment**:
Add the user to the `wheel` group to enable basic sudo capabilities:
```bash
usermod --append -G wheel <user>
```

**2. Modular Permission Configuration (Sudoers.d)**:
To avoid corrupting the master `/etc/sudoers` file and to make automation with Ansible easier, independent files are created under `/etc/sudoers.d/`.

- **Action**: Create a user-specific file using `nano`:
  ```bash
  sudo nano /etc/sudoers.d/<user>
  ```
- **Content**: Add the following rule to allow passwordless command execution (ideal for CI/CD pipelines):
  ```text
  <user> ALL=(ALL) NOPASSWD:ALL
  ```
- **Critical Security Note**: Sudo ignores files with incorrect permissions. You must set the `0440` permission:
  ```bash
  sudo chmod 0440 /etc/sudoers.d/<user>
  ```

**3. Security Validation**:
Validate there are no syntax errors that could lock out administrative access:
```bash
sudo visudo
```

**4. Access Test**:
Verify the switch to root without a password prompt:
```bash
sudo -i
```

### 0.4 Automatic Updates (`dnf-automatic`)
**Goal:** Automatic security patching.
- **Action**:
  ```bash
  sudo dnf install dnf-automatic
  sudo systemctl edit dnf-automatic.timer # Set OnCalendar=*-*-* 6:00
  sudo systemctl enable --now dnf-automatic.timer
  ```

### 0.5 firewalld (Zones and Rules)
**Goal:** Control inbound/outbound traffic.
- **Action**:
  ```bash
  firewall-cmd --zone=public --add-service=http
  firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="ssh" accept'
  firewall-cmd --runtime-to-permanent
  firewall-cmd --reload
  ```

### 0.6 SELinux (Enforcing)
**Goal:** Mandatory Access Control (MAC).
- **Diagnostics**:
  ```bash
  getenforce
  ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts recent
  sealert -l "*"
  restorecon -R -v /path
  ```
- **Remediation**: `audit2allow -a > module.te && semodule -i module.pp`.

---

## 📦 PHASE 1 — Containers: Podman

### 1.1 Enterprise Installation
**Goal:** Daemonless rootless engine.
- **Action**:
  ```bash
  sudo dnf -y install podman
  sudo dnf -y install epel-release podman-compose
  ```
  🚨 **Related Incident**: [[incidentes/INC-00-SRE-AS-A-SERVICE#INC-02|INC-02: EPEL/podman-compose dependency error]]

### 1.2 Rootless Architecture & Namespaces
**Goal:** Understand process isolation and identity mapping without root privileges.

#### 1. UID Mapping Concept (The "Identity Lie")
Podman uses **User Namespaces** so a process inside the container believes it is `root` (UID 0), while for the Linux kernel it remains a standard user (e.g. UID 1000).

- **Range Configuration**: Available UIDs are defined in `/etc/subuid` and `/etc/subgid`.
  - Example: `krikox:100000:65536` $\rightarrow$ The user can map their processes to the host's 100,000 - 165,535 range.
- **Isolation**: If the container is compromised, the attacker only gets the standard user's permissions on the host, removing the risk of full privilege escalation.

#### 2. Identity Diagnostics and Verification
| Command | What it checks | Expected result |
| :--- | :--- | :--- |
| `podman unshare id` | Identity inside the namespace | `uid=0(root)` (even though you're a standard user) |
| `podman top <container> huser` | Host vs. Container comparison | Host: `1000` $\rightarrow$ Container: `0` |
| `lsns -t mnt` | Existence of namespaces | List of active mount namespaces |
| `cat /etc/subuid` | Assigned UID quotas | Range of allowed secondary IDs |

#### 3. Hands-on Test: Deploying a Rootless Web Server
To validate the architecture, we deploy an Nginx server and inspect its identity.

**A. Launch the container:**
```bash
podman run -d --name poc-web -p 8080:80 nginx
```

**B. Validate the identity mapping (the key test):**
```bash
podman top poc-web huser
```
*You'll observe that the process the container sees as `root` is actually your user on the host.*

**C. Verify functionality:**
```bash
curl localhost:8080
```

**D. Cleanup:**
```bash
podman stop poc-web && podman rm poc-web
```

**Technical References:**
- [Podman Rootless Documentation](https://docs.podman.io/en/latest/Rootless/)
- [Linux User Namespaces Guide](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Red Hat: Rootless Containers](https://www.redhat.com/en/blog/rootless-containers-podman)


### 1.3 Resource Limits
**Goal:** Restrict CPU and memory usage to avoid "noisy neighbor" issues between containers and guarantee host stability.

- **Action**:
  - **Alpine example (lightweight/quick test):**
   podman run -d \ --name test-alpine \ -m 512m \ --cpus=1.5 \ --memory-swap=512m \ alpine \ sleep 1000
  - **Nginx example (real service):**
    ```bash
    podman run -d --name test-nginx -m 512m --cpus=1.5 --memory-swap=0 nginx
    ```

- **Metrics Validation (crucial for SRE):**
  To confirm limits are being applied correctly in real time:
  ```bash
  podman stats test-alpine test-nginx
  ```

### 1.4 Pods (Bridge to Kubernetes)
- **Action**:
  ```bash
  podman pod create --name mypod
  podman create --pod mypod nginx
  podman create --pod mypod redis
  podman pod start mypod
  ```

## Proper Quadlet Installation (Podman + systemd)

### 1. Prerequisites

bash

```bash
podman --version          # must be >= 4.6
dnf module list container-tools   # RHEL/Rocky/Alma — confirm active stream
```

- Failure symptom: the generator doesn't recognize new keys, or the `/usr/lib/systemd/system-generators/podman-system-generator` binary is missing.
- Fix: `sudo dnf module switch-to container-tools:4.6 && sudo dnf update podman`
- Ref: [RHEL 8 – Note: "Quadlet is available beginning with Podman v4.6"](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers#auto-generating-a-systemd-unit-file-using-quadlets_assembly_porting-containers-to-systemd-using-podman)

### 2. Choosing the correct path (root vs rootless)

|Mode|Path|Use|
|---|---|---|
|Root|`/etc/containers/systemd/`|system admin|
|Root|`/usr/share/containers/systemd/`|package/distro quadlets (NOT for a regular user)|
|Rootless|`$HOME/.config/containers/systemd/` or `$XDG_CONFIG_HOME/containers/systemd/`|your own user|
|Rootless|`/etc/containers/systemd/users/$UID`|admin defines quadlets for a specific user|

⚠️ Lesson from a previous incident: `/usr/share/containers/systemd/` **is not scanned** by `systemctl --user`. If you're a regular (rootless) user, the path is always `$HOME/.config/containers/systemd/`.

- Ref: [podman-systemd.unit(5) — "Podman Quadlet Unit Search Path"](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

### 3. Create the directory (doesn't exist by default)

bash

```bash
mkdir -p $HOME/.config/containers/systemd/
```

- Symptom if skipped: `No such file or directory` when trying to create the `.container` file.
- Ref: [Red Hat Blog — Deploying a multi-container application using Podman and Quadlet (explicit `mkdir -p` step)](https://www.redhat.com/en/blog/multi-container-application-podman-quadlet)

### 4. Create the `.container` file

bash

```bash
cat > $HOME/.config/containers/systemd/mysleep.container <<'EOF'
[Unit]
Description=The sleep container
After=local-fs.target

[Container]
Image=registry.access.redhat.com/ubi8-minimal:latest
Exec=sleep 1000

[Install]
WantedBy=multi-user.target default.target
EOF
```

- Required fields under `[Container]`: `Image` and (optional) `Exec`.
- Ref: [RHEL 8 – Auto-generating a systemd unit file using Quadlets (`mysleep.container` example)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers#auto-generating-a-systemd-unit-file-using-quadlets_assembly_porting-containers-to-systemd-using-podman)

### 5. Validate BEFORE daemon-reload (the step that prevents the earlier incident)

bash

```bash
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun
```

- Correct symptom: prints the full contents of the generated `mysleep.service`.
- Error symptom: `No files parsed from [...]` → the file is in a path that isn't scanned (go back to step 2).
- Ref: [podman-systemd.unit(5) — "Debugging Quadlet files" section](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

### 6. Generate the service

bash

```bash
systemctl --user daemon-reload
```

### 7. Verify the actual generation (not just the reload)

bash

```bash
ls /run/user/$(id -u)/systemd/generator/ | grep mysleep
systemctl --user list-unit-files | grep mysleep
```

- The real `.service` lives in `/run/user/<UID>/systemd/generator/`, not next to the `.container` file.

### 8. Start and enable

bash

```bash
systemctl --user start mysleep.service
systemctl --user enable mysleep.service   # if you're not using WantedBy in the .container file
```

### 9. Final verification

bash

```bash
systemctl --user status mysleep.service
podman ps -a   # should show up as systemd-mysleep
```

- Ref: [podman-quadlet-basic-usage(7)](https://docs.podman.io/en/latest/markdown/podman-quadlet-basic-usage.7.html)

### 10. (Optional, persistent rootless after logout)

bash

```bash
loginctl enable-linger $USER
```

Without this, the `--user` service stops when you close the SSH session.

- Ref: [RHEL 9 – Porting containers to systemd using Podman](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers)
### 1.6 Migration to Kubernetes
**Goal**: Generate real YAML from Podman.
- **Action**:
  ```bash
  podman kube generate mypod > mypod.yaml
  podman kube play mypod.yaml
  ```

---

## ☸️ PHASE 2 — Orchestration: k3s (Multi-Node Cluster)

**Official references:**
- [docs.k3s.io](https://docs.k3s.io/) — official k3s documentation
- [kubernetes.io/docs/setup/production-environment/](https://kubernetes.io/docs/setup/production-environment/) — K8s production environment guide
- [github.com/k3s-io/k3s](https://github.com/k3s-io/k3s) — official k3s repository

### 2.1 — Control Plane Installation (Master Node)

The Control Plane is the cluster's brain; it manages state, the scheduler and the API.

**📍 Where to run it:** On the main server (e.g. `SRE-Master-01`).

**1. Run the installation script**
```bash
curl -sfL https://get.k3s.io | sh -
```
→ This command installs k3s, sets up the kubeconfig at `/etc/rancher/k3s/k3s.yaml` and starts the required services.

**2. Retrieve the cluster TOKEN**
For Workers to join the cluster, they need a unique security token generated by the Master.
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```
→ **Copy this value**. Example token: `K10:abc123def456ghi789jklmnop...`

**3. Verify the server is running**
```bash
sudo kubectl get nodes
```
→ Should show the `SRE-Master-01` node with status `Ready` and role `control-plane,master`.

---

### 2.2 — Worker Node (Agent) Installation

Worker Nodes are responsible for running the containers (Pods) and the actual workloads.

**📍 Where to run it:** On each secondary server you want to add to the cluster (e.g. `SRE-Worker-01`, `SRE-Worker-02`).

**1. Run the cluster-join script**
Replace `<MASTER_IP>` with the real IP of the Control Plane and `<TOKEN>` with the value from the previous step.
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<MASTER_IP>:6443 K3S_TOKEN=<TOKEN> sh -
```
**Real example:**
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.100.42:6443 K3S_TOKEN=K10:abc123def456ghi789jklmnop sh -
```
→ `K3S_URL`: Tells the agent where the cluster API is (port 6443 by default).
→ `K3S_TOKEN`: Authenticates the node so the Master accepts it as part of the cluster.

**2. Verify the join from the Control Plane**
Go back to the Master server and run:
```bash
sudo kubectl get nodes -o wide
```
→ **Expected result**: You should now see all nodes listed.
- `SRE-Master-01` $\rightarrow$ `control-plane,master`
- `SRE-Worker-01` $\rightarrow$ `<none>` (this indicates it's a pure Worker).

---

### 2.3 — Cluster Operation and Health

**Common administration actions:**
```bash
# View overall node status and their IPs
kubectl get nodes -o wide

# View real-time resource consumption (requires metrics-server, included in k3s)
kubectl top node

# View recent cluster events to diagnose failures
kubectl get events -A --sort-by='.lastTimestamp'
```

**Kubeconfig Setup (Remote Access):**
If you want to manage the cluster from your PC (via MobaXterm/VSCode) without logging into the server:
1. Copy the contents of `/etc/rancher/k3s/k3s.yaml` from the Master.
2. Save it on your PC at `~/.kube/config`.
3. Change `server: https://127.0.0.1:6443` to `server: https://<MASTER_IP>:6443`.
---

## ⚙️ PHASE 3 — Automation: Ansible

### 3.1 Control Setup and Infrastructure
**Goal:** Prepare the control environment to manage infrastructure without manual intervention.

1. **Create the file structure**:
   ```bash
   mkdir -p /opt/ansible
   cd /opt/ansible
   ```

2. **Install Ansible**:
   ```bash
   pip install ansible
   ```

3. **Inventory Configuration (`inventory.ini`)**:
   Defines which servers you're going to manage.
   ```ini
   # inventory.ini
   [web]
   srv-prod-01 ansible_connection=local

   [web:vars]
   ansible_python_interpreter=/usr/bin/python3
   ```
   → `ansible_connection=local` means the control node and the managed node are the same server.

4. **Connectivity Test**:
   ```bash
   ansible web -i inventory.ini -m ping
   ```

### 3.2 Deployment Playbook (`playbook.yml`)
**Goal:** Declaratively define the desired state of the server.

```yaml
# playbook.yml
- hosts: web
  become: true
  tasks:
    - name: Update all system packages (RHEL family)
      dnf:
        name: "*"
        state: latest

    - name: Install the Podman container engine
      dnf:
        name: podman
        state: present

    - name: Install podman-compose for multi-container stacks
      dnf:
        name: podman-compose
        state: present

    - name: Create application directory
      file:
        path: /opt/app
        state: directory
        mode: "0755"

    - name: Deploy app configuration from template
      template:
        src: templates/app.env.j2
        dest: /opt/app/.env
        mode: "0600"
      notify: restart app

  handlers:
    - name: restart app
      containers.podman.podman_container:
        name: myapp
        image: nginx:latest
        state: started
        restart_policy: always
```

### 3.3 Execution and Validation
To run the playbook safely and with the correct privileges:

- **Dry-Run Mode (Simulation)**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check
  ```
- **Real Execution with Privileges**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
  ```
  → `--ask-become-pass` requests the `sudo` password needed for `become: true` tasks.

### 3.4 Key Modules for the RHEL/Podman Family
- **`ansible.builtin.dnf`**: Package management (Rocky/AlmaLinux).
- **`ansible.builtin.systemd`**: Service and timer control.
- **`ansible.posix.firewalld`**: Firewall rule configuration.
- **`containers.podman.podman_container`**: Lifecycle management for rootless containers.

### 📦 Guide: Installing and Using the `containers.podman` Collection

For the Podman module to work, the collection must be installed on the **Control Machine** (where Ansible runs).

**1. Installation**
```bash
ansible-galaxy collection install containers.podman
```

**2. Verification**
```bash
ansible-galaxy collection list | grep podman
```

**3. Professional Usage (FQCN)**
It's recommended to use the fully-qualified module name to avoid ambiguity:
`containers.podman.podman_container` instead of just `podman_container`.

**4. Flow Requirements**
- **Control**: `ansible-galaxy collection install containers.podman`
- **Node**: `dnf install podman` (managed by the playbook).




---

## ☁️ PHASE 4 — Cloud Deployment (Always Free)

| Provider | Free compute | Duration | Key limitation |
|---|---|---|---|
| **Oracle Cloud** | 2 OCPU / 12 GB ARM (Ampere A1) | **Perpetual** | 10 TB egress/month |
| **GCP** | 1 e2-micro instance | **Perpetual** | Only 1 GB egress/month outside GCP |
| **AWS** | $100-200 credit | **6 months** | No perpetual free EC2 for new accounts |
| **Azure** | B1s/B2pts/B2ats VM | **12 months** | Not free forever |

**Recommendation**: Oracle Cloud (Ampere A1) as the primary host.

---

## 🚀 PHASE 5 — CI/CD and GitOps

### 5.1 Pipelines
- **GitHub Actions**: `.github/workflows/demo.yml` $\rightarrow$ `actions/checkout@v6` $\rightarrow$ `run: ls`.
- **GitLab CI**: `.gitlab-ci.yml` $\rightarrow$ Stages: `build`, `test`, `deploy-prod`.

### 5.2 ArgoCD (GitOps)
**Goal**: Automatic Git $\rightarrow$ k3s sync.
- **Installation**:
  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  ```
- **Operation**: `argocd app create <name> --repo <url> --path <path> --dest-server <url> --dest-namespace <ns>`.

---

## 🔍 PHASE 6 — Security and Auditing

### 6.1 CIS & OpenSCAP Compliance
- **OpenSCAP**:
  ```bash
  dnf install scap-security-guide openscap-scanner openscap-utils
  oscap xccdf eval --report scan-report.html --profile xccdf_org.ssgproject.content_profile_cis /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
  ```

### 6.2 General Audits
- **Lynis**: `git clone https://github.com/CISOfy/lynis /usr/local/lynis && ./lynis audit system`.
- **Podman Security**: `bash podman-security-bench.sh`.
- **Kubernetes (k3s)**: `kube-bench` (via Job YAML).

---

## 📈 PHASE 7 — Automated Monitoring (Prometheus + Grafana + Zabbix)

**Official references:**
- [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) — official Prometheus documentation
- [grafana.com/docs](https://grafana.com/docs/) — official Grafana documentation
- [zabbix.com/documentation](https://www.zabbix.com/documentation/current/) — official Zabbix documentation
- [github.com/prometheus/prometheus](https://github.com/prometheus/prometheus) · [github.com/prometheus/node_exporter](https://github.com/prometheus/node_exporter) · [github.com/grafana/grafana](https://github.com/grafana/grafana) · [github.com/zabbix/zabbix](https://github.com/zabbix/zabbix)
- [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/) — community dashboard repository (includes dashboard 1860 used in this phase)

```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
```
→ System user with no login or home directory, for security (services shouldn't run as interactive users).

### 7.1 — Prometheus + Grafana + Node Exporter, step by step

**1. Resolve the latest version and download it**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Detected version: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ The version is resolved dynamically by querying the GitHub API (`tag_name` of the latest release) instead of hardcoding a version number in the URL — a fixed number combined with `/latest/download/` will eventually go stale.

**2. Verify you downloaded a real file, not an error page, BEFORE extracting**

```bash
file node_exporter-*.tar.gz
```
→ Should say `gzip compressed data`. If it says `HTML document`, delete it and repeat step 1.

**3. Extract the file**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirm the binary exists inside the extracted folder BEFORE moving it**

```bash
ls -la ~ | grep node_exporter
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```

**5. Move the binary to `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```

**6. Verify the binary was installed and responds**

```bash
node_exporter --version
```

**7. Cleanup**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Create the service definition file:**
```bash
sudo nano /etc/systemd/system/node_exporter.service
```

```ini
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter --now
```

**Create a folder for the monitoring stack:**
```bash
mkdir -p /opt/monitoring
cd /opt/monitoring
nano docker-compose.monitoring.yml
```

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus
    volumes: ["./prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana
    ports: ["3000:3000"]
    volumes: ["grafana-data:/var/lib/grafana"]
volumes:
  grafana-data:
```

**Create the Prometheus configuration file:**
```bash
nano prometheus.yml
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<SERVER_IP>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<SERVER_IP>:10250"]
```

```bash
podman-compose -f docker-compose.monitoring.yml up -d
```
→ `podman-compose` is used to keep the rootless, daemonless architecture defined across the rest of the SRE-as-a-Service project.

### 7.2 — Bringing up the stack and accessing it via browser, step by step

**1. Verify both containers are up and running**

```bash
podman-compose -f docker-compose.monitoring.yml ps
```

**2. Confirm the ports are exposed correctly**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```

**3. Access Prometheus from the browser**
`http://<SERVER_IP>:9090`
Check targets at: `http://<SERVER_IP>:9090/targets`

**4. Access Grafana from the browser**
`http://<SERVER_IP>:3000` (Admin / admin)

**5. Connect Grafana to Prometheus as a data source**
`Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Prometheus`
URL: `http://prometheus:9090`

**6. Import the industry-standard dashboard**
`Dashboards` $\rightarrow$ `New` $\rightarrow$ `Import` $\rightarrow$ ID: `1860` (Node Exporter Full).

### 7.3 — Zabbix: Enterprise Monitoring, step by step

**1. Install the Zabbix Agent on the Host**
The agent natively collects hardware and OS data.

```bash
# Official Zabbix repository for Rocky Linux 9
sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
sudo dnf clean all
sudo dnf install zabbix-agent -y
```

**2. Configure the agent**
```bash
sudo nano /etc/zabbix_agentd.conf
```
Edit:
```ini
Server=<SERVER_IP>
ServerActive=<SERVER_IP>
Hostname=SRE-Server-01
```

**3. Enable and open the port**
```bash
sudo systemctl enable zabbix-agent --now
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload
```

**4. Deploy the Zabbix Server Stack via Podman**
```bash
mkdir -p /opt/zabbix
cd /opt/zabbix
nano docker-compose.zabbix.yml
```

```yaml
# docker-compose.zabbix.yml
services:
  zabbix-db:
    image: mysql:8.0
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_bin --default-authentication-plugin=mysql_native_password
    volumes:
      - zbx_db_data:/var/lib/mysql
    env_file:
      - .env_zabbix
  zabbix-server:
    image: zabbix/zabbix-server-mysql:6.4-ubuntu-latest
    ports:
      - "10051:10051"
    volumes:
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env_zabbix
    depends_on:
      - zabbix-db
  zabbix-web:
    image: zabbix/zabbix-web-apache-mysql:6.4-ubuntu-latest
    ports:
      - "8080:8080"
    volumes:
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env_zabbix
    depends_on:
      - zabbix-db
      - zabbix-server
volumes:
  zbx_db_data:
```

**5. Create the `.env_zabbix` environment file**
```ini
DB_SERVER=zabbix-db
MYSQL_DATABASE=zabbix
MYSQL_USER=zabbix
MYSQL_PASSWORD=zabbix_pwd
MYSQL_ROOT_PASSWORD=root_pwd
ZBX_SERVER_HOST=zabbix-server
PHP_TZ=America/New_York
```

**6. Bring it up and verify**
```bash
podman-compose -f docker-compose.zabbix.yml up -d
```
Access: `http://<SERVER_IP>:8080` (Admin / zabbix).
→ Configure the `SRE-Server-01` host under `Configuration` $\rightarrow$ `Hosts` using the `Linux by Zabbix agent` template.

### 7.4 — Unified Integration in Grafana

To achieve a "Single Pane of Glass," we integrate Zabbix into Grafana.

**1. Install the Zabbix Plugin**
```bash
# Find the Grafana container ID
GRAFANA_ID=$(podman ps -qf "name=grafana")
podman exec -it $GRAFANA_ID grafana-cli plugins install alexanderzobnin-zabbix-app
podman restart $GRAFANA_ID
```

**2. Enable and configure**
- `Administration` $\rightarrow$ `Plugins` $\rightarrow$ `Zabbix` $\rightarrow$ **Enable**.
- `Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Zabbix`.
- **URL**: `http://<SERVER_IP>:8080/zabbix/api_jsonrpc.php`.
- **User/Pass**: `Admin` / `zabbix`.

### 7.5 — Basic Alerts and Governance (SRE)

**1. Alert Rules in Prometheus**
Create `/opt/monitoring/alert.rules.yml`:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiskFull
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Less than 15% free disk space on {{ $labels.instance }}"}
```
Reference this file in `prometheus.yml` and mount the volume in `docker-compose.monitoring.yml`.

**2. SRE Governance**
- **SLI**: A quantitative measurement (e.g. API latency).
- **SLO**: A target for an SLI (e.g. 99.9% of requests < 200ms).
- **SLA**: A legal agreement based on the SLO.
- **Error Budget**: The allowed margin of error before halting deployments to stabilize the system.
- **Incidents**: Flow of `Detection` $\rightarrow$ `Mitigation` $\rightarrow$ `Blameless Postmortem`.
 system with no login or home directory, for security (services shouldn't run as interactive users).

### 7.1 — Prometheus + Grafana + Node Exporter, step by step

**1. Resolve the latest version and download it**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Detected version: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ The version is resolved dynamically by querying the GitHub API (`tag_name` of the latest release) instead of hardcoding a version number in the URL — a fixed number combined with `/latest/download/` will eventually go stale.

**2. Verify you downloaded a real file, not an error page, BEFORE extracting**

```bash
file node_exporter-*.tar.gz
```
→ Should say `gzip compressed data`. If it says `HTML document`, delete it and repeat step 1.

**3. Extract the file**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirm the binary exists inside the extracted folder BEFORE moving it**

```bash
ls -la ~ | grep node_exporter
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```

**5. Move the binary to `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```

**6. Verify the binary was installed and responds**

```bash
node_exporter --version
```

**7. Cleanup**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Create the service definition file:**
```bash
sudo nano /etc/systemd/system/node_exporter.service
```

```ini
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter --now
```

**Create a folder for the monitoring stack:**
```bash
mkdir -p /opt/monitoring
cd /opt/monitoring
nano docker-compose.monitoring.yml
```

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus
    volumes: ["./prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana
    ports: ["3000:3000"]
    volumes: ["grafana-data:/var/lib/grafana"]
volumes:
  grafana-data:
```

**Create the Prometheus configuration file:**
```bash
nano prometheus.yml
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<SERVER_IP>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<SERVER_IP>:10250"]
```

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

### 7.2 — Bringing up the stack and accessing it via browser, step by step

**1. Verify both containers are up and running**

```bash
docker compose -f docker-compose.monitoring.yml ps
```

**2. Confirm the ports are exposed correctly**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```

**3. Access Prometheus from the browser**
`http://<SERVER_IP>:9090`
Check targets at: `http://<SERVER_IP>:9090/targets`

**4. Access Grafana from the browser**
`http://<SERVER_IP>:3000` (Admin / admin)

**5. Connect Grafana to Prometheus as a data source**
`Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Prometheus`
URL: `http://prometheus:9090`

**6. Import the industry-standard dashboard**
`Dashboards` $\rightarrow$ `New` $\rightarrow$ `Import` $\rightarrow$ ID: `1860` (Node Exporter Full).

### 7.3 — Zabbix: Enterprise Monitoring, step by step

**1. Install the Zabbix Agent on the Host**
The agent natively collects hardware and OS data.

```bash
# Official Zabbix repository for Rocky Linux 9
sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
sudo dnf clean all
sudo dnf install zabbix-agent -y
```

**2. Configure the agent**
```bash
sudo nano /etc/zabbix_agentd.conf
```
Edit:
```ini
Server=<SERVER_IP>
ServerActive=<SERVER_IP>
Hostname=SRE-Server-01
```

**3. Enable and open the port**
```bash
sudo systemctl enable zabbix-agent --now
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload
```

**4. Deploy the Zabbix Server Stack via Docker**
```bash
mkdir -p /opt/zabbix
cd /opt/zabbix
nano docker-compose.zabbix.yml
```

```yaml
# docker-compose.zabbix.yml
services:
  zabbix-db:
    image: mysql:8.0
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_bin --default-authentication-plugin=mysql_native_password
    volumes:
      - zbx_db_data:/var/lib/mysql
    env_file:
      - .env_zabbix
  zabbix-server:
    image: zabbix/zabbix-server-mysql:6.4-ubuntu-latest
    ports:
      - "10051:10051"
    volumes:
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env_zabbix
    depends_on:
      - zabbix-db
  zabbix-web:
    image: zabbix/zabbix-web-apache-mysql:6.4-ubuntu-latest
    ports:
      - "8080:8080"
    volumes:
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env_zabbix
    depends_on:
      - zabbix-db
      - zabbix-server
volumes:
  zbx_db_data:
```

**5. Create the `.env_zabbix` environment file**
```ini
DB_SERVER=zabbix-db
MYSQL_DATABASE=zabbix
MYSQL_USER=zabbix
MYSQL_PASSWORD=zabbix_pwd
MYSQL_ROOT_PASSWORD=root_pwd
ZBX_SERVER_HOST=zabbix-server
PHP_TZ=America/New_York
```

**6. Bring it up and verify**
```bash
docker compose -f docker-compose.zabbix.yml up -d
```
Access: `http://<SERVER_IP>:8080` (Admin / zabbix).
→ Configure the `SRE-Server-01` host under `Configuration` $\rightarrow$ `Hosts` using the `Linux by Zabbix agent` template.

### 7.4 — Unified Integration in Grafana

To achieve a "Single Pane of Glass," we integrate Zabbix into Grafana.

**1. Install the Zabbix Plugin**
```bash
# Find the Grafana container ID
GRAFANA_ID=$(docker ps -qf "name=grafana")
docker exec -it $GRAFANA_ID grafana-cli plugins install alexanderzobnin-zabbix-app
docker restart $GRAFANA_ID
```

**2. Enable and configure**
- `Administration` $\rightarrow$ `Plugins` $\rightarrow$ `Zabbix` $\rightarrow$ **Enable**.
- `Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Zabbix`.
- **URL**: `http://<SERVER_IP>:8080/zabbix/api_jsonrpc.php`.
- **User/Pass**: `Admin` / `zabbix`.

### 7.5 — Basic Alerts and Governance (SRE)

**1. Alert Rules in Prometheus**
Create `/opt/monitoring/alert.rules.yml`:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiskFull
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Less than 15% free disk space on {{ $labels.instance }}"}
```
Reference this file in `prometheus.yml` and mount the volume in `docker-compose.monitoring.yml`.

**2. SRE Governance**
- **SLI**: A quantitative measurement (e.g. API latency).
- **SLO**: A target for an SLI (e.g. 99.9% of requests < 200ms).
- **SLA**: A legal agreement based on the SLO.
- **Error Budget**: The allowed margin of error before halting deployments to stabilize the system.
- **Incidents**: Flow of `Detection` $\rightarrow$ `Mitigation` $\rightarrow$ `Blameless Postmortem`.

---

## 🗺️ Suggested Roadmap

1. **W1**: Phase 0 (Rocky/Alma Hardening).
2. **W1-2**: Phase 1 (Podman) + Phase 2 (k3s).
3. **W2-3**: Phase 3 (Ansible) $\rightarrow$ Setup reproducibility.
4. **W3**: Phase 4 $\rightarrow$ Migration to Oracle Cloud Always Free.
5. **W4**: Phase 5 $\rightarrow$ CI/CD (GitHub Actions) + ArgoCD.
6. **W4-5**: Phase 6 $\rightarrow$ Audits (Lynis, OpenSCAP, kube-bench).
7. **W5-6**: Phase 7 $\rightarrow$ PLG Stack + SLO Definition + Simulated Postmortem.

---

## 📚 Full Reference Table

| Topic | Reference | URL |
|---|---|---|
| Rocky Installation | Installing Rocky Linux 9 | https://docs.rockylinux.org/9/guides/9_6_installation/ |
| Alma Installation | AlmaLinux Installation Guide | https://wiki.almalinux.org/documentation/installation-guide.html |
| SSH hardening | Securing networks — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/securing_networks/assembly_using-secure-communications-between-two-systems-with-openssh_securing-networks |
| Sudo | Managing sudo access — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/managing-sudo-access_configuring-basic-system-settings |
| dnf-automatic | Patching with dnf-automatic | https://docs.rockylinux.org/10/guides/security/dnf_automatic/ |
| firewalld | firewalld for Beginners | https://docs.rockylinux.org/10/guides/security/firewalld-beginners/ |
| SELinux | Troubleshooting SELinux — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_selinux/troubleshooting-problems-related-to-selinux_using-selinux |
| CIS RHEL/Rocky | CIS Rocky Linux Benchmarks | https://www.cisecurity.org/benchmark/rocky_linux |
| OpenSCAP | Scanning compliance — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/scanning-the-system-for-configuration-compliance-and-vulnerabilities_security-hardening |
| Lynis | Get Started with Lynis | https://cisofy.com/documentation/lynis/get-started/ |
| Podman install | Podman Installation | https://podman.io/docs/installation |
| Podman Rocky | Podman — Rocky Linux Docs | https://docs.rockylinux.org/10/guides/containers/podman_guide/ |
| Podman rootless | Rootless containers using Podman | https://www.redhat.com/en/blog/rootless-containers-podman |
| Podman pods | podman-pod-create | https://docs.podman.io/en/stable/markdown/podman-pod-create.1.html |
| Podman + systemd | podman-systemd.unit (Quadlet) | https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html |
| Podman $\rightarrow$ Kubernetes | podman-kube-play | https://docs.podman.io/en/latest/markdown/podman-kube-play.1.html |
| Podman compose | podman-compose | https://docs.podman.io/en/latest/markdown/podman-compose.1.html |
| CIS Podman | podman-security-bench | https://github.com/containers/podman-security-bench |
| k3s install | k3s Quick-Start | https://docs.k3s.io/quick-start |
| k3s architecture | k3s Architecture | https://docs.k3s.io/architecture |
| kubectl | kubectl Cheatsheet | https://kubernetes.io/docs/reference/kubectl/cheatsheet/ |
| CIS Kubernetes | kube-bench | https://github.com/aquasecurity/kube-bench |
| Ansible getting started | Start automating with Ansible | https://docs.ansible.com/projects/ansible-core/devel/getting_started/get_started_ansible.html |
| Ansible playbooks | Creating a playbook | https://docs.ansible.com/projects/ansible-core/devel/getting_started/get_started_playbook.html |
| Ansible roles | Roles | https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html |
| Ansible dnf module | dnf module | https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/dnf_module.html |
| Ansible firewalld module | firewalld module | https://docs.ansible.com/projects/ansible/latest/collections/ansible/posix/firewalld_module.html |
| Oracle Free Tier | Oracle Cloud Free Tier | https://www.oracle.com/cloud/free/ |
| AWS Free Tier | AWS Free Tier eligibility | https://aws.amazon.com/free/ |
| GCP Free Tier | Google Cloud Free Tier | https://cloud.google.com/free |
| Azure Free Account | Azure Free Account | https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account |
| GitHub Actions | Quickstart for GitHub Actions | https://docs.github.com/en/actions/get-started/quickstart |
| GitLab CI | Getting started with GitLab CI/CD | https://docs.gitlab.com/ci/quick_start/ |
| ArgoCD | Core Concepts | https://argo-cd.readthedocs.io/en/latest/core_concepts/ |
| Prometheus | Getting Started | https://prometheus.io/docs/prometheus/latest/getting_started/ |
| Grafana | Build your first dashboard | https://grafana.com/docs/grafana/latest/getting-started/build-first-dashboard/ |
| Loki | Get started | https://grafana.com/docs/loki/latest/get-started/ |
| SLO/SLI | Google SRE Book, Ch. 4 | https://sre.google/sre-book/service-level-objectives/ |
| Incidents | Google SRE Book, Ch. 14 | https://sre.google/sre-book/managing-incidents/ |
| Postmortems | Google SRE Book, Ch. 15 | https://sre.google/sre-book/postmortem-culture/ |

## See also
- [[00-MOC-SRE-AS-A-SERVICE]] - Technical MOC.
