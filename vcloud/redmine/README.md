# Scalable Redmine Using Bitnami Containers, Kubernetes and VMware vCloud Air

- [Prerequisites](#prerequisites)
    - [VMware vCloud Air](#vmware-vcloud-air)
    - [vCloud Air CLI](#vcloud-air-cli)
- [Create your cluster](#create-your-cluster)
    - [Network Configuration](#network-configuration)
    - [Kubernetes master](#kubernetes-master)
        - [Create `k8s-master` VM](#create-k8s-master-vm)
        - [Allow remote SSH connections (Optional)](#allow-remote-ssh-connections-optional)
        - [Setting up the master node](#setting-up-the-master-node)
    - [Kubernetes Worker](#kubernetes-worker)
        - [Create `k8s-worker-01` VM](#create-k8s-worker-01-vm)
        - [Setting up the worker node](#setting-up-the-worker-node)
- [Download the configuration files](#download-the-configuration-files)
- [Create the Redmine Docker container image](#create-the-redmine-docker-container-image)
- [MariaDB pod and service](#mariadb-pod-and-service)
    - [MariaDB pod](#mariadb-pod)
    - [MariaDB service](#mariadb-service)
- [Redmine pod and service](#redmine-pod-and-service)
    - [Redmine pod](#redmine-pod)
    - [Redmine service](#redmine-service)
- [Allow external traffic](#allow-external-traffic)
- [Access your Redmine server](#access-your-redmine-server)
- [Scaling the Redmine application](#scaling-the-redmine-application)
- [Cleanup](#cleanup)

## Prerequisites

### VMware vCloud Air

Since this tutorial demonstrates using Bitnami containers on VMware vCloud Air using Kubernetes, you will need to [signup](https://signupvcloud.vmware.com/1094/purl-signup) for a vCloud Air account.

Upon signup you will receive $300 or 3 months (whichever comes first) in vCloud Air OnDemand service credits.

#### vCloud Air CLI

Install VMware's [vca-cli](https://github.com/vmware/vca-cli) tool using:

```bash
$ sudo apt-get update
$ sudo apt-get install -y build-essential libffi-dev libssl-dev \
    libxml2-dev libxslt-dev python-dev
$ wget https://bootstrap.pypa.io/get-pip.py
$ sudo python get-pip.py
$ sudo pip install vca-cli
```

Confirm that the tool is installed and working by performing a version check:

```bash
$ vca --version
vca-cli version 14 (pyvcloud: 14)
```

## Create your cluster

Before you get to creating the Kubernetes cluster, we need to login to vCloud Air using the `vca` tool.

```bash
$ vca login user@company.com
```

Now that we are logged in list the available instances using:

```bash
$ vca instance
| Service Group   | Region            | Plan                           | Instance Id                          | Selected   |
|-----------------+-------------------+--------------------------------+--------------------------------------+------------|
| M159692122      | us-virginia-1-4   | Virtual Private Cloud OnDemand | fb35cb94-0a90-42c3-8193-d400ec1f58fb |            |
| M159692122      | jp-japanwest-1-10 | Virtual Private Cloud OnDemand | 596f0a15-e944-40ff-a0ce-65cf5b27851e |            |
| M159692122      | de-germany-1-16   | Virtual Private Cloud OnDemand | 06290eca-4584-4c20-acb2-25126e44be9c |            |
| M159692122      | us-california-1-3 | Virtual Private Cloud OnDemand | 41d63a80-4148-408e-bc7d-0a0c5b87c800 |            |
```

For this tutorial we will use the instance located in Germany, you can choose whichever location is closer to you. If you do not see more than one location then you can enable other locations using the dropdown list in the vCloud Air web interface and then execute the `vca instance` command.

![vcloud-air-locations-dropdown](images/vcloud-air-locations-dropdown.jpg)

> **Note!**: If you face issues following this tutorial, please try switching to a different location.

```bash
$ vca instance use --instance 06290eca-4584-4c20-acb2-25126e44be9c
```

You can list the existing VDC's using:

```bash
$ vca vdc
```

You can use one of the existing VDC's or create a new one. In this tutorial we will create a new VDC named **Kubernetes**.

List all VDC templates using:

```bash
$ vca org list-templates
| Template         |
|------------------|
| VPC Subscription |
| d11p16v3-tp      |
| d11p16v9-tp      |
| dr-d11p16v3-tp   |
```

We will use the `VPC Subscription` template for our new Kubernetes VDC.

```bash
$ vca vdc create --vdc Kubernetes --template 'VPC Subscription'
```

Now we can select the Kubernetes VDC using:

```bash
$ vca vdc use --vdc Kubernetes
```

Check the configuration status using:

```bash
$ vca status
| Key              | Value                                                            |
|------------------+------------------------------------------------------------------|
| vca_cli_version  | 14                                                               |
| pyvcloud_version | 14                                                               |
| profile_file     | /home/user/.vcarc                                                |
| profile          | default                                                          |
| host             | https://vca.vmware.com                                           |
| host_score       | https://score.vca.io                                             |
| user             | user@example.com                                                 |
| instance         | 06290eca-4584-4c20-acb2-25126e44be9c                             |
| org              | 494267b8-b8c2-477a-9f83-3c6121aedb0d                             |
| vdc              | Kubernetes                                                       |
| gateway          | gateway                                                          |
| password         | <encrypted>                                                      |
| type             | vca                                                              |
| version          | 5.7                                                              |
| org_url          | https://de-germany-1-16.vchs.vmware.com/api/compute/api/sessions |
| active session   | True                                                             |
```

> **Note!**: If you are logged out from the `vca` login, you can directly login and start using the Kubernetes cluster using:
>
> ```bash
> $ vca login user@company.com --instance 06290eca-4584-4c20-acb2-25126e44be9c --vdc Kubernetes
> ```

### Network Configuration

Before you start creating virtual machines (VM) for the Kubernetes cluster we need to perform some network configurations to allow outbound network connections from our VM's.

List the existing networks using:

```bash
$ vca network
| Name                   | Mode      | Gateway       | Netmask       | DNS 1   | DNS 2   | Pool IP Range                 |
|------------------------+-----------+---------------+---------------+---------+---------+-------------------------------|
| default-routed-network | natRouted | 192.168.109.1 | 255.255.255.0 |         |         | 192.168.109.2-192.168.109.253 |
```

You will notice that the `default-routed-network` does not have DNS addresses configured. We will delete this network and recreate it specifying Google's public DNS servers.

```bash
$ vca network delete -n default-routed-network && \
  vca network create -n default-routed-network \
    -i 192.168.109.1 -m 255.255.255.0 \
    -1 8.8.8.8 -2 8.8.4.4 \
    -p 192.168.109.2-192.168.109.253
```

Now if you list the existing networks using `vca network`, you will notice that the DNS server address is configured on `default-routed-network`.

Next we assign a public IP address to the gateway interface. This will allow us to access the services (Redmine) running on the cluster over the internet.

```bash
$ vca gateway add-ip
```

To get the details of the gateway:

```bash
$ vca gateway info
| Property         | Value        |
|------------------+--------------|
| Name             | gateway      |
| DCHP Service     | Off          |
| Firewall Service | On           |
| NAT Service      | Off          |
| VPN Service      | Off          |
| Syslog           |              |
| External IP #    | 1            |
| External IPs     | 92.246.241.9 |
| Uplinks          | d11p16v9-ext |
```

Set the value displayed under `External IPs` in a variable named `EXTERNAL_IP`. This is the public IP address of our cluster and will be used while configuring the NAT and Firewall rules as well as to access the applications running on the cluster.

```bash
export EXTERNAL_IP=92.246.241.9
```

For the VM's created in our cluster to be able to access the internet we need to add some NAT and Firewall rules.

The following command adds a SNAT rule:

```bash
$ vca nat add --type snat \
    --original-ip 192.168.109.0/24 --translated-ip $EXTERNAL_IP
```

Next we need to add a Firewall rule. Unfortunately, at the time of writing, this is not possible using the `vca` tool. So we will perform this from vCloud Air's web browser interface.

After logging in to the vCloud Air interface:

1. On the left sidebar, click on the **Kubernetes** VDC
2. Goto **Gateways > Gateway on Kubernetes > Firewall Rules**
3. Click on the **Add Firewall Rule** button

Add a firewall rule named `outbound-ALL` with the `Source` set to `Internal` and `Destination` set as `External`.

![gateway_public_ips_list](images/firewall-outbound-ALL.jpg)

You can list the NAT rules and Firewall rules using `vca nat` and `vca firewall` respectively.

We should now be able to spin up VM's and be assured that they will be able to connect to the internet.

### Kubernetes master

A Kubernetes cluster consists on one master node and zero or more worker nodes. In this section we will setup a master node named `k8s-master`.

#### Create `k8s-master` VM

List the catalog items using:

```bash
$ vca catalog
| Catalog        | Item                                     |
|----------------+------------------------------------------|
| Public Catalog | CentOS63-64BIT                           |
| Public Catalog | W2K12-STD-64BIT                          |
| Public Catalog | CentOS64-64BIT                           |
| Public Catalog | W2K12-STD-R2-64BIT                       |
| Public Catalog | CentOS64-32BIT                           |
| Public Catalog | W2K8-STD-R2-64BIT                        |
| Public Catalog | photon-1.0TP1.iso                        |
| Public Catalog | Ubuntu Server 12.04 LTS (amd64 20150127) |
| Public Catalog | CentOS63-32BIT                           |
| Public Catalog | Ubuntu Server 12.04 LTS (i386 20150127)  |
```

We will be using the `Ubuntu Server 12.04 LTS (amd64 20150127)` VM image from the `Public Catalog` for our master VM.

```bash
$ vca vapp create -a k8s-master-VApp -V k8s-master \
    -c 'Public Catalog' -t 'Ubuntu Server 12.04 LTS (amd64 20150127)' \
    -n default-routed-network -m manual --ip 192.168.109.200 --cpu 2 --ram 4096
```

In this command we are creating a VM named `k8s-master` with the static IP address `192.168.109.200`, `2` vCPUs and `4G` RAM. Feel free to change this as per your requirements. Unfortunately we cannot specify the storage space using `vca` so we will stick with the default `10G` disk space.

Power on the VM using:

```bash
$ vca vapp power-on --vapp k8s-master-VApp
```

Once powered on you can get the VM details such as the `cpu`, `ram`, `admin_password`, etc. using:

```bash
$ vca vapp info -a k8s-master-VApp -V k8s-master
```

To access the console of the VM, in the vCloud Air web interface:

1. On the left sidebar, click on the **Kubernetes** VDC
2. Goto **Virtual Machines > k8s-master > Settings**
3. Click on the **Open Virtual Machine Console** link

Optionally you can enable remote SSH access using instructions listed in the next section.

#### Allow remote SSH connections (Optional)

To enable remote SSH access to the `k8s-master` VM we need to add some NAT and Firewall rules.

Add a DNAT rule using:

```bash
$ vca nat add --type dnat \
    --original-ip $EXTERNAL_IP --original-port 22 \
    --translated-ip 192.168.109.200 --translated-port 22 --protocol tcp
```

To add the firewall rule, as before, we need to do it from the vCloud Air web interface.

1. On the left sidebar, click on the **Kubernetes** VDC
2. Goto **Gateways > Gateway on Kubernetes > Firewall Rules**
3. Click on the **Add** button

Add a firewall rule named `inbound-SSH` with the `Protocol` set to `TCP`, `Source` to `External`, `Source Port` as `Any`, `Destination` set as `Specific CIDR, IP, or IP Range` and specify the public IP address from the `EXTERNAL_IP` variable and finally set the `Destination Port` as `22`.

![firewall-inbound-SSH](images/firewall-inbound-SSH.jpg)

Like before you can list the NAT rules using `vca nat` and the firewall rules using `vca firewall`.

With this configuration, you should now be able to login to the **k8s-master** VM using an SSH client.

```bash
$ ssh $EXTERNAL_IP -l root
```

Login using the `admin_password` displayed in the output of the `vca vapp info -a k8s-master-VApp -V k8s-master` command.

#### Setting up the master node

Begin by updating the system packages.

```bash
$ apt-get update && apt-get -y upgrade
```

*It recommended that you reboot the VM after updating the system*

Next install Docker

```bash
$ curl -sSL https://get.docker.com/ | sh
```

Set `K8S_VERSION` to the most recent Kubernetes [release](https://github.com/kubernetes/kubernetes/releases) and install `kubectl` using:

```bash
$ export K8S_VERSION=1.0.3 && \
  wget https://github.com/kubernetes/kubernetes/releases/download/v${K8S_VERSION}/kubernetes.tar.gz && \
  tar xf kubernetes.tar.gz && \
  cp kubernetes/platforms/linux/$(dpkg --print-architecture)/kubectl /usr/local/bin && \
  chmod +x /usr/local/bin/kubectl
```

Finally we setup the VM to be the master node of the Kubernetes cluster.

```bash
$ wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/master.sh && \
  chmod +x master.sh && ./master.sh
```

This process will take a while to complete at the end of which we should have a working Kubernetes master node.

### Kubernetes Worker

#### Create `k8s-worker-01` VM

```bash
$ vca vapp create -a k8s-worker-01-VApp -V k8s-worker-01 \
    -c 'Public Catalog' -t 'Ubuntu Server 12.04 LTS (amd64 20150127)' -n default-routed-network \
    -m manual --ip 192.168.109.201 --cpu 2 --ram 4096
```

In this command we are creating a VM named `k8s-worker-01` with the static IP address `192.168.109.201`, `2` vCPUs and `4G` RAM.

Power on the VM using:

```bash
$ vca vapp power-on --vapp k8s-worker-01-VApp
```

Once powered on you can get the VM details such as the `cpu`, `ram`, `admin_password`, etc. using:

```bash
$ vca vapp info -a k8s-worker-01-VApp -V k8s-worker-01
```

To access the console of the VM, in the vCloud Air web interface:

1. On the left sidebar, click on the **Kubernetes** VDC
2. Goto **Virtual Machines > k8s-worker-01 > Settings**
3. Click on the **Open Virtual Machine Console** link

If you have enabled remote SSH access to the `k8s-master` VM, then you can SSH into `k8s-worker-01` from `k8s-master` using:

```bash
$ ssh $EXTERNAL_IP -tl root ssh 192.168.109.201 -l root
```

#### Setting up the worker node

Login to the worker node and begin by updating the system packages.

```bash
$ apt-get update && apt-get -y upgrade
```

*It recommended that you reboot the VM after updating the system*

Next we install Docker, followed by the Kubernetes `kubectl` command.

```bash
$ curl -sSL https://get.docker.com/ | sh
```

Set `K8S_VERSION` to the most recent Kubernetes [release](https://github.com/kubernetes/kubernetes/releases) and install `kubectl` using:

```bash
$ export K8S_VERSION=1.0.3 && \
  wget https://github.com/kubernetes/kubernetes/releases/download/v${K8S_VERSION}/kubernetes.tar.gz && \
  tar xf kubernetes.tar.gz && \
  cp kubernetes/platforms/linux/$(dpkg --print-architecture)/kubectl /usr/local/bin && \
  chmod +x /usr/local/bin/kubectl
```

Finally we setup the VM as a worker node of the Kubernetes cluster. First set the `MASTER_IP` environment variable to the IP address of the **ks8-master** VM and setup the worker.

```bash
$ export MASTER_IP=192.168.109.200 && \
  wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/worker.sh && \
  chmod +x worker.sh && ./worker.sh
```

Like the master node setup, the this process will take a while to complete at the end of which the worker should be ready.

You can repeat these instructions in [Kubernetes Worker](#kubernetes-worker) to add more worker nodes if you wish to. Remember to change the name and IP address while adding new VM's to the cluster.

### Deploy DNS

To complete the setup of our Kubernetes cluster we need to deploy a DNS. These instructions can be executed on the master node or any of the worker nodes.

First, download the configuration templates.

```bash
$ wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-rc.yaml.in && \
  wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/docs/getting-started-guides/docker-multinode/skydns-svc.yaml.in
```

Next, we need to configure some environment variables, namely `DNS_REPLICAS` , `DNS_DOMAIN` , `DNS_SERVER_IP` , `KUBE_SERVER`. Set the `KUBE_SERVER` variable to the IP address of the **k8s-master** VM.

```bash
$ export DNS_REPLICAS=1 && \
  export DNS_DOMAIN=cluster.local && \
  export DNS_SERVER_IP=10.0.0.10 && \
  export KUBE_SERVER=192.168.109.200
```

Next we generate the configuration using the templates and the above configuration.

```bash
$ sed -e "s/{{ pillar\['dns_replicas'\] }}/${DNS_REPLICAS}/g;s/{{ pillar\['dns_domain'\] }}/${DNS_DOMAIN}/g;s/{kube_server_url}/${KUBE_SERVER}/g;" skydns-rc.yaml.in > ./skydns-rc.yaml && \
  sed -e "s/{{ pillar\['dns_server'\] }}/${DNS_SERVER_IP}/g" skydns-svc.yaml.in > ./skydns-svc.yaml
```

Now use `kubectl` to create the `skydns` replication controller.

```bash
$ kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system create -f ./skydns-rc.yaml
```

Wait for the pods to enter the `Running` state.

```bash
$ kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system get pods
NAME                READY     STATUS    RESTARTS   AGE
kube-dns-v8-rh7lz   4/4       Running   0          2m
```

Once the pods are in the `Running` state, create the `skydns` service using `kubectl`.

```bash
$ kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system create -f ./skydns-svc.yaml
```

See it running:

```bash
$ kubectl -s "$KUBE_SERVER:8080" --namespace=kube-system get services
NAME       LABELS                                                                           SELECTOR           IP(S)       PORT(S)
kube-dns   k8s-app=kube-dns,kubernetes.io/cluster-service=true,kubernetes.io/name=KubeDNS   k8s-app=kube-dns   10.0.0.10   53/UDP
                                                                                                                           53/TCP
```

Lets perform a basic check to see if the Kubernetes cluster has been setup correctly.

```bash
$ kubectl -s "$KUBE_SERVER:8080" get nodes
NAME        LABELS                             STATUS
127.0.0.1   kubernetes.io/hostname=127.0.0.1   Ready
127.0.1.1   kubernetes.io/hostname=127.0.1.1   Ready
```

And there you have it, a Kubernetes cluster running on vCloud Air. You can run further tests on your cluster using these instructions: https://github.com/kubernetes/kubernetes/blob/master/docs/getting-started-guides/docker-multinode/testing.md

> **Note!** *From this point on, all `kubectl` commands will be executed in the `k8s-master` nodes console.*

### Download the configuration files

Clone the [bitnami-docker](https://github.com/bitnami/bitnami-docker) GitHub repository:

```bash
$ git clone https://github.com/bitnami/bitnami-docker.git
```

The files used in this tutorial can be found in the `vcloud/redmine` directory of the cloned repository:

- dockerfiles/redmine/Dockerfile
- dockerfiles/redmine/run.sh
- redmine-controller.yml
- redmine-service.yml
- mariadb-controller.yml
- mariadb-service.yml

```bash
$ cd bitnami-docker/vcloud/redmine/
```

## Create the Redmine Docker container image

The Redmine image is built using the `Dockerfile` and `run.sh` script from the `dockerfiles/redmine/` directory. Docker container images can extend from other existing images so for this image, we'll extend from the existing `bitnami/ruby` image.

The `Dockerfile` imports the correct Redmine source code and a `run.sh` script.

The `run.sh` script uses the MariaDB connection information exposed by docker links and automatically configures the Redmine database connection parameters.

Build the Redmine image by running:

```bash
$ cd dockerfiles/redmine/
$ docker build -t <dockerhub-account-name>/redmine .
```

Then push this image to the Docker Hub Registry:

```bash
$ docker push <dockerhub-account-name>/redmine
```

## MariaDB pod and service

### MariaDB pod

The first thing that we're going to do is start a [pod](http://kubernetes.io/v1.0/docs/user-guide/pods.html) for MariaDB. We'll use a [replication controller](http://kubernetes.io/v1.0/docs/user-guide/replication-controller.html) to create the pod—even though it's a single pod, the controller is still useful for monitoring health and restarting the pod if required.

We'll use the config file `mariadb-controller.yml` for the database pod. The pod definition creates a single MariaDB pod.

> **Note**": You should change the value of the `MARIADB_PASSWORD` env variable to one of your choosing.

To create the pod:

```bash
$ kubectl create -f mariadb-controller.yml
```

Check to see if the pod is running. It may take a minute to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=mariadb
NAME            READY     STATUS    RESTARTS   AGE
mariadb-izq2p   1/1       Running   0          5m
```

### MariaDB service

A [service](http://kubernetes.io/v1.0/docs/user-guide/services.html) is an abstraction which defines a logical set of pods and a policy by which to access them. It is effectively a named load balancer that proxies traffic to one or more pods.

When you set up a service, you tell it the pods to proxy based on pod labels. Note that the pod that you created in step one has the label `name=mariadb`.

We'll use the file `mariadb-service.yml` to create a service for MariaDB:

The `selector` field of the service configuration determines which pods will receive the traffic sent to the service. So, the configuration is specifying that we want this service to point to pods labeled with `name=mariadb`.

Start the service:

```bash
$ kubectl create -f mariadb-service.yml
```

See it running:

```bash
$ kubectl get services mariadb
NAME      LABELS         SELECTOR       IP(S)        PORT(S)
mariadb   name=mariadb   name=mariadb   10.0.0.143   3306/TCP
```

## Redmine pod and service

Now that you have the database up and running, lets set up the Redmine web servers.

### Redmine pod

The controller and its pod template is described in the file `redmine-controller.yml`.

> **Note**:
> 1. Change the image name to `<dockerhub-account-name>/redmine` as per the build instructions in [Create a Docker container image](#create-a-docker-container-image).
> 2. Update the values of `REDMINE_SESSION_TOKEN` and `DATABASE_PASSWORD`.

It specifies 3 replicas of the server. Using this file, you can start your Redmine servers with:

```bash
$ kubectl create -f redmine-controller.yml
```

Check to see if the pods are running. It may take a few minutes to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=redmine
NAME            READY     STATUS    RESTARTS   AGE
redmine-8qqfv   1/1       Running   0          5m
redmine-tc4oi   1/1       Running   0          5m
redmine-xj3mh   1/1       Running   0          5m
```

Once the servers are up, you can list the pods in the cluster, to verify that they're all running:

```bash
$ kubectl get pods
NAME                   READY     STATUS    RESTARTS   AGE
k8s-master-127.0.0.1   3/3       Running   0          1d
mariadb-izq2p          1/1       Running   0          32m
redmine-8qqfv          1/1       Running   0          6m
redmine-tc4oi          1/1       Running   0          6m
redmine-xj3mh          1/1       Running   0          6m
```

You'll see a single MariaDB pod and three Redmine pods and some infrastructure pods. In [Scaling the Redmine application](#scaling-the-redmine-application) we will see how we can scale the Redmine pods.

### Redmine service

As with the MariaDB pod, we want a service to group the Redmine server pods. However, this time it's different: this service is user-facing, so we want it to be externally visible. That is, we want a client to be able to request the service from outside the cluster. To accomplish this, we can set the `type: NodePort` field and specify `nodePort: 30000` in the service configuration.

The service specification for the Redmine is in `redmine-service.yml`.

```bash
$ kubectl create -f redmine-service.yml
```

See it running:

```bash
$ kubectl get services redmine
NAME      LABELS         SELECTOR       IP(S)        PORT(S)
redmine   name=redmine   name=redmine   10.0.0.226   80/TCP
```

## Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Redmine service accessible from the Internet we have to open port 80 and forward it to port `30000` (`nodePort`) of our master node.

For this we need to add some NAT and Firewall rules. To add the NAT rule:

```bash
$ vca nat add --type dnat \
    --original-ip $EXTERNAL_IP --original-port 80 \
    --translated-ip 192.168.109.200 --translated-port 30000 --protocol tcp
```

To add the firewall rule, again, we need to do it from the vCloud Air web interface.

1. On the left sidebar, click on the **Kubernetes** VDC
2. Goto **Gateways > Gateway on Kubernetes > Firewall Rules**
3. Click on the **Add** button

Add a firewall rule named `inbound-HTTP` with the `Protocol` set to `TCP`, `Source` to `External`, `Source Port` as `Any`, `Destination` set as `Specific CIDR, IP, or IP Range` and specify the public IP address from the `EXTERNAL_IP` variable and finally set the `Destination Port` as `80`.

![firewall-inbound-HTTP](images/firewall-inbound-HTTP.jpg)

## Access your Redmine server

Now that the firewall is open, you can access the service using the public IP address (`EXTERNAL_IP`) of your gateway. Visit `http://x.x.x.x` where `x.x.x.x` is the public IP address of the gateway from the [Network Configuration](#network-configuration) section.

## Scaling the Redmine application

Since the Redmine pod is defined as a service that uses a replication controller, you can easily resize the number of pods in the replication controller as follows:

```bash
$ kubectl scale --replicas=5 rc redmine
```

The configuration for the redmine controller will be updated, to specify that there should be 5 replicas running. The replication controller adjusts the number of pods it is running to match that, and you will be able to see the additional pods running:

```bash
$ kubectl get pods -l name=redmine
NAME            READY     STATUS    RESTARTS   AGE
redmine-8qqfv   1/1       Running   0          1h
redmine-lrvbu   1/1       Running   0          22s
redmine-tc4oi   1/1       Running   0          1h
redmine-w34sq   1/1       Running   0          22s
redmine-xj3mh   1/1       Running   0          1h
```

You can scale down the number of Redmine pods in the same manner.

## Cleanup

To delete your application completely:

*If you intend to teardown the entire cluster then jump to Step 3.*

1. Delete the services:

    ```bash
    $ kubectl delete service redmine
    $ kubectl delete service mariadb
    ```

2. Delete the controllers:

    ```bash
    $ kubectl delete rc redmine
    $ kubectl delete rc mariadb
    ```

3. Delete the Kubernetes VDC:

    ```bash
    $ vca vdc delete --vdc Kubernetes
    ```

