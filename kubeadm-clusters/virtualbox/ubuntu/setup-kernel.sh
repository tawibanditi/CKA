#!/bin/bash
#
# Sets up the kernel with the requirements for running Kubernetes
# Requires a reboot, which is carried out by the vagrant provisioner.
set -ex

# Disable cgroups v2 (kernel command line parameter)
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="systemd.unified_cgroup_hierarchy=0 ipv6.disable=1 /' /etc/default/grub
update-grub

