# Scalable Redmine Using Bitnami Containers, Kubernetes and VMware vCloud Air

## Prerequisites

### VMware vCloud Air

Signup for a [VMware vCloud Air](https://signupvcloud.vmware.com/1094/purl-signup).

### Download the configuration files

Clone the [bitnami-docker](https://github.com/bitnami/bitnami-docker) GitHub repository:

```bash
git clone https://github.com/bitnami/bitnami-docker.git
```

The files used in this tutorial can be found in the `vcloud/redmine` directory of the cloned repository:

  - Dockerfile
  - run.sh
  - redmine-secrets.yml
  - redmine-controller.yml
  - redmine-service.yml
  - mariadb-controller.yml
  - mariadb-service.yml


## Setting up a Kubernetes cluster on vCloud Air

In this section we will talk through setting up a Kubernetes cluster on vCloud Air.

Lets begin by logging in to our vCloud Air account.

![login_welcome](images/01_login_welcome.jpg)

### Network Configuration

Before we start creating virtual machines (VM) for the Kubernetes cluster, we need to perform some network configurations to allow oubound network connections from our VM's.

We begin by assigning a public IP address to the gateway interface. This will allow us to access the services running on the cluster over the internet.

Browse to the **Gateways** tab and select the listed gateway interface.

![gateways](images/02_gateways.jpg)

Next, select the **Public IPs** tab and click the **Add IP Address** button to add a public IP address.

![gateway_public_ips_add](images/03_gateway_public_ips_add.jpg)

The public IP address will now be listed. Copy the displayed IP address as it will be used in the following sections.

![gateway_public_ips_list](images/04_gateway_public_ips_list.jpg)

Next we will add a Source NAT (SNAT) rule. Select the **NAT Rules** tab and add a new SNAT rule as displayed in the below screenshot.

> **Note!**: The IP address entered in the **Translated (External) Source** is the public IP address of our Gateway.

![gateway_nat_add_SNAT](images/05_gateway_nat_add_SNAT.jpg)

Next, we need to add a firewall rule to allow outgoing network connections from our virtual machines.

Select the **Firewall Rules** tab and add a new rule named **outbound-ALL** as shown in the screenshot below.

![gateway_firewall_add](images/07_gateway_firewall_add-outbound-ALL.jpg)

Optionally, we can add an **inbound-ICMP** rule as shown below. This will allow us to ping the gateway.

![gateway_firewall_add](images/08_gateway_firewall_add-inbound-ICMP.jpg)

After performing the above firewall configurations the firewall rules will look something like this.

![gateway_firewall_list](images/09_gateway_firewall_list.jpg)

To complete our network configuration, we need to configure the DNS addresses that will be configured on the VM's.

Select the **Networks** tab and click the **Manage in vCloud Director** link. vCloud Director will open in a new browser tab.

![networks](images/10_networks.jpg)

*Please note that vCloud Director requires the Adobe Flash web-browser plugin*

In vCloud Director select the **default-routed-network** and load the **Properties** dialog as displayed in the screenshot below.

![network_properties](images/11_network_properties.jpg)

Under the DNS settings enter the address of the DNS server you want to use and apply the changes. In this tutorial we use Google's Public DNS servers `8.8.8.8` and `8.8.4.4`.

![network_configure_dns](images/12_network_configure_dns.jpg)

And we are done with the network configuration. In the following sections we will setup the Kubernetes master and worker nodes.

### Kubernetes master

A Kubernetes cluster consists on one master node and one or more worker nodes. In this section we will create a virtual machine for the master node.

#### Create virtual machine

Begin by creating a new virtual machine.

![vm_create_k8s](images/13_vm_create_k8s-master.jpg)

Select the **Ubuntu 12.04 Server AMD64** virtual machine template from the VMware Catalog.

![vm_select_k8s](images/14_vm_select_k8s-master_image.jpg)

Name the virtual machine **k8s-master** and assign the desired system resources to the VM and create the virtual machine.

![vm_select_k8s](images/15_vm_select_k8s-master_resources.jpg)

A VM named **ks8-master** should now be listed under the **Virtual Machines** tab and should enter the powered on state in a couple of minutes.

![vm_k8s](images/16_vm_k8s-master.jpg)

Select the VM to view its settings and properties.

Under the **Networks** tab you will find the IP address of the virtual machine. Please note it down as it will be required later.

![vm_networks](images/17_vm_networks.jpg)

Under the **Settings** tab you will find the **Guest OS Password** and also a link to **Open Virtual Machine Console**. Click this link to open a console session to the VM. Upon login as `root` user, you will be required change the default password.

![vm_settings](images/18_vm_settings.jpg)

#### Allow remote SSH connections (Optional)

Optionally we can update the network configuration to allow incoming SSH connections to our **k8s-master** VM.

Add a new **DNAT** rule under the **Gateway > NAT** section as shown below. Set the **Original (External) IP** to the public IP address of the gateway and the **Translated (Internal) IP/Range** to the IP address of the VM.

![gateway_nat_add_DNAT](images/19_gateway_nat_add_DNAT.jpg)

After performing the above NAT configuration the NAT Rules will look something like this.

![gateway_nat_list](images/20_gateway_nat_list.jpg)

Next, we need to add a firewall rule to allow inbound SSH connections to the **k8s-master** VM.

![gateway_firewall_add](images/21_gateway_firewall_add-inbound-SSH.jpg)

After performing the above firewall configurations the firewall rules will look something like this.

![gateway_firewall_list](images/22_gateway_firewall_list.jpg)

With this configuration, you should now be able to login to the **ks-master** VM using an SSH client.

#### Setting up the master node

Begin by updating the system packages.

```bash
apt-get update && apt-get -y upgrade
```

*It recommended that you reboot the VM after updating the system*

Next we install Docker, followed by the Kubernetes `kubectl` command.

```bash
curl -sSL https://get.docker.com/ | sh
```

Set `K8S_VERSION` to the most recent Kubernetes release

```bash
export K8S_VERSION=1.0.3
```

Install the `kubectl` command.

```bash
wget https://github.com/kubernetes/kubernetes/releases/download/v${K8S_VERSION}/kubernetes.tar.gz
tar xf kubernetes.tar.gz
cp kubernetes/platforms/linux/$(dpkg --print-architecture)/kubectl /usr/local/bin
chmod +x /usr/local/bin/kubectl
```

Finally we setup the VM to be the master node of the Kubernetes cluster.

```bash
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/master.sh
chmod +x master.sh
./master.sh
```

This process will take a while to complete at the end of which we should have a working Kubernetes master node.

While the node is being setup, you can go ahead and setup one or more worker nodes.

### Kubernetes Worker

#### Create virtual machine

Similar to creating a VM for the master node, we create a VM for the worker node.

![vm_ks8-worker](images/23_vm_ks8-worker.jpg)

Name the virtual machine **k8s-worker-01** and assign the desired system resources to the VM and create the virtual machine.

A VM named **ks8-worker-01** should now be listed under the **Virtual Machines** tab and should enter the powered on state in a couple of minutes.

#### Setting up the worker node

Login to the worker node and begin by updating the system packages.

```bash
apt-get update && apt-get -y upgrade
```

*It recommended that you reboot the VM after updating the system*

Next we install Docker, followed by the Kubernetes `kubectl` command.

```bash
curl -sSL https://get.docker.com/ | sh
```

Set `K8S_VERSION` to the most recent Kubernetes release

```bash
export K8S_VERSION=1.0.3
```

Install the `kubectl` command.

```bash
wget https://github.com/kubernetes/kubernetes/releases/download/v${K8S_VERSION}/kubernetes.tar.gz
tar xf kubernetes.tar.gz
cp kubernetes/platforms/linux/$(dpkg --print-architecture)/kubectl /usr/local/bin
chmod +x /usr/local/bin/kubectl
```

Finally we setup the VM as a worker node of the Kubernetes cluster. First set the `MASTER_IP` environment variable to the IP address of the **ks8-master** VM.

```bash
export MASTER_IP=192.168.109.2
```

And begin the install.

```bash
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/worker.sh
chmod +x worker.sh
./worker.sh
```

Like the master node setup, the this process will take a while to complete at the end of which the worker should be ready.

You can repeat the instructions in [Kubernetes Worker](#kubernetes-worker) to add more worker nodes if you wish to.

### Deploy DNS

To complete the setup of our Kubernetes cluster we need to deploy a DNS. These instructions can be executed on the master node or any of the worker nodes.

First, download the configuration templates.

```bash
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-rc.yaml.in
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-svc.yaml.in
```

Next, we need to configure some environment variables, namely `DNS_REPLICAS` , `DNS_DOMAIN` , `DNS_SERVER_IP` , `KUBE_SERVER`. Set the `KUBE_SERVER` variable to the IP address of the **k8s-master** VM.

```bash
export DNS_REPLICAS=1
export DNS_DOMAIN=cluster.local
export DNS_SERVER_IP=10.0.0.10
export KUBE_SERVER=192.168.109.2
```

Next we generate the configuration using the templates and the above configuration.

```bash
sed -e "s/{{ pillar\['dns_replicas'\] }}/${DNS_REPLICAS}/g;s/{{ pillar\['dns_domain'\] }}/${DNS_DOMAIN}/g;s/{kube_server_url}/${KUBE_SERVER}/g;" skydns-rc.yaml.in > ./skydns-rc.yaml
sed -e "s/{{ pillar\['dns_server'\] }}/${DNS_SERVER_IP}/g" skydns-svc.yaml.in > ./skydns-svc.yaml
```

Now use `kubectl` to create the `skydns` replication controller.

```bash
kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system create -f ./skydns-rc.yaml
```

Wait for the pods to enter the `Running` state.

```bash
kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system get pods
NAME                READY     STATUS    RESTARTS   AGE
kube-dns-v8-rh7lz   4/4       Running   0          2m
```

Once the pods are in the `Running` state, create the `skydns` service using `kubectl`.

```bash
kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system create -f ./skydns-svc.yaml
```
