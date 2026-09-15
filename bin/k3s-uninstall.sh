#!/bin/sh
set -x
[ $(id -u) -eq 0 ] || exec sudo --preserve-env=K3S_DATA_DIR $0 $@

K3S_DATA_DIR=${K3S_DATA_DIR:-/var/lib/rancher/k3s}

/usr/local/bin/k3s-killall.sh

if command -v systemctl; then
    systemctl disable k3s
    systemctl reset-failed k3s
    systemctl daemon-reload
fi
if command -v rc-update; then
    rc-update delete k3s default
fi

rm -f /etc/systemd/system/k3s.service
rm -f /etc/systemd/system/k3s.service.env

remove_uninstall() {
    rm -f /usr/local/bin/k3s-uninstall.sh
}
trap remove_uninstall EXIT

if (ls /etc/systemd/system/k3s*.service || ls /etc/init.d/k3s*) >/dev/null 2>&1; then
    set +x; echo 'Additional k3s services installed, skipping uninstall of k3s'; set -x
    exit
fi

for cmd in kubectl crictl ctr; do
    if [ -L /usr/local/bin/$cmd ]; then
        rm -f /usr/local/bin/$cmd
    fi
done

clean_mounted_directory() {
    if ! grep -q " $1" /proc/mounts; then
        rm -rf "$1"
	return 0
    fi

    for path in "$1"/*; do
        if [ -d "$path" ]; then
            if grep -q " $path" /proc/mounts; then
                clean_mounted_directory "$path"
            else
                rm -rf "$path"
            fi
        else
            rm "$path"
        fi
     done
}

rm -rf /etc/rancher/k3s
rm -rf /run/k3s
rm -rf /run/flannel
clean_mounted_directory ${K3S_DATA_DIR}
rm -rf /var/lib/kubelet
rm -f /usr/local/bin/k3s
rm -f /usr/local/bin/k3s-killall.sh

# uninstall k3s-selinux package if a compatible package manager is found
zypper_remove_selinux_rpm() {
    uninstall_cmd="zypper remove -y k3s-selinux"
    if [ "${TRANSACTIONAL_UPDATE=false}" != "true" ] && [ -x /usr/sbin/transactional-update ]; then
        uninstall_cmd="transactional-update --no-selfupdate -d run $uninstall_cmd"
    fi
    $uninstall_cmd
}
dnf_remove_selinux_rpm() {
    package_manager=dnf
    # yum is only needed for rhel 7, which is EOM since 2024 anyway
    if ! type dnf >/dev/null 2>&1; then
        package_manager=yum
    fi
    $package_manager remove -y k3s-selinux
}
rpm_ostree_uninstall_cmd="rpm-ostree uninstall --idempotent k3s-selinux"

# shellcheck source=/dev/null
[ -r /etc/os-release ] && . /etc/os-release

if [ "$(expr "${ID_LIKE}" : ".*suse.*")" != 0 ]; then
    zypper_remove_selinux_rpm
# cover any standard & atomic rhel/centos/fedora + derivatives like amazon linux
elif [ "${ID:-}" = fedora ] || [ "$(expr "${ID_LIKE}" : ".*fedora.*\|.*rhel.*\|.*centos.*")" != 0 ]; then
    if [ -n "${OSTREE_VERSION:-}" ]; then
        $rpm_ostree_uninstall_cmd
    else
        dnf_remove_selinux_rpm
    fi
# if we did not match yet just check for package managers commonly found on selinux-enabled distributions
elif type rpm-ostree >/dev/null 2>&1; then
    $rpm_ostree_uninstall_cmd
elif type zypper >/dev/null 2>&1; then
    zypper_remove_selinux_rpm
elif type yum >/dev/null 2>&1; then
    dnf_remove_selinux_rpm
elif [ -d /usr/share/selinux ]; then
    echo '[WARN] Automatic removal of "k3s-selinux" package not possible, please remove it manually.' >&2
fi

if [ -d /etc/zypp/repos.d ]; then
    rm -f /etc/zypp/repos.d/rancher-k3s-common*.repo
elif [ -d /etc/yum.repos.d ]; then
    rm -f /etc/yum.repos.d/rancher-k3s-common*.repo
fi
