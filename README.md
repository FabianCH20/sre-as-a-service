<div align="center">

# 🛡️ SRE as a Service

### From Homelab to a Real Service — Infrastructure, Security and Observability

[![Rocky Linux](https://img.shields.io/badge/OS-Rocky%20Linux%209-10B981?style=for-the-badge&logo=rockylinux&logoColor=white)](https://rockylinux.org/)
[![Podman](https://img.shields.io/badge/Containers-Podman-892CA0?style=for-the-badge&logo=podman&logoColor=white)](https://podman.io/)
[![k3s](https://img.shields.io/badge/Orchestration-k3s-FFC61C?style=for-the-badge&logo=kubernetes&logoColor=black)](https://k3s.io/)
[![Ansible](https://img.shields.io/badge/IaC-Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Zabbix](https://img.shields.io/badge/Monitoring-Zabbix-D40000?style=for-the-badge&logo=zabbix&logoColor=white)](https://www.zabbix.com/)
[![Prometheus](https://img.shields.io/badge/Metrics-Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Dashboards-Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/)

</div>

---

## 📖 About the project

**SRE as a Service** is a technical playbook and lab environment that *simulates* what running an SRE-as-a-Service offering would look like — provisioning, rootless containers, Kubernetes orchestration, CI/CD, security audits and end-to-end observability — all running on **Rocky/AlmaLinux 9**, simulating a real headless RHEL environment.

⚠️ **This is a testing/practice environment, not a production service offered to real clients.** It exists to build and demonstrate hands-on SRE skills in a realistic, self-contained setup.

It's not just a collection of commands — every phase includes the **real incident** that triggered it, the diagnosis, the fix that was applied, and the official reference backing it up.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Free-tier cloud (Oracle / GCP / Azure)                  │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Rocky Linux / AlmaLinux 9 (headless, RHEL-like)  │    │
│  │  ├── Hardening: SSH, sudo, firewalld, SELinux     │    │
│  │  ├── Podman (rootless, daemonless)                │    │
│  │  │    ├── Quadlets (systemd-native containers)    │    │
│  │  │    └── k3s (server, single-node)               │    │
│  │  │         ├── Workloads (client apps)            │    │
│  │  │         ├── Prometheus + Grafana + Zabbix       │    │
│  │  │         └── ArgoCD (GitOps)                    │    │
│  │  └── Ansible (provisions everything above)        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
        ▲
        │ CI/CD (GitHub Actions) pushes config
        │ Auditing: CIS Benchmarks, OpenSCAP, Lynis, kube-bench
        │
   This repo (GitHub)
```

---

## ✨ What's new in this version

| Technology | What it brings |
|---|---|
| 🦭 **Podman rootless** | Daemonless container engine with no root privileges — the kernel sees a standard user even though the process "believes" it is root (User Namespaces) |
| 🧩 **Quadlets** | Defines containers as native `systemd` units (`.container`) instead of loose scripts — startup, restarts and logs are managed by `systemctl` |
| 📊 **Zabbix** | Enterprise-grade monitoring integrated with Grafana as a "single pane of glass," added on top of the existing Prometheus + Node Exporter stack |

---

## 🧰 Tech stack

| Layer | Tools |
|---|---|
| **Base system** | Rocky Linux / AlmaLinux 9, SSH hardening, firewalld, SELinux (enforcing) |
| **Containers** | Podman (rootless), Quadlets (systemd), podman-compose |
| **Orchestration** | k3s (single-node and multi-node), kubectl |
| **Automation** | Ansible + `containers.podman` collection |
| **CI/CD & GitOps** | GitHub Actions, GitLab CI, ArgoCD |
| **Security & Auditing** | Lynis, OpenSCAP, CIS Benchmarks, kube-bench |
| **Observability** | Prometheus, Grafana, Node Exporter, Zabbix |
| **Cloud** | Oracle Cloud Always Free (Ampere A1 ARM) |

---

## 📂 Repo structure

```
sre-as-a-service/
├── README.md
├── docs/
│   └── SRE-as-a-Service-Playbook.md   # Full playbook, phase by phase
├── ansible/
│   ├── inventory.ini
│   └── playbook.yml
├── monitoring/
│   ├── docker-compose.monitoring.yml
│   └── prometheus.yml
├── zabbix/
│   └── docker-compose.zabbix.yml
└── k8s/
    └── alert.rules.yml
```

---

## 🗺️ Roadmap

- [x] **Phase 0** — Base server hardening (SSH, sudo, firewalld, SELinux)
- [x] **Phase 1** — Rootless containers with Podman + Quadlets
- [x] **Phase 2** — Orchestration with k3s (control plane + workers)
- [x] **Phase 3** — Automation with Ansible
- [ ] **Phase 4** — Cloud deployment (Oracle Always Free)
- [ ] **Phase 5** — CI/CD and GitOps with ArgoCD
- [ ] **Phase 6** — Security audits (Lynis, OpenSCAP, kube-bench)
- [x] **Phase 7** — Monitoring with Prometheus, Grafana and Zabbix

---

## 📚 Full documentation

The full step-by-step technical playbook — with commands, real error symptoms and fixes — lives in [`docs/SRE-as-a-Service-Playbook.md`](docs/SRE-as-a-Service-Playbook.md).

---

<div align="center">

### 👤 Author

**Fabian Chaves** — SRE / SysAdmin / Security (Blue Team)

[![GitHub](https://img.shields.io/badge/GitHub-FabianCH20-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/FabianCH20)

</div>
