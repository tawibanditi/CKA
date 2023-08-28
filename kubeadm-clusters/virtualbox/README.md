# Kubeadm on VirtualBox

This guide shows how to install a 3 node kubeadm cluster on VirtualBox. **Note that this currently does not work with Apple M1/M2**. We have an alternative option for these machines [here](../apple-silicon/). If you have an older Intel Mac, then this should still work.

* Instance type: `t3.medium`
* Operating System: Ubuntu 22.04 (at time of writing)
* Storage: `gp2`, 8GB

Note that this is an exercise in simply getting a cluster running and is a learning exercise only! It will not be suitable for serving workloads to the internet, nor will it be properly secured, otherwise this guide would be three times longer! It should not be used as a basis for building a production cluster.

## Prerequisites

* [Vagrant](https://developer.hashicorp.com/vagrant/downloads?product_intent=vagrant)
    1. For macOS, the easiest way is to use homebrew as indicated.
    1. For Windows, select `AMD64` and download the Windows Installer file, then double-click the file to run Setup.
        * If you have the [chocolately](https://chocolatey.org/) package manager, simply run `choco install -y vagrant` As Administrator.
        * If you don't, you really should consider [installing it](https://chocolatey.org/install).
* [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
    * Either download and install manually for your operating system, or
    * Windows (with [chocolatey](https://chocolatey.org/install)), As Administrator
        ```
        choco install -y virtualbox
        ```
    * Mac (homebrew)
        ```
        brew install --cask virtualbox
        ```



## Provision the infrastructure

This lab was tested using the following versions

* VirtualBox - 7.0.10
* Vagrant - 2.3.7

We will provision the following infrastructure.

* `kubemaster` - Control plane node. 2CPU, 2GB RAM
* `kubenode01` - Worker node. 2CPU, 2GB RAM
* `kubenode02` - Worker node. 2CPU, 2GB RAM

## Configure Operating System, Container Runtime and Kube Packages

Repeat the following steps on `kubemaster`, `kubenode01` and `kubenode02` by running `vagrant ssh` to each node, e.g. 

```
vagrant ssh kubemaster
```

Note that if you see this error on Windows:

```
vagrant@127.0.0.1: Permission denied (publickey).
```

Then do the following, depending on which shell you are using

* Windows command prompt: `set VAGRANT_PREFER_SYSTEM_BIN=0`
* PowerShell prompt: `$Env:VAGRANT_PREFER_SYSTEM_BIN += 0`

1. Become root (saves typing `sudo` before every command)
    ```bash
    sudo -i
    ```
1. Update the apt package index and install packages needed to use the Kubernetes apt repository:
    ```bash
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    ```
1. Set up the required kernel modules and make them persistent
    ```bash
    cat <<EOF > /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF

    modprobe overlay
    modprobe br_netfilter
    ```
1.  Set the required kernel parameters and make them persistent
    ```bash
    cat <<EOF > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF

    sysctl --system
    ```
1. Install the container runtime
    ```bash
    apt-get install -y containerd
    ```
1.  Configure the container runtime to use CGroups. This part is the bit many students miss, and if not done results in a kubemaster that comes up, then all the pods start crashlooping.

    1. Create default configuration

        ```bash
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        ```
    1. Edit the configuration to set up CGroups

        ```
        vi /etc/containerd/config.toml
        ```

        Scroll down till you find a line with `SystemdCgroup = false`. Edit it to be `SystemdCgroup = true`, then save and exit vi

    1.  Restart containerd

        ```bash
        systemctl restart containerd
        ```

1. Download the Google Cloud public signing key
    ```bash
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    ```

1. Add the Kubernetes apt repository
    ```bash
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    ```

1. Update apt package index, install kubelet, kubeadm and kubectl, and pin their version
    ```bash
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    ```

1.  Configure `crictl` in case we need it to examine running containers
    ```bash
    crictl config \
        --set runtime-endpoint=unix:///run/containerd/containerd.sock \
        --set image-endpoint=unix:///run/containerd/containerd.sock
    ```

1. Exit root shell
    ```bash
    exit
    ```

1.  Return to `student-node`

    ```bash
    exit
    ```

    Repeat the above till you have done `kubemaster`, `kubenode01` and  `kubenode02`

## Boot up kubemaster

1.  ssh to `kubemaster`

    ```bash
    ssh kubemaster
    ```

1. Become root
    ```bash
    sudo -i
    ```

1. Boot the control plane
    ```bash
    kubeadm init
    ```

    Copy the join command that is printed to a notepad for use on the worker nodes.

1. Install network plugin (weave)
    ```bash
    kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml"
    ```

1.  Check we are up and running

    ```bash
    kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -n kube-system
    ```

1.  Exit root shell

    ```bash
    exit
    ```

1.  Prepare the kubeconfig file for copying to `student-node`

    ```bash
    {
    sudo cp /etc/kubernetes/admin.conf .
    sudo chown ubuntu:ubuntu admin.conf
    }
    ```

1.  Exit to student node

    ```bash
    exit
    ```

1.  Copy kubeconfig down from `kubemaster` to `student-node`

    ```
    mkdir ~/.kube
    scp kubemaster:~/admin.conf ~/.kube/config
    ```

1.  Test it

    ```
    kubectl get pods -n kube-system
    ```

## Join the worker nodes

1.  SSH to `kubenode01`
1.  Become root

    ```bash
    sudo -i
    ```

1. Paste the join command that was output by `kubeadm init` on `kubemaster`

1. Return to `student-node`

    ```
    exit
    exit
    ```

1. Repeat the steps 2, 3 and 4 on `kubenode02`

1. Now you should be back on `student-node`. Check all nodes are up

    ```bash
    kubectl get nodes -o wide
    ```

## Create a test service

Run the following on `student-node`

1. Deploy and expose an nginx pod

    ```bash
    kubectl run nginx --image nginx --expose --port 80
    ```

1. Convert the service to NodePort

    ```bash
    kubectl edit service nginx
    ```

    Edit the `spec:` part of the service until it looks like this. Don't change anything above `spec:`

    ```yaml
    spec:
      ports:
      - port: 80
        protocol: TCP
        targetPort: 80
        nodePort: 30080
      selector:
        run: nginx
      sessionAffinity: None
      type: NodePort
    ```

1.  Test with curl

    1. Get the _internal_ IP of one of the nodes

        ```bash
        kubectl get node kubenode01 -o wide
        ```

        This will output the following (INTERNAL-IP will be different for you)

        ```
        NAME     STATUS   ROLES    AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION    CONTAINER-RUNTIME
        kubenode01   Ready    <none>   13m   v1.27.4   172.31.26.150   <none>        Ubuntu 22.04.2 LTS   5.19.0-1028-aws   containerd://1.6.12
        ```

    1. Using the INTERNAL-IP and the nodePort value set on the service, form a `curl` command. The IP will be different to what is shown here.

        ```bash
        curl http://172.31.26.150:30080
        ```

1.  Test from your own browser

    1. Get the _public_ IP of one of the nodes. These were output by Terraform. You can also find this by looking at the instances on the EC2 page of the AWS console.

    1. Using the public IP and the nodePort value set on the service, form a URL to paste into your browser. The IP will be different to what is shown here.

        ```
        http://18.205.245.169:30080/
        ```