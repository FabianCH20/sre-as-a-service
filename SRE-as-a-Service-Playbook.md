---
title: SRE as a Service Playbook
tags: [SRE, playbook, infrastructure, hardening, k3s, podman, observability, automation, security]
proyecto: "[[00-MOC-SRE-HOME-LAB]]"
incidentes: "[[INC-00-SRE-AS-A-SERVICE]]"
fecha: 2026-09-07
estado: activo
---

# Playbook: SRE as a Service — Del Homelab a un Servicio Real

**Base:** Rocky Linux / AlmaLinux 9 (simulando RHEL, servidor sin GUI, "minimal install")
**Proyecto de referencia:** `FabianCH20/sre-homelab-portfolio`
**Objetivo:** Convertir el homelab (Podman + k3s + Ansible + monitoreo) en un stack profesional ofrecido como servicio (SRE-as-a-Service) para terceros: infraestructura, seguridad, CI/CD y soporte.

---

## 🏗️ Arquitectura General del Proyecto

```
┌─────────────────────────────────────────────────────────┐
│  Nube gratuita (Oracle / GCP / Azure)                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Rocky Linux / AlmaLinux 9 (headless, RHEL-like)  │    │
│  │  ├── Hardening: SSH, sudo, firewalld, SELinux     │    │
│  │  ├── Podman (rootless, sin daemon)                │    │
│  │  │    └── k3s (server, single-node)               │    │
│  │  │         ├── Workloads (apps de clientes)       │    │
│  │  │         ├── Prometheus + Grafana + Loki        │    │
│  │  │         └── ArgoCD (GitOps)                    │    │
│  │  └── Ansible (aprovisiona todo lo anterior)       │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
        ▲
        │ CI/CD (GitHub Actions / GitLab CI) hace push de config
        │ Auditoría: CIS Benchmarks, OpenSCAP, Lynis, kube-bench
        │
   Tu repo: sre-homelab-portfolio (GitHub)
```

---

## 🛡️ FASE 0 — Servidor Base: Rocky Linux / AlmaLinux

### 0.1 Instalación Mínima (Headless)
**Objetivo:** Instalar SO base simulando servidor RHEL real.
- **Acción**: ISO minimal $\rightarrow$ "Minimal Install (Basic functionality)".
- **Comandos**:
  ```bash
  wget https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-minimal.iso
  sha256sum -c CHECKSUM --ignore-missing
  ```

### 0.2 Hardening SSH
**Objetivo:** Permitir login remoto de root, pero eliminar autenticación por contraseña.
- **Decisión**: `PermitRootLogin prohibit-password` (Root solo con llave).
- **Acción**:
  ```bash
  ssh-keygen -t ed25519
  ssh-copy-id root@servidor
  ```
- **Config `/etc/ssh/sshd_config`**:
  ```
  PermitRootLogin prohibit-password
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  ```
- **Verificación**: `systemctl restart sshd` $\rightarrow$ Conectar via MobaXterm con llave (debe funcionar) $\rightarrow$ Intentar con pass (debe fallar).
**🚨 Recuperación de Acceso (Troubleshooting):**
Si pierdes el acceso remoto ("Connection refused" o "Network connection not found"):
1. Acceder via Consola VM $\rightarrow$ `nano /etc/ssh/sshd_config`.
2. Habilitar temporalmente: `PermitRootLogin yes` y `PasswordAuthentication yes`.
3. Reiniciar servicio: `systemctl restart sshd`.
4. Verificar Firewall: `firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload`.
5. Una vez recuperado el acceso, enviar la llave con `ssh-copy-id` y volver a deshabilitar contraseñas.

- **Controles Compensatorios**:
  - Restringir puerto 22 por IP via `firewalld`.
  - Instalar `fail2ban`: `dnf install epel-release && dnf install fail2ban && systemctl enable --now fail2ban`.

### 0.3 Sudo & Administración
**Objetivo:** Gestión administrativa sin usar root directo siguiendo mejores prácticas de SRE.

**1. Asignación de Grupo Administrativo**:
Agregar el usuario al grupo `wheel` para habilitar capacidades básicas de sudo:
```bash
usermod --append -G wheel <usuario>
```

**2. Configuración Modular de Permisos (Sudoers.d)**:
Para evitar corromper el archivo maestro `/etc/sudoers` y facilitar la automatización con Ansible, se crean archivos independientes en `/etc/sudoers.d/`.

- **Acción**: Crear archivo específico para el usuario usando `nano`:
  ```bash
  sudo nano /etc/sudoers.d/<usuario>
  ```
- **Contenido**: Agregar la siguiente regla para permitir ejecución de comandos sin contraseña (ideal para pipelines de CI/CD):
  ```text
  <usuario> ALL=(ALL) NOPASSWD:ALL
  ```
