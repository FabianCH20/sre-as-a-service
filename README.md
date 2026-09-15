<div align="center">

# 🛡️ SRE as a Service

### Del Homelab a un Servicio Real — Infraestructura, Seguridad y Observabilidad

[![Rocky Linux](https://img.shields.io/badge/OS-Rocky%20Linux%209-10B981?style=for-the-badge&logo=rockylinux&logoColor=white)](https://rockylinux.org/)
[![Podman](https://img.shields.io/badge/Containers-Podman-892CA0?style=for-the-badge&logo=podman&logoColor=white)](https://podman.io/)
[![k3s](https://img.shields.io/badge/Orchestration-k3s-FFC61C?style=for-the-badge&logo=kubernetes&logoColor=black)](https://k3s.io/)
[![Ansible](https://img.shields.io/badge/IaC-Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Zabbix](https://img.shields.io/badge/Monitoring-Zabbix-D40000?style=for-the-badge&logo=zabbix&logoColor=white)](https://www.zabbix.com/)
[![Prometheus](https://img.shields.io/badge/Metrics-Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Dashboards-Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/)

</div>

---

## 📖 Sobre el proyecto

**SRE as a Service** es un playbook técnico que documenta la transformación de un homelab personal en un stack de infraestructura profesional, listo para ofrecerse como servicio a terceros: aprovisionamiento, contenedores rootless, orquestación con Kubernetes, CI/CD, auditorías de seguridad y observabilidad de extremo a extremo — todo corriendo sobre **Rocky/AlmaLinux 9** simulando un entorno RHEL real, sin GUI.

No es solo una colección de comandos: cada fase incluye el **incidente real** que la originó, el diagnóstico, el fix aplicado y la referencia oficial que lo respalda.

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│  Nube gratuita (Oracle / GCP / Azure)                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Rocky Linux / AlmaLinux 9 (headless, RHEL-like)  │    │
│  │  ├── Hardening: SSH, sudo, firewalld, SELinux     │    │
│  │  ├── Podman (rootless, sin daemon)                │    │
│  │  │    ├── Quadlets (systemd-native containers)    │    │
│  │  │    └── k3s (server, single-node)               │    │
│  │  │         ├── Workloads (apps de clientes)       │    │
│  │  │         ├── Prometheus + Grafana + Zabbix       │    │
│  │  │         └── ArgoCD (GitOps)                    │    │
│  │  └── Ansible (aprovisiona todo lo anterior)       │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
        ▲
        │ CI/CD (GitHub Actions) hace push de config
        │ Auditoría: CIS Benchmarks, OpenSCAP, Lynis, kube-bench
        │
   Este repo (GitHub)
```

---

## ✨ Novedades de esta versión

| Tecnología | Qué aporta |
|---|---|
| 🦭 **Podman rootless** | Motor de contenedores sin daemon ni privilegios root — el kernel ve un usuario estándar aunque el proceso "crea" ser root (User Namespaces) |
| 🧩 **Quadlets** | Define contenedores como unidades nativas de `systemd` (`.container`) en vez de scripts sueltos — arranque, reinicio y logs gestionados por `systemctl` |
| 📊 **Zabbix** | Monitoreo enterprise integrado con Grafana como "single pane of glass", sumado al stack de Prometheus + Node Exporter ya existente |

---

## 🧰 Stack tecnológico

| Capa | Herramientas |
|---|---|
| **Sistema base** | Rocky Linux / AlmaLinux 9, SSH hardening, firewalld, SELinux (enforcing) |
| **Contenedores** | Podman (rootless), Quadlets (systemd), podman-compose |
| **Orquestación** | k3s (single-node y multi-node), kubectl |
| **Automatización** | Ansible + colección `containers.podman` |
| **CI/CD & GitOps** | GitHub Actions, GitLab CI, ArgoCD |
| **Seguridad & Auditoría** | Lynis, OpenSCAP, CIS Benchmarks, kube-bench |
| **Observabilidad** | Prometheus, Grafana, Node Exporter, Zabbix |
| **Nube** | Oracle Cloud Always Free (Ampere A1 ARM) |

---

## 📂 Estructura del repo

```
sre-as-a-service/
├── README.md
├── docs/
│   └── SRE-as-a-Service-Playbook.md   # Playbook completo, fase por fase
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

- [x] **Fase 0** — Hardening del servidor base (SSH, sudo, firewalld, SELinux)
- [x] **Fase 1** — Contenedores rootless con Podman + Quadlets
- [x] **Fase 2** — Orquestación con k3s (control plane + workers)
- [x] **Fase 3** — Automatización con Ansible
- [ ] **Fase 4** — Despliegue en nube (Oracle Always Free)
- [ ] **Fase 5** — CI/CD y GitOps con ArgoCD
- [ ] **Fase 6** — Auditorías de seguridad (Lynis, OpenSCAP, kube-bench)
- [x] **Fase 7** — Monitoreo con Prometheus, Grafana y Zabbix

---

## 📚 Documentación completa

El playbook técnico paso a paso —con comandos, síntomas de error y fixes reales— está en [`docs/SRE-as-a-Service-Playbook.md`](docs/SRE-as-a-Service-Playbook.md).

---

<div align="center">

### 👤 Autor

**Fabian Chaves** — SRE / SysAdmin / Security (Blue Team)

[![GitHub](https://img.shields.io/badge/GitHub-FabianCH20-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/FabianCH20)

</div>
