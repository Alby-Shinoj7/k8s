# Kubernetes Cluster Setup Tool

This repository provides a modular bash tool to automate installation of a simple Kubernetes cluster on Ubuntu 22.04+ servers. Edit the `.env` file with your node information and run commands via `k8s-tool.sh` as root.

## Directory Structure

- `k8s-tool.sh` – command line wrapper
- `modules/` – individual scripts
  - `control_plane.sh` – installs control plane
  - `worker_node.sh` – installs worker components and joins cluster
  - `gpu_enable.sh` – enables NVIDIA GPU support
  - `validate_env.sh` – validates server environment
- `.env` – sample file with IPs and hostnames

## Usage

1. Copy `.env` to each node and edit IPs and hostnames accordingly.
2. On all nodes run:

```bash
sudo ./k8s-tool.sh validate
```

3. On the control plane node run:

```bash
sudo ./k8s-tool.sh control-plane
```

4. Record the token and CA hash output by `kubeadm init` and export as environment variables on worker nodes:

```bash
export KUBEADM_TOKEN=<token>
export KUBEADM_CA_HASH=<hash>
```

5. On each worker node run:

```bash
sudo ./k8s-tool.sh join-workers
```

6. To install Calico CNI after the control plane is ready run on the control plane:

```bash
sudo ./k8s-tool.sh install-cni
```

7. Enable GPU support on worker nodes if needed:

```bash
sudo ./k8s-tool.sh enable-gpu
```

8. Validate node status:

```bash
sudo ./k8s-tool.sh validate
```

This tool is idempotent and designed to follow enterprise best practices such as disabling swap, configuring sysctl, ensuring containerd uses systemd cgroups and verifying environment readiness before proceeding.