- **Seguridad Crítica**: Sudo ignora archivos con permisos incorrectos. Se debe asignar obligatoriamente el permiso `0440`:
  ```bash
  sudo chmod 0440 /etc/sudoers.d/<usuario>
  ```

**3. Validación de Seguridad**:
Validar que no existan errores de sintaxis que puedan bloquear el acceso administrativo:
```bash
sudo visudo
```

**4. Prueba de Acceso**:
Verificar la transición a root sin solicitud de contraseña:
```bash
sudo -i
```

### 0.4 Actualizaciones Automáticas (`dnf-automatic`)
**Objetivo:** Parcheo automático de seguridad.
- **Acción**:
  ```bash
  sudo dnf install dnf-automatic
  sudo systemctl edit dnf-automatic.timer # Ajustar OnCalendar=*-*-* 6:00
  sudo systemctl enable --now dnf-automatic.timer
  ```

### 0.5 firewalld (Zonas y Reglas)
**Objetivo:** Control de tráfico entrante/saliente.
- **Acción**:
  ```bash
  firewall-cmd --zone=public --add-service=http
  firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="ssh" accept'
  firewall-cmd --runtime-to-permanent
  firewall-cmd --reload
  ```

### 0.6 SELinux (Enforcing)
**Objetivo:** Control de acceso obligatorio (MAC).
- **Diagnóstico**:
  ```bash
  getenforce
  ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts recent
  sealert -l "*"
  restorecon -R -v /ruta
  ```
- **Remediación**: `audit2allow -a > modulo.te && semodule -i modulo.pp`.

---

## 📦 FASE 1 — Contenedores: Podman

