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
