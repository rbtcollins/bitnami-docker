
# Scalable Wordpress Blog Using Bitnami Containers, Kubernetes and Google Cloud Platform

- [Prerequisites](#prerequisites)
  + [Container engine environment](#container-engine-environment)
- [Create your cluster](#create-your-cluster)
- [Download the configuration files](#download-the-configuration-files)
- [Create the Docker container images](#create-the-docker-container-images)
    - [Wordpress Image](#wordpress-image)
    - [Apache Image](#apache-image)
- [MariaDB pod and service](#mariadb-pod-and-service)
  + [Create persistent disk](#create-persistent-disk)
  + [MariaDB pod](#mariadb-pod)
  + [MariaDB service](#mariadb-service)
- [Wordpress pod and service](#wordpress-pod-and-service)
  + [Wordpress secret store](#wordpress-secret-store)
  + [Wordpress pod](#wordpress-pod)
  + [Wordpress service](#wordpress-service)
- [Apache pod and service](#apache-pod-and-service)
  + [Apache pod](#apache-pod)
  + [Apache service](#apache-service)
- [Allow external traffic](#allow-external-traffic)
- [Access your Wordpress server](#access-your-wordpress-server)
- [Scaling the Wordpress application](#scaling-the-wordpress-application)
- [Take down and restart Wordpress](#take-down-and-restart-wordpress)
- [Cleanup](#cleanup)

This tutorial walks through setting up a scalable [Wordpress](http://wordpress.org) installation on Google Container Engine using the [Bitnami Container Images](https://bitnami.com/docker) for Docker. If you're just looking for the quickest way to get Wordpress up and running you might prefer our [prebuilt installers, VMs and Cloud Images](http://www.bitnami.com/stack/wordpress). If you're interested in getting hands on with [Kubernetes](http://kubernetes.io) and [Google Container Engine](https://cloud.google.com/container-engine/), read on....

We'll be creating a scalable Wordpress installation backed by instances of MariaDB and Apache containers. We also configure load balancing, an external IP and health checks. While the MariaDB instance will be used for the database requirements, the Apache instance will serve as the frontend to your Wordpress blog.

## Prerequisites

### Container engine environment

Set up your Google Container Engine environment using [these instructions](https://cloud.google.com/container-engine/docs/before-you-begin).

## Create your cluster

Now you are ready to create the Kubernetes cluster on which you'll run Wordpress. A cluster consists of a master API server hosted by Google and a set of worker nodes.

Create a cluster named `wordpress`:

```bash
$ gcloud beta container clusters create wordpress
```

A successful create response looks like:

```
Creating cluster wordpress...done.
Created [.../projects/bitnami-tutorials/zones/us-central1-b/clusters/wordpress].
kubeconfig entry generated for wordpress.
NAME       ZONE           MASTER_VERSION  MASTER_IP       MACHINE_TYPE   STATUS
wordpress  us-central1-b  1.0.6           162.222.180.48  n1-standard-1  RUNNING
```

Now that your cluster is up and running, we are set to launch the components that make up our Wordpress deployment.

## Download the configuration files

Clone the [bitnami-docker](https://github.com/bitnami/bitnami-docker) GitHub repository. The files used in this tutorial can be found in the `gke/wordpress` directory of the cloned repository:

```bash
$ git clone https://github.com/bitnami/bitnami-docker.git
$ cd bitnami-docker/gke/wordpress
```

## Create the Docker container images

In this section we will build the Docker images for our Wordpress blog.

### Wordpress

The Wordpress image is built using the `Dockerfile` from the `dockerfiles/wordpress-php` directory. Docker container images can extend from other existing images. Since Wordpress is a PHP application, we'll extend from the `bitnami/php-fpm` image.

Build the image by running:

```bash
$ cd dockerfiles/wordpress-php/
$ docker build -t gcr.io/<google-project-name>/wordpress-php .
```

Then push this image to the Google Container Registry:

```bash
$ gcloud docker push gcr.io/<google-project-name>/wordpress-php
```

### Apache

The Apache image is built using the `Dockerfile` from the `dockerfiles/wordpress-apache` directory and it extends the existing `bitnami/apache` image.

This image is used to serve static Wordpress assets (css, js, images, etc). It also adds a catch-all virtual host configuration that proxies requests for dynamic content to the Wordpress container using the TCP socket exposed by the PHP-FPM daemon.

Build the image by running:

```bash
$ cd dockerfiles/wordpress-apache/
$ docker build -t gcr.io/<google-project-name>/wordpress-apache .
```

Then push this image to the Google Container Registry:

```bash
$ gcloud docker push gcr.io/<google-project-name>/wordpress-apache
```

## MariaDB pod and service

### Create persistent disk

We will make use of [volumes](http://kubernetes.io/v1.0/docs/user-guide/volumes.html) for MariaDB, allowing the database server to preserve its state across pod shutdown and startup.

```bash
$ gcloud compute disks create --size 200GB mariadb-disk
Created [.../projects/bitnami-tutorials/zones/us-central1-b/disks/mariadb-disk].
NAME         ZONE          SIZE_GB TYPE        STATUS
mariadb-disk us-central1-b 200     pd-standard READY

```

The `mariadb-disk` is used in the pod definition of the MariaDB controller to achieve persistence of the database across startups and shutdowns.

### MariaDB pod

For our Wordpress deployment, the first thing that we're going to do is start a [pod](http://kubernetes.io/v1.0/docs/user-guide/pods.html) for MariaDB. We'll use a [replication controller](http://kubernetes.io/v1.0/docs/user-guide/replication-controller.html) to create the pod—even though it's a single pod, the controller is still useful for monitoring health and restarting the pod if required.

We'll use the config file `mariadb-controller.yml` for the pod which creates a single MariaDB pod.

> **Note**": You should change the value of the `MARIADB_PASSWORD` env variable to one of your choosing.

To create the pod:

```bash
$ kubectl create -f mariadb-controller.yml
```

Check to see if the pod is running. It may take a minute to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=mariadb
NAME            READY     STATUS    RESTARTS   AGE
mariadb-m1271   1/1       Running   0          20s
```

### MariaDB service

A [service](http://kubernetes.io/v1.0/docs/user-guide/services.html) is an abstraction which defines a logical set of pods and a policy by which to access them. It is effectively a named load balancer that proxies traffic to one or more pods.

When you set up a service, you tell it the pods to proxy based on pod labels. Note that the pod that you created in previous step has the label `name=mariadb`.

We'll use the file `mariadb-service.yml` to create a service for MariaDB. The `selector` field of the service configuration determines which pods will receive the traffic sent to the service. So, the configuration is specifies that we want this service to point to pods labeled with `name=mariadb`.

Start the service:

```bash
$ kubectl create -f mariadb-service.yml
```

See it running:

```bash
$ kubectl get services mariadb
NAME      LABELS         SELECTOR       IP(S)           PORT(S)
mariadb   name=mariadb   name=mariadb   10.247.254.14   3306/TCP
```

## Wordpress pod and service

Now that you have the database up and running, lets set up the Wordpress instance.

### Wordpress secret store

A [secret key store](http://kubernetes.io/v1.0/docs/user-guide/secrets.html) is intended to hold sensitive information such as passwords, access keys, etc. Having this information in a key store is safer and more flexible then putting it in to the pod definition.

We will create a key store to save the sensitive configuration parameters of our Wordpress container. This includes, but is not limited to the database password.

Lets begin by encoding our secret data in base64, starting with the database password.

```bash
$ base64 <<< "secretpassword"
c2VjcmV0cGFzc3dvcmQK
```

Specify this base64 encoded data in the secret definition described in `wordpress-secrets.yml`.

> **Note**:
>
> Update the value of `database-password` with the `base64` encoded data generated above.

Create the secret key store:

```bash
$ kubectl create -f wordpress-secrets.yml
```

See it running:

```bash
$ kubectl get secrets -l name=wordpress-secrets
NAME                TYPE      DATA
wordpress-secrets   Opaque    1
```

This secret key store will be mounted at `/etc/secrets` in read-only mode in the Wordpress pods.

### Wordpress pod

The controller and its pod template is described in the file `wordpress-controller.yml`.

> **Note**:
>
> Change the image name to `gcr.io/<google-project-name>/wordpress-php` as per the build instructions in [Wordpress image](#wordpress-image).

It specifies 1 replicas of the pod. Using this file, you can start your Wordpress controller with:

```bash
$ kubectl create -f wordpress-controller.yml
```

Check to see if the pods are running. It may take a few minutes to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=wordpress-php
NAME                  READY     STATUS    RESTARTS   AGE
wordpress-php-8hgri   1/1       Running   0          21s
```

### Wordpress service

As with the MariaDB pod, we want a service to group the Wordpress pods. The service specification for the Wordpress service is in `wordpress-service.yml`.

Start the service using:

```bash
$ kubectl create -f wordpress-service.yml
```

See it running:

```bash
$ kubectl get services wordpress-php
NAME            LABELS               SELECTOR             IP(S)            PORT(S)
wordpress-php   name=wordpress-php   name=wordpress-php   10.247.244.105   9000/TCP
```

## Apache pod and service

Now that we have the MariaDB and Wordpress pods up and running, lets set up the Apache service which will act as the frontend to our Wordpress blog.

### Apache pod

The controller and its pod template is described in the file `apache-controller.yml`.

> **Note**
>
> 1. Change the image name to `gcr.io/<google-project-name>/wordpress-php` as per the build instructions in [Apache image](#apache-image).


It specifies 3 replicas of the server. Using this file, you can start your Apache servers with:

```bash
$ kubectl create -f apache-controller.yml
```

Check to see if the pods are running. It may take a few minutes to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=wordpress-apache
NAME                     READY     STATUS    RESTARTS   AGE
wordpress-apache-fku0h   1/1       Running   0          11s
wordpress-apache-hwubs   1/1       Running   0          11s
wordpress-apache-m2iag   1/1       Running   0          11s
```

Once the servers are up, you can list the pods in the cluster, to verify that they're all running:

```bash
$ kubectl get pods
NAME                     READY     STATUS    RESTARTS   AGE
mariadb-m1271            1/1       Running   0          16m
wordpress-apache-fku0h   1/1       Running   0          32s
wordpress-apache-hwubs   1/1       Running   0          32s
wordpress-apache-m2iag   1/1       Running   0          32s
wordpress-php-8hgri      1/1       Running   0          2m
```

You'll see a single MariaDB pod, a Wordpress pod and three Apache pods. In [Scaling the Apache application](#scaling-the-redmine-application) we will see how we can scale the Wordpress and Apache pods.

### Apache service

As with the other pods, we want a service to group the Apache pods. However, this time it's different: this service is user-facing, so we want it to be externally visible. That is, we want a client to be able to request the service from outside the cluster. To accomplish this, we can set the `type: LoadBalancer` field in the service configuration.

The service specification for the Apache is in `apache-service.yml`.

```bash
$ kubectl create -f apache-service.yml
```

See it running:

```bash
$ kubectl get services wordpress-apache
NAME               LABELS                  SELECTOR                IP(S)           PORT(S)
wordpress-apache   name=wordpress-apache   name=wordpress-apache   10.247.248.86   80/TCP

```

## Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Wordpress service accessible from the internet we have to open port 80.

First we need to get the node prefix for the cluster using `kubectl get nodes`:

```bash
$ kubectl get nodes
NAME                               LABELS                                                    STATUS
gke-wordpress-71da2c3f-node-0c48   kubernetes.io/hostname=gke-wordpress-71da2c3f-node-0c48   Ready
gke-wordpress-71da2c3f-node-6cel   kubernetes.io/hostname=gke-wordpress-71da2c3f-node-6cel   Ready
gke-wordpress-71da2c3f-node-tus4   kubernetes.io/hostname=gke-wordpress-71da2c3f-node-tus4   Ready
```

The value of `--target-tag` in the command below is the node prefix for the cluster up to `-node`.

```bash
$ gcloud compute firewall-rules create --allow=tcp:80 \
    --target-tags=gke-wordpress-71da2c3f-node wordpress-http
```

A successful response looks like:

```bash
Created [.../projects/bitnami-tutorials/global/firewalls/wordpress-http].
NAME           NETWORK SRC_RANGES RULES  SRC_TAGS TARGET_TAGS
wordpress-http default 0.0.0.0/0  tcp:80          gke-wordpress-71da2c3f-node
```

Alternatively, you can open up port 80 from the [Developers Console](https://console.developers.google.com/).

## Access your Wordpress server

Now that the firewall is open, you can access the service. Find the external IP of the Apache service you just set up:

```bash
$ kubectl describe services wordpress-apache
Name:                   wordpress-apache
Namespace:              default
Labels:                 name=wordpress-apache
Selector:               name=wordpress-apache
Type:                   LoadBalancer
IP:                     10.247.248.86
LoadBalancer Ingress:   104.197.114.51
Port:                   <unnamed> 80/TCP
NodePort:               <unnamed> 31191/TCP
Endpoints:              10.244.0.5:80,10.244.2.5:80,10.244.2.6:80
Session Affinity:       None
No events.
```

Then, visit `http://x.x.x.x` in your favourite web browser, where `x.x.x.x` is the IP address listed next to `LoadBalancer Ingress` in the response. You will be greeted with the Wordpress setup page.

## Scaling the Redmine application

Since the Wordpress and Apache pods are defined as a service that uses a replication controller, you can easily resize the number of pods in the replication controller as follows:

To scale the Wordpress pods:

```bash
$ kubectl scale --replicas=5 rc wordpress-php
```

The configuration for the controllers will be updated, to specify that there should be 5 replicas running. The replication controller adjusts the number of pods it is running to match that, and you will be able to see the additional pods running:

```bash
$ kubectl get pods -l name=wordpress-php
NAME                  READY     STATUS    RESTARTS   AGE
wordpress-php-24rdp   1/1       Running   0          18s
wordpress-php-8hgri   1/1       Running   0          15m
wordpress-php-gxw22   1/1       Running   0          18s
wordpress-php-lovo7   1/1       Running   0          18s
wordpress-php-wur0y   1/1       Running   0          18s
```

Similarly to scale the Apache pods:

```bash
$ kubectl scale --replicas=5 rc wordpress-apache
```

...and check:

```bash
$ kubectl get pods -l name=wordpress-apache
NAME                     READY     STATUS    RESTARTS   AGE
wordpress-apache-8d9dq   1/1       Running   0          11s
wordpress-apache-fku0h   1/1       Running   2          13m
wordpress-apache-hwubs   1/1       Running   2          13m
wordpress-apache-k7li9   1/1       Running   0          11s
wordpress-apache-m2iag   1/1       Running   1          13m
```

You can scale down in the same manner.

## Take down and restart Wordpress

Because we used a persistent disk for the MariaDB pod and used Google cloud storage for files uploaded in Wordpress, your Wordpress state is preserved even when the pods it's running on are deleted. Lets try it.

```bash
$ kubectl delete rc wordpress-apache
$ kubectl delete rc wordpress-php
$ kubectl delete rc mariadb
```

*Deleting the replication controller also deletes its pods.*

Confirm that the pods have been deleted:

```bash
$ kubectl get pods
```

Then re-create the pods:

```bash
$ kubectl create -f mariadb-controller.yml
$ kubectl create -f wordpress-controller.yml
$ kubectl create -f apache-controller.yml
```

Once the pods have restarted, the `mariadb`, `wordpress-php` and `wordpress-apache` services pick them up immediately based on their labels, and your Wordpress blog is restored.

## Cleanup

To delete your application completely:

*If you intend to teardown the entire cluster then jump to Step 4.*

  1. Delete the controllers:

  ```bash
  $ kubectl delete rc wordpress-apache
  $ kubectl delete rc wordpress-php
  $ kubectl delete rc mariadb
  ```

  2. Delete the services:

  ```bash
  $ kubectl delete service wordpress-apache
  $ kubectl delete service wordpress-php
  $ kubectl delete service mariadb
  ```

  3. Delete the secret key store

  ```bash
  $ kubectl delete secret wordpress-secrets
  ```

  4. Delete your cluster:

  ```bash
  $ gcloud beta container clusters delete wordpress
  ```

  5. Delete the firewall rule:

  ```bash
  $ gcloud compute firewall-rules delete wordpress-http
  ```

  6. Delete the disks:

  ```bash
  $ gcloud compute disks delete mariadb-disk
  ```