### 1.1 Instalación Enterprise
**Objetivo:** Motor rootless sin daemon.
- **Acción**:
  ```bash
  sudo dnf -y install podman
  sudo dnf -y install epel-release podman-compose
  ```
  🚨 **Incidencia Relacionada**: [[incidentes/INC-00-SRE-AS-A-SERVICE#INC-02|INC-02: Error de dependencias EPEL/podman-compose]]

### 1.2 Arquitectura Rootless & Namespaces
**Objetivo:** Comprender el aislamiento de procesos y el mapeo de identidades sin privilegios de root.

#### 1. Concepto de Mapeo de UIDs (The "Identity Lie")
Podman utiliza **User Namespaces** para que un proceso dentro del contenedor crea que es `root` (UID 0), mientras que para el Kernel de Linux sigue siendo un usuario estándar (ej. UID 1000).

- **Configuración de Rangos**: Los UIDs disponibles se definen en `/etc/subuid` y `/etc/subgid`.
  - Ejemplo: `krikox:100000:65536` $\rightarrow$ El usuario puede mapear sus procesos al rango 100,000 - 165,535 del host.
- **Aislamiento**: Si el contenedor es vulnerado, el atacante solo tiene permisos del usuario estándar en el host, eliminando el riesgo de escalada de privilegios total.

#### 2. Diagnóstico y Verificación de Identidad
| Comando | Qué verifica | Resultado esperado |
| :--- | :--- | :--- |
| `podman unshare id` | Identidad dentro del namespace | `uid=0(root)` (aunque seas usuario estándar) |
| `podman top <container> huser` | Comparativa Host vs Contenedor | Host: `1000` $\rightarrow$ Container: `0` |
| `lsns -t mnt` | Existencia de Namespaces | Lista de namespaces de montaje activos |
| `cat /etc/subuid` | Cuotas de UIDs asignadas | Rango de IDs secundarios permitidos |

#### 3. Prueba Práctica: Despliegue de Web Server Rootless
Para validar la arquitectura, desplegamos un servidor Nginx y analizamos su identidad.

**A. Lanzar el contenedor:**
```bash
podman run -d --name poc-web -p 8080:80 nginx
```

**B. Validar el mapeo de identidad (La prueba clave):**
```bash
podman top poc-web huser
```
*Observarás que el proceso que el contenedor ve como `root` es en realidad tu usuario en el host.*

**C. Verificar funcionalidad:**
```bash
curl localhost:8080
```

**D. Limpieza:**
```bash
podman stop poc-web && podman rm poc-web
```

**Referencias Técnicas:**
- [Podman Rootless Documentation](https://docs.podman.io/en/latest/Rootless/)
- [Linux User Namespaces Guide](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Red Hat: Rootless Containers](https://www.redhat.com/en/blog/rootless-containers-podman)


### 1.3 Límites de Recursos
**Objetivo:** Restringir el consumo de CPU y Memoria para evitar el "ruido" entre contenedores (Noisy Neighbor) y garantizar la estabilidad del host.

- **Acción**:
  - **Ejemplo con Alpine (Ligero/Prueba rápida):**
   podman run -d \ --name test-alpine \ -m 512m \ --cpus=1.5 \ --memory-swap=512m \ alpine \ sleep 1000
  - **Ejemplo con Nginx (Servicio Real):**
    ```bash
    podman run -d --name test-nginx -m 512m --cpus=1.5 --memory-swap=0 nginx
    ```

- **Validación de Métricas (Crucial para SRE):**
  Para confirmar que los límites se están aplicando correctamente en tiempo real:
  ```bash
  podman stats test-alpine test-nginx
  ```

### 1.4 Pods (Puente a Kubernetes)
- **Acción**:
  ```bash
  podman pod create --name mipod
  podman create --pod mipod nginx
  podman create --pod mipod redis
  podman pod start mipod
  ```

## Instalación correcta de Quadlet (Podman + systemd)

### 1. Prerequisitos

bash

```bash
podman --version          # debe ser >= 4.6
dnf module list container-tools   # RHEL/Rocky/Alma — confirmar stream activo
```

- Síntoma si falla: generador no reconoce claves nuevas o falta el binario `/usr/lib/systemd/system-generators/podman-system-generator`.
- Fix: `sudo dnf module switch-to container-tools:4.6 && sudo dnf update podman`
- Ref: [RHEL 8 – Note: "Quadlet is available beginning with Podman v4.6"](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers#auto-generating-a-systemd-unit-file-using-quadlets_assembly_porting-containers-to-systemd-using-podman)

### 2. Elegir la ruta correcta (root vs rootless)

|Modo|Ruta|Uso|
|---|---|---|
|Root|`/etc/containers/systemd/`|admin del sistema|
|Root|`/usr/share/containers/systemd/`|quadlets de paquete/distro (NO para usuario normal)|
|Rootless|`$HOME/.config/containers/systemd/` o `$XDG_CONFIG_HOME/containers/systemd/`|tu propio usuario|
|Rootless|`/etc/containers/systemd/users/$UID`|admin define quadlets para un usuario específico|

⚠️ Lección del incidente anterior: `/usr/share/containers/systemd/` **no es escaneado** por `systemctl --user`. Si sos usuario normal (rootless), la ruta es siempre `$HOME/.config/containers/systemd/`.

- Ref: [podman-systemd.unit(5) — "Podman Quadlet Unit Search Path"](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

### 3. Crear el directorio (no existe por defecto)

bash

```bash
mkdir -p $HOME/.config/containers/systemd/
```

- Síntoma si se omite: `No such file or directory` al intentar crear el `.container`.
- Ref: [Red Hat Blog — Deploying a multi-container application using Podman and Quadlet (paso explícito de `mkdir -p`)](https://www.redhat.com/en/blog/multi-container-application-podman-quadlet)

### 4. Crear el archivo `.container`

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

- Campos obligatorios en `[Container]`: `Image` y (opcional) `Exec`.
- Ref: [RHEL 8 – Auto-generating a systemd unit file using Quadlets (ejemplo `mysleep.container`)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers#auto-generating-a-systemd-unit-file-using-quadlets_assembly_porting-containers-to-systemd-using-podman)

### 5. Validar ANTES de daemon-reload (paso que evita el incidente anterior)

bash

```bash
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun
```

- Síntoma correcto: imprime el contenido completo del `mysleep.service` generado.
- Síntoma de error: `No files parsed from [...]` → el archivo está en una ruta no escaneada (volver al paso 2).
- Ref: [podman-systemd.unit(5) — sección "Debugging Quadlet files"](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

### 6. Generar el servicio

bash

```bash
systemctl --user daemon-reload
```

### 7. Verificar generación real (no solo el reload)

bash

```bash
ls /run/user/$(id -u)/systemd/generator/ | grep mysleep
systemctl --user list-unit-files | grep mysleep
```

- El `.service` real vive en `/run/user/<UID>/systemd/generator/`, no junto al `.container`.

### 8. Iniciar y habilitar

bash

```bash
systemctl --user start mysleep.service
systemctl --user enable mysleep.service   # si no usás WantedBy en el .container
```

### 9. Verificación final

bash

```bash
systemctl --user status mysleep.service
podman ps -a   # debe aparecer como systemd-mysleep
```

- Ref: [podman-quadlet-basic-usage(7)](https://docs.podman.io/en/latest/markdown/podman-quadlet-basic-usage.7.html)

### 10. (Opcional, rootless persistente tras logout)

bash

```bash
loginctl enable-linger $USER
```

Sin esto, el servicio `--user` se detiene al cerrar sesión SSH.

- Ref: [RHEL 9 – Porting containers to systemd using Podman](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_porting-containers-to-systemd-using-podman_building-running-and-managing-containers)
### 1.6 Migración a Kubernetes
**Objetivo**: Generar YAML real desde Podman.
- **Acción**:
  ```bash
  podman kube generate mipod > mipod.yaml
  podman kube play mipod.yaml
  ```

---

## ☸️ FASE 2 — Orquestación: k3s (Multi-Node Cluster)

**Referencias oficiales:**
- [docs.k3s.io](https://docs.k3s.io/) — documentación oficial de k3s
- [kubernetes.io/docs/setup/production-environment/](https://kubernetes.io/docs/setup/production-environment/) — guía de entorno de producción de K8s
- [github.com/k3s-io/k3s](https://github.com/k3s-io/k3s) — repositorio oficial de k3s

### 2.1 — Instalación del Control Plane (Master Node)

El Control Plane es el cerebro del clúster; gestiona el estado, el scheduler y la API.

**📍 Dónde ejecutar:** En el servidor principal (ej. `SRE-Master-01`).

**1. Ejecutar script de instalación**
```bash
curl -sfL https://get.k3s.io | sh -
```
→ Este comando instala k3s, configura el kubeconfig en `/etc/rancher/k3s/k3s.yaml` y levanta los servicios necesarios.

**2. Recuperar el TOKEN del clúster**
Para que los Workers puedan unirse al clúster, necesitan un token de seguridad único generado por el Master.
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```
→ **Copia este valor**. Ejemplo de token: `K10:abc123def456ghi789jklmnop...`

**3. Verificar que el servidor está corriendo**
```bash
sudo kubectl get nodes
```
→ Debe mostrar el nodo `SRE-Master-01` con el estado `Ready` y el rol `control-plane,master`.

---

### 2.2 — Instalación de Worker Nodes (Agentes)

Los Worker Nodes son los encargados de ejecutar los contenedores (Pods) y las cargas de trabajo reales.

**📍 Dónde ejecutar:** En cada servidor secundario que quieras sumar al clúster (ej. `SRE-Worker-01`, `SRE-Worker-02`).

**1. Ejecutar script de unión al clúster**
Sustituye `<IP_MASTER>` por la IP real del Control Plane y `<TOKEN>` por el valor obtenido en el paso anterior.
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<IP_MASTER>:6443 K3S_TOKEN=<TOKEN> sh -
```
**Ejemplo real:**
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.100.42:6443 K3S_TOKEN=K10:abc123def456ghi789jklmnop sh -
```
→ `K3S_URL`: Indica al agente dónde está la API del clúster (puerto 6443 por defecto).
→ `K3S_TOKEN`: Autentica al nodo para que el Master lo acepte como parte del clúster.

**2. Verificar la unión desde el Control Plane**
Vuelve al servidor Master y ejecuta:
```bash
sudo kubectl get nodes -o wide
```
→ **Resultado esperado**: Deberías ver ahora todos los nodos listados.
- `SRE-Master-01` $\rightarrow$ `control-plane,master`
- `SRE-Worker-01` $\rightarrow$ `<none>` (esto indica que es un Worker puro).

---

### 2.3 — Operación y Salud del Clúster

**Acciones comunes de administración:**
```bash
# Ver estado general de los nodos y sus IPs
kubectl get nodes -o wide

# Ver el consumo de recursos en tiempo real (requiere metrics-server, incluido en k3s)
kubectl top node

# Ver eventos recientes del clúster para diagnosticar fallos
kubectl get events -A --sort-by='.lastTimestamp'
```

**Configuración del Kubeconfig (Acceso Remoto):**
Si quieres gestionar el clúster desde tu PC (via MobaXterm/VSCode) sin entrar al servidor:
1. Copia el contenido de `/etc/rancher/k3s/k3s.yaml` del Master.
2. Guárdalo en tu PC en `~/.kube/config`.
3. Cambia `server: https://127.0.0.1:6443` por `server: https://<IP_MASTER>:6443`.
---

## ⚙️ FASE 3 — Automatización: Ansible

### 3.1 Setup e Infraestructura de Control
**Objetivo:** Preparar el entorno de control para gestionar la infraestructura sin intervención manual.

1. **Creación de estructura de archivos**:
   ```bash
   mkdir -p /opt/ansible
   cd /opt/ansible
   ```

2. **Instalación de Ansible**:
   ```bash
   pip install ansible
   ```

3. **Configuración del Inventario (`inventory.ini`)**:
   Define qué servidores vas a gestionar.
   ```ini
   # inventory.ini
   [web]
   srv-prod-01 ansible_connection=local

   [web:vars]
   ansible_python_interpreter=/usr/bin/python3
   ```
   → `ansible_connection=local` indica que el nodo de control y el gestionado son el mismo servidor.

4. **Prueba de Conectividad**:
   ```bash
   ansible web -i inventory.ini -m ping
   ```

### 3.2 Playbook de Implementación (`playbook.yml`)
**Objetivo:** Definir el estado deseado del servidor de forma declarativa.

```yaml
# playbook.yml
- hosts: web
  become: true
  tasks:
    - name: Actualizar todos los paquetes del sistema (RHEL-family)
      dnf:
        name: "*"
        state: latest

    - name: Instalar motor de contenedores Podman
      dnf:
        name: podman
        state: present

    - name: Instalar podman-compose para stacks multi-contenedor
      dnf:
        name: podman-compose
        state: present

    - name: Crear directorio para la aplicación
      file:
        path: /opt/app
        state: directory
        mode: "0755"

    - name: Desplegar configuración de la app mediante plantilla
      template:
        src: templates/app.env.j2
        dest: /opt/app/.env
        mode: "0600"
      notify: reiniciar app

  handlers:
    - name: reiniciar app
      containers.podman.podman_container:
        name: miapp
        image: nginx:latest
        state: started
        restart_policy: always
```

### 3.3 Ejecución y Validación
Para ejecutar el playbook con seguridad y privilegios correctos:

- **Modo Dry-Run (Simulación)**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check
  ```
- **Ejecución Real con Privilegios**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
  ```
  → `--ask-become-pass` solicita la contraseña de `sudo` necesaria para las tareas de `become: true`.

### 3.4 Módulos Clave para RHEL/Podman Family
- **`ansible.builtin.dnf`**: Gestión de paquetes (Rocky/AlmaLinux).
- **`ansible.builtin.systemd`**: Control de servicios y timers.
- **`ansible.posix.firewalld`**: Configuración de reglas de firewall.
- **`containers.podman.podman_container`**: Gestión del ciclo de vida de contenedores rootless.

### 📦 Guía: Instalación y Uso de la Colección `containers.podman`

Para que el módulo de Podman funcione, es necesario instalar la colección en la **Máquina de Control** (donde se ejecuta Ansible).

**1. Instalación**
```bash
ansible-galaxy collection install containers.podman
```

**2. Verificación**
```bash
ansible-galaxy collection list | grep podman
```

**3. Uso Profesional (FQCN)**
Se recomienda usar el nombre completo del módulo para evitar ambigüedades:
`containers.podman.podman_container` en lugar de solo `podman_container`.

**4. Requisitos de Flujo**
- **Control**: `ansible-galaxy collection install containers.podman`
- **Nodo**: `dnf install podman` (gestionado por el playbook).







---

## ☁️ FASE 4 — Despliegue en Nube (Always Free)

| Proveedor | Cómputo gratis | Duración | Limitante clave |
|---|---|---|---|
| **Oracle Cloud** | 2 OCPU / 12 GB ARM (Ampere A1) | **Perpetuo** | 10 TB egress/mes |
| **GCP** | 1 instancia e2-micro | **Perpetuo** | Solo 1 GB egress/mes fuera de GCP |
| **AWS** | Crédito $100-200 | **6 meses** | Sin EC2 gratis perpetuo para cuentas nuevas |
| **Azure** | VM B1s/B2pts/B2ats | **12 meses** | No es gratis para siempre |

**Recomendación**: Oracle Cloud (Ampere A1) como host principal.

---

## 🚀 FASE 5 — CI/CD y GitOps

### 5.1 Pipelines
- **GitHub Actions**: `.github/workflows/demo.yml` $\rightarrow$ `actions/checkout@v6` $\rightarrow$ `run: ls`.
- **GitLab CI**: `.gitlab-ci.yml` $\rightarrow$ Stages: `build`, `test`, `deploy-prod`.

### 5.2 ArgoCD (GitOps)
**Objetivo**: Sincronización automática Git $\rightarrow$ k3s.
- **Instalación**:
  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  ```
- **Operación**: `argocd app create <name> --repo <url> --path <path> --dest-server <url> --dest-namespace <ns>`.

---

## 🔍 FASE 6 — Seguridad y Auditoría

### 6.1 Cumplimiento CIS & OpenSCAP
- **OpenSCAP**:
  ```bash
  dnf install scap-security-guide openscap-scanner openscap-utils
  oscap xccdf eval --report scan-report.html --profile xccdf_org.ssgproject.content_profile_cis /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
  ```

### 6.2 Auditorías Generales
- **Lynis**: `git clone https://github.com/CISOfy/lynis /usr/local/lynis && ./lynis audit system`.
- **Podman Security**: `bash podman-security-bench.sh`.
- **Kubernetes (k3s)**: `kube-bench` (via Job YAML).

---

## 📈 FASE 7 — Monitoreo Automatizado (Prometheus + Grafana + Zabbix)

**Referencias oficiales:**
- [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) — documentación oficial de Prometheus
- [grafana.com/docs](https://grafana.com/docs/) — documentación oficial de Grafana
- [zabbix.com/documentation](https://www.zabbix.com/documentation/current/) — documentación oficial de Zabbix
- [github.com/prometheus/prometheus](https://github.com/prometheus/prometheus) · [github.com/prometheus/node_exporter](https://github.com/prometheus/node_exporter) · [github.com/grafana/grafana](https://github.com/grafana/grafana) · [github.com/zabbix/zabbix](https://github.com/zabbix/zabbix)
- [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/) — repositorio de dashboards comunitarios (incluye el dashboard 1860 usado en esta fase)

```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
```
→ Usuario de sistema sin login ni home, por seguridad (servicios no deben correr como usuarios interactivos).

### 7.1 — Prometheus + Grafana + Node Exporter, paso a paso

**1. Resuelve la versión más reciente y descarga**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Versión detectada: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ La versión se resuelve dinámicamente consultando la API de GitHub (`tag_name` del último release) en vez de escribir un número de versión fijo en la URL — un número fijo combinado con `/latest/download/` se desactualiza tarde o temprano.

**2. Verifica que descargaste un archivo real, no una página de error, ANTES de extraer**

```bash
file node_exporter-*.tar.gz
```
→ Debe decir `gzip compressed data`. Si dice `HTML document`, bórrela y repite el paso 1.

**3. Extrae el archivo**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirma que el binario existe dentro de la carpeta extraída ANTES de moverlo**

```bash
ls -la ~ | grep node_exporter
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```

**5. Mueve el binario a `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```

**6. Verifica que el binario quedó instalado y responde**

```bash
node_exporter --version
```

**7. Limpieza**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Crea el archivo de definición del servicio:**
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

**Crea una carpeta para el stack de monitoreo:**
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

**Crea el archivo de configuración de Prometheus:**
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
      - targets: ["<IP_SERVIDOR>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<IP_SERVIDOR>:10250"]
```

```bash
podman-compose -f docker-compose.monitoring.yml up -d
```
→ Se utiliza `podman-compose` para mantener la arquitectura rootless y daemonless definida en el resto del proyecto SRE-as-a-Service.

### 7.2 — Levantar el stack y acceder vía navegador, paso a paso

**1. Verifica que ambos contenedores quedaron corriendo**

```bash
podman-compose -f docker-compose.monitoring.yml ps
```

**2. Confirma que los puertos están expuestos correctamente**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```

**3. Accede a Prometheus desde el navegador**
`http://<IP_SERVIDOR>:9090`
Confirma targets en: `http://<IP_SERVIDOR>:9090/targets`

**4. Accede a Grafana desde el navegador**
`http://<IP_SERVIDOR>:3000` (Admin / admin)

**5. Conecta Grafana con Prometheus como fuente de datos**
`Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Prometheus`
URL: `http://prometheus:9090`

**6. Importa el dashboard estándar de la industria**
`Dashboards` $\rightarrow$ `New` $\rightarrow$ `Import` $\rightarrow$ ID: `1860` (Node Exporter Full).

### 7.3 — Zabbix: Monitoreo Enterprise, paso a paso

**1. Instalar Zabbix Agent en el Host**
El agente recolecta datos del hardware y el SO nativamente.

```bash
# Repositorio oficial Zabbix para Rocky Linux 9
sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
sudo dnf clean all
sudo dnf install zabbix-agent -y
```

**2. Configurar el agente**
```bash
sudo nano /etc/zabbix_agentd.conf
```
Edita:
```ini
Server=<IP_SERVIDOR>
ServerActive=<IP_SERVIDOR>
Hostname=SRE-Server-01
```

**3. Habilitar y abrir puerto**
```bash
sudo systemctl enable zabbix-agent --now
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload
```

**4. Desplegar Zabbix Server Stack via Podman**
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

**5. Crear archivo de entorno `.env_zabbix`**
```ini
DB_SERVER=zabbix-db
MYSQL_DATABASE=zabbix
MYSQL_USER=zabbix
MYSQL_PASSWORD=zabbix_pwd
MYSQL_ROOT_PASSWORD=root_pwd
ZBX_SERVER_HOST=zabbix-server
PHP_TZ=America/New_York
```

**6. Levantar y Verificar**
```bash
podman-compose -f docker-compose.zabbix.yml up -d
```
Acceso: `http://<IP_SERVIDOR>:8080` (Admin / zabbix).
→ Configura el host `SRE-Server-01` en `Configuration` $\rightarrow$ `Hosts` usando el template `Linux by Zabbix agent`.

### 7.4 — Integración Unificada en Grafana

Para tener un "Single Pane of Glass", integramos Zabbix en Grafana.

**1. Instalar Plugin de Zabbix**
```bash
# Busca el ID del contenedor de Grafana
GRAFANA_ID=$(podman ps -qf "name=grafana")
podman exec -it $GRAFANA_ID grafana-cli plugins install alexanderzobnin-zabbix-app
podman restart $GRAFANA_ID
```

**2. Habilitar y Configurar**
- `Administration` $\rightarrow$ `Plugins` $\rightarrow$ `Zabbix` $\rightarrow$ **Enable**.
- `Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Zabbix`.
- **URL**: `http://<IP_SERVIDOR>:8080/zabbix/api_jsonrpc.php`.
- **User/Pass**: `Admin` / `zabbix`.

### 7.5 — Alertas básicas y Gobernanza (SRE)

**1. Reglas de Alerta en Prometheus**
Crea `/opt/monitoring/alert.rules.yml`:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiscoLleno
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Disco con menos de 15% libre en {{ $labels.instance }}"}
```
Referencia este archivo en `prometheus.yml` y monta el volumen en `docker-compose.monitoring.yml`.

**2. Gobernanza SRE**
- **SLI**: Medida cuantitativa (ej. latencia de API).
- **SLO**: Objetivo sobre SLI (ej. 99.9% de requests < 200ms).
- **SLA**: Acuerdo legal basado en el SLO.
- **Error Budget**: El margen de error permitido antes de detener despliegues para estabilizar el sistema.
- **Incidentes**: Flujo de `Detección` $\rightarrow$ `Mitigación` $\rightarrow$ `Postmortem Blameless`.
 sistema sin login ni home, por seguridad (servicios no deben correr como usuarios interactivos).

### 7.1 — Prometheus + Grafana + Node Exporter, paso a paso

**1. Resuelve la versión más reciente y descarga**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Versión detectada: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ La versión se resuelve dinámicamente consultando la API de GitHub (`tag_name` del último release) en vez de escribir un número de versión fijo en la URL — un número fijo combinado con `/latest/download/` se desactualiza tarde o temprano.

**2. Verifica que descargaste un archivo real, no una página de error, ANTES de extraer**

```bash
file node_exporter-*.tar.gz
```
→ Debe decir `gzip compressed data`. Si dice `HTML document`, bórrela y repite el paso 1.

**3. Extrae el archivo**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirma que el binario existe dentro de la carpeta extraída ANTES de moverlo**

```bash
ls -la ~ | grep node_exporter
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```

**5. Mueve el binario a `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```

**6. Verifica que el binario quedó instalado y responde**

```bash
node_exporter --version
```

**7. Limpieza**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Crea el archivo de definición del servicio:**
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

**Crea una carpeta para el stack de monitoreo:**
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

**Crea el archivo de configuración de Prometheus:**
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
      - targets: ["<IP_SERVIDOR>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<IP_SERVIDOR>:10250"]
```

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

### 7.2 — Levantar el stack y acceder vía navegador, paso a paso

**1. Verifica que ambos contenedores quedaron corriendo**

```bash
docker compose -f docker-compose.monitoring.yml ps
```

**2. Confirma que los puertos están expuestos correctamente**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```

**3. Accede a Prometheus desde el navegador**
`http://<IP_SERVIDOR>:9090`
Confirma targets en: `http://<IP_SERVIDOR>:9090/targets`

**4. Accede a Grafana desde el navegador**
`http://<IP_SERVIDOR>:3000` (Admin / admin)

**5. Conecta Grafana con Prometheus como fuente de datos**
`Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Prometheus`
URL: `http://prometheus:9090`

**6. Importa el dashboard estándar de la industria**
`Dashboards` $\rightarrow$ `New` $\rightarrow$ `Import` $\rightarrow$ ID: `1860` (Node Exporter Full).

### 7.3 — Zabbix: Monitoreo Enterprise, paso a paso

**1. Instalar Zabbix Agent en el Host**
El agente recolecta datos del hardware y el SO nativamente.

```bash
# Repositorio oficial Zabbix para Rocky Linux 9
sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
sudo dnf clean all
sudo dnf install zabbix-agent -y
```

**2. Configurar el agente**
```bash
sudo nano /etc/zabbix_agentd.conf
```
Edita:
```ini
Server=<IP_SERVIDOR>
ServerActive=<IP_SERVIDOR>
Hostname=SRE-Server-01
```

**3. Habilitar y abrir puerto**
```bash
sudo systemctl enable zabbix-agent --now
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload
```

**4. Desplegar Zabbix Server Stack via Docker**
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

**5. Crear archivo de entorno `.env_zabbix`**
```ini
DB_SERVER=zabbix-db
MYSQL_DATABASE=zabbix
MYSQL_USER=zabbix
MYSQL_PASSWORD=zabbix_pwd
MYSQL_ROOT_PASSWORD=root_pwd
ZBX_SERVER_HOST=zabbix-server
PHP_TZ=America/New_York
```

**6. Levantar y Verificar**
```bash
docker compose -f docker-compose.zabbix.yml up -d
```
Acceso: `http://<IP_SERVIDOR>:8080` (Admin / zabbix).
→ Configura el host `SRE-Server-01` en `Configuration` $\rightarrow$ `Hosts` usando el template `Linux by Zabbix agent`.

### 7.4 — Integración Unificada en Grafana

Para tener un "Single Pane of Glass", integramos Zabbix en Grafana.

**1. Instalar Plugin de Zabbix**
```bash
# Busca el ID del contenedor de Grafana
GRAFANA_ID=$(docker ps -qf "name=grafana")
docker exec -it $GRAFANA_ID grafana-cli plugins install alexanderzobnin-zabbix-app
docker restart $GRAFANA_ID
```

**2. Habilitar y Configurar**
- `Administration` $\rightarrow$ `Plugins` $\rightarrow$ `Zabbix` $\rightarrow$ **Enable**.
- `Connections` $\rightarrow$ `Data Sources` $\rightarrow$ `Add data source` $\rightarrow$ `Zabbix`.
- **URL**: `http://<IP_SERVIDOR>:8080/zabbix/api_jsonrpc.php`.
- **User/Pass**: `Admin` / `zabbix`.

### 7.5 — Alertas básicas y Gobernanza (SRE)

**1. Reglas de Alerta en Prometheus**
Crea `/opt/monitoring/alert.rules.yml`:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiscoLleno
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Disco con menos de 15% libre en {{ $labels.instance }}"}
```
Referencia este archivo en `prometheus.yml` y monta el volumen en `docker-compose.monitoring.yml`.

**2. Gobernanza SRE**
- **SLI**: Medida cuantitativa (ej. latencia de API).
- **SLO**: Objetivo sobre SLI (ej. 99.9% de requests < 200ms).
- **SLA**: Acuerdo legal basado en el SLO.
- **Error Budget**: El margen de error permitido antes de detener despliegues para estabilizar el sistema.
- **Incidentes**: Flujo de `Detección` $\rightarrow$ `Mitigación` $\rightarrow$ `Postmortem Blameless`.

---

## 🗺️ Roadmap Sugerido

1. **S1**: Fase 0 (Hardening Rocky/Alma).
2. **S1-2**: Fase 1 (Podman) + Fase 2 (k3s).
3. **S2-3**: Fase 3 (Ansible) $\rightarrow$ Reproducibilidad de setup.
4. **S3**: Fase 4 $\rightarrow$ Migración a Oracle Cloud Always Free.
5. **S4**: Fase 5 $\rightarrow$ CI/CD (GitHub Actions) + ArgoCD.
6. **S4-5**: Fase 6 $\rightarrow$ Auditorías (Lynis, OpenSCAP, kube-bench).
7. **S5-6**: Fase 7 $\rightarrow$ PLG Stack + Definición de SLOs + Postmortem simulado.

---

## 📚 Tabla de Referencias Completas

| Tema | Referencia | URL |
|---|---|---|
| Instalación Rocky | Installing Rocky Linux 9 | https://docs.rockylinux.org/9/guides/9_6_installation/ |
| Instalación Alma | AlmaLinux Installation Guide | https://wiki.almalinux.org/documentation/installation-guide.html |
| SSH hardening | Securing networks — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/securing_networks/assembly_using-secure-communications-between-two-systems-with-openssh_securing-networks |
| Sudo | Managing sudo access — RHEL 9 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/managing-sudo-access_configuring-basic-system-settings |
| dnf-automatic | Patching con dnf-automatic | https://docs.rockylinux.org/10/guides/security/dnf_automatic/ |
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
| k3s arquitectura | k3s Architecture | https://docs.k3s.io/architecture |
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
| GitLab CI | Primer pipeline GitLab CI/CD | https://docs.gitlab.com/ci/quick_start/ |
| ArgoCD | Core Concepts | https://argo-cd.readthedocs.io/en/latest/core_concepts/ |
| Prometheus | Getting Started | https://prometheus.io/docs/prometheus/latest/getting_started/ |
| Grafana | Build your first dashboard | https://grafana.com/docs/grafana/latest/getting-started/build-first-dashboard/ |
| Loki | Get started | https://grafana.com/docs/loki/latest/get-started/ |
| SLO/SLI | Google SRE Book, Cap. 4 | https://sre.google/sre-book/service-level-objectives/ |
| Incidentes | Google SRE Book, Cap. 14 | https://sre.google/sre-book/managing-incidents/ |
| Postmortems | Google SRE Book, Cap. 15 | https://sre.google/sre-book/postmortem-culture/ |

## Ver también
- [[00-MOC-SRE-AS-A-SERVICE]] - MOC Técnico.
