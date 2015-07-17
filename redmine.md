
# Scalable Redmine Using Bitnami Containers, Kubernetes and Google Cloud Platform

- [Before you begin](#before-you-begin)
- [Download the configuration files](#download-the-configuration-files)
- [Create a Docker container image](#create-a-docker-container-image)
- [Create your cluster](#create-your-cluster)
- [Create MariaDB pod and service](#create-mariadb-pod-and-service)
  + [Create persistent disk](#create-persistent-disk)
  + [MariaDB pod](#mariadb-pod)
  + [MariaDB service](#mariadb-service)
- [Create Redmine pod and service](#create-redmine-pod-and-service)
  + [Create Google cloud storage bucket](#create-google-cloud-storage-bucket)
  + [Redmine secret store](#redmine-secret-store)
  + [Redmine pod](#redmine-pod)
  + [Redmine service](#redmine-service)
- [Allow external traffic](#allow-external-traffic)
- [Access your Redmine server](#access-your-redmine-server)
- [Scaling the Redmine application](#scaling-the-redmine-application)
- [Take down and restart Redmine](#take-down-and-restart-redmine)
- [Cleanup](#cleanup)

This tutorial walks through setting up a scalable [Redmine](http://redmine.org) installation on Google Container Engine using the Bitnami Container Images for Docker. If you're just looking for the quickest way to get Redmine up and running you might prefer our [prebuilt installers, VMs and Cloud Images](http://www.bitnami.com/stack/redmine). If you're interested in getting hands on with Kubernetes and Google Container Engine, read on....

!SPB Quick architecture diagram here!


We'll be creating a scalable Redmine installation backed by an instance of MariaDB. We also configure load balancing, an external IP, a secret store and health checks. We use [Google Cloud Storage](https://cloud.google.com/storage/) for persistent file uploads.

## Before you begin

Set up your Google Container Engine environment using [these instructions](https://cloud.google.com/container-engine/docs/before-you-begin).

## Download the configuration files

!SPB Move these to a GitHub repo and pull them. Perhaps the bitnami-docker repo?!

We'll be using these files to deploy and configure Redmine :

  - Dockerfile
  - run.sh
  - redmine-secrets.yml
  - redmine-controller.yml
  - redmine-service.yml
  - mariadb-controller.yml
  - mariadb-service.yml

## Create a Docker container image

The Redmine image is built using the `Dockerfile` and `run.sh` script. Docker container images can extend from other existing images so for this image, we'll extend from the existing `bitnami/ruby` image.

The `Dockerfile` imports the correct Redmine and Redmine S3 plug-in source code and a `run.sh` script. 

The `run.sh` script automates links the MariaDB service and sets up the Redmine database connection parameters. It also configures Google Cloud Storage and performs database migration tasks before starting up the Redmine application server.

Build the Redmine image by running:

```bash
$ docker build -t gcr.io/<google-project-name>/redmine .
```

Then push this image to the Google Container Registry:

```bash
$ gcloud docker push gcr.io/<google-project-name>/redmine
```

## Create your cluster

Now you are ready to create the cluster on which you'll run Redmine. A cluster consists of a master API server hosted by Google and a set of worker nodes.

Create a cluster named `redmine`:

```bash
$ gcloud beta container clusters create redmine
```

A successful create response looks like:

```
Creating cluster redmine...done.
Created [.../projects/bitnami-tutorials/zones/us-central1-b/clusters/redmine].
kubeconfig entry generated for redmine.
NAME     ZONE           MASTER_VERSION  MASTER_IP       MACHINE_TYPE   STATUS
redmine  us-central1-b  0.21.2          104.197.17.142  n1-standard-1  RUNNING
```

Now that your cluster is up and running, everything is set to launch the Redmine app.

## Create MariaDB pod and service

### Create persistent disk

We will make use of [persistent disks](https://cloud.google.com/compute/docs/disks/) for MariaDB, allowing the database server to preserve its state across pod shutdown and startup.

```bash
$ gcloud compute disks create --size 200GB mariadb-disk
Created [.../projects/bitnami-tutorials/zones/us-central1-b/disks/mariadb-disk].
NAME         ZONE          SIZE_GB TYPE        STATUS
mariadb-disk us-central1-b 200     pd-standard READY
```

We will use the `mariadb-disk` in the MariaDB pod definition in the next step.

### MariaDB pod

The first thing that we're going to do is start a [pod](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/user-guide/pods.md) for MariaDB. We'll use a [replication controller](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/user-guide/replication-controller.md) to create the pod—even though it's a single pod, the controller is still useful for monitoring health and restarting the pod if required.

We'll use the config file `mariadb-controller.yml` for the database pod. The pod containers a single container. 

> **Note**": You should change the value of the `MARIADB_PASSWORD` env variable to one of your choosing.

To create the pod:

```bash
$ kubectl create -f mariadb-controller.yml
```

Check to see if the pod is running. It may take a minute to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=mariadb
NAME            READY     REASON    RESTARTS   AGE
mariadb-mmae9   1/1       Running   0          31s
```

### MariaDB service

A [service](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/user-guide/services.md) is an abstraction which defines a logical set of pods and a policy by which to access them. It is effectively a named load balancer that proxies traffic to one or more pods.

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
NAME      LABELS         SELECTOR       IP(S)           PORT(S)
mariadb   name=mariadb   name=mariadb   10.99.253.149   3306/TCP
```

## Create Redmine pod and service

Now that you have the database up and running, lets set up the Redmine web servers.

### Create Google cloud storage bucket

We will be using a Google cloud storage bucket, in S3 interoperability mode, for persistence of files uploaded to our Redmine application. We will also generate a developer key which will enable the Redmine application to access the bucket.

To create a bucket and developer key:

  1. Go to the [Google Developers Console](https://console.developers.google.com/).
  2. Click the name of your project.
  3. In the left sidebar, go to **Storage > Cloud Storage > Browser**.
  4. Select **Create bucket** and give it the name, eg. `redmine-uploads`.

  ![Create Bucket](images/create-bucket.png)

  5. In the left sidebar, go to **Storage > Cloud Storage > Storage settings**.
  6. Select **Interoperability**.
  7. If you have not set up interoperability before, click **Enable interoperability access**.
  8. Click **Create a new key**.

  ![Create Developer Key](images/create-developer-key.png)

Make a note of the generated **Access Key** and **Secret** as we will use in the Redmine pod definition in the next step.

### Redmine secret store

A [secret key store](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/design/secrets.md) is intended to hold sensitive information such as passwords, access keys, etc. Having this information in a secret key store is safer and more flexible then putting in to our pod definition.

We will create a resource to store the sensitive configuration parameters of our Redmine container. This includes, but is not limited to the database password, session token, cloud storage access key id and secret.

Lets begin by encoding our secret data in base64, starting with the database password.

```bash
$ base64 <<< "secretpassword"
c2VjcmV0cGFzc3dvcmQK
```

Next, we encode the google cloud storage access credentials as generated in [Create Google cloud storage bucket](#create-google-cloud-storage-bucket).

```bash
$ base64 <<< "GOOGUF56OWN3R3LFYOZE"
R09PR1VGNTZPV04zUjNMRllPWkUK

$ base64 <<< "A+uW0XLz9Y+EHUGRUf1V2uApcI/TenhBtUnPao7i"
QSt1VzBYTHo5WStFSFVHUlVmMVYydUFwY0kvVGVuaEJ0VW5QYW83aQo=
```

Finally, we encode a random key that will be used by the Redmine application to encode cookies storing session data. It is recommended to use a key of length 30 characters or more.

```bash
$ base64 <<< "mCjVXBV6jZVn9RCKsHZFGBcVmpQd8l9s"
bUNqVlhCVjZqWlZuOVJDS3NIWkZHQmNWbXBRZDhsOXMK
```

> **Tip**: `pwgen -csv1 64` will generate a strong 64 character key that can be used as the Redmine session key.*

Now, we use this base64 encoded secret data in the secret definition described in `redmine-secret.yml`:

```yaml
apiVersion: "v1"
kind: "Secret"
metadata:
  name: "redmine-secrets"
  namespace: "default"
  labels:
    name: redmine-secrets
data:
  redmine-session-token: "bUNqVlhCVjZqWlZuOVJDS3NIWkZHQmNWbXBRZDhsOXMK"
  database-password: "c2VjcmV0cGFzc3dvcmQK"
  s3-access-key-id: "R09PR1VGNTZPV04zUjNMRllPWkUK"
  s3-secret-access-key: "QSt1VzBYTHo5WStFSFVHUlVmMVYydUFwY0kvVGVuaEJ0VW5QYW83aQo="
```

> **Note**:
> Update the values of `redmine-session-token`, `database-password`, `s3-access-key-id` and `s3-secret-access-key` values with the base64 encoded data generated above.

Create the secret key store:

```bash
$ kubectl create -f redmine-secrets.yml
```

See it running:

```bash
$ kubectl get secrets -l name=redmine-secrets
NAME              TYPE      DATA
redmine-secrets   Opaque    4
```

This secret key store will be mounted at `/etc/redmine-secrets` as read-only in the Redmine pods.

### Redmine pod

The controller and its pod template is described in the file `redmine-controller.yml`.

> **Note**:
> 1. Change the image name to `gcr.io/<google-project-name>/redmine` as per the build instructions in [Create a Docker container image](#create-a-docker-container-image).
> 2. Change the value of `S3_BUCKET` with the one generated in [Create Google cloud storage bucket](#create-google-cloud-storage-bucket)

It specifies 3 replicas of the server. Using this file, you can start your Redmine servers with:

```bash
$ kubectl create -f redmine-controller.yml
```

Check to see if the pod is running. It may take a few minutes to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=redmine
NAME            READY     REASON    RESTARTS   AGE
redmine-lxfmy   1/1       Running   0          1m
redmine-nqzqc   1/1       Running   0          1m
redmine-zrc9d   1/1       Running   0          1m
```

Once the servers are up, you can list the pods in the cluster, to verify that they're all running:

```bash
$ kubectl get pods
NAME            READY     REASON    RESTARTS   AGE
mariadb-mmae9   1/1       Running   0          3m
redmine-lxfmy   1/1       Running   0          1m
redmine-nqzqc   1/1       Running   0          1m
redmine-zrc9d   1/1       Running   0          1m
```

You'll see a single MariaDB pod and three Redmine pods. In [Scaling the Redmine application](#scaling-the-redmine-application) we will see how we can scale the Redmine pods.

### Redmine service

As with the other pods, we want a service to group the Redmine server pods. However, this time it's different: this service is user-facing, so we want it to be externally visible. That is, we want a client to be able to request the service from outside the cluster. To accomplish this, we can set the `type: LoadBalancer` field in the service configuration.

The service specification for the Redmine is in `redmine-service.yml`.
Start up the service:

```bash
$ kubectl create -f redmine-service.yml
```

See it running:

```bash
$ kubectl get services redmine
NAME      LABELS         SELECTOR       IP(S)           PORT(S)
redmine   name=redmine   name=redmine   10.99.248.210   80/TCP
```

## Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Redmine service accessible from the Internet we have to open port 80.

First we need to get the node prefix for the cluster using `kubectl get nodes`:

```bash
$ kubectl get nodes
NAME                             LABELS                                                  STATUS
gke-redmine-08042373-node-3djt   kubernetes.io/hostname=gke-redmine-08042373-node-3djt   Ready
gke-redmine-08042373-node-73j3   kubernetes.io/hostname=gke-redmine-08042373-node-73j3   Ready
gke-redmine-08042373-node-wu4g   kubernetes.io/hostname=gke-redmine-08042373-node-wu4g   Ready
```

The value of `--target-tag` in the command below is the node prefix for the cluster up to `-node`.

```bash
$ gcloud compute firewall-rules create --allow=tcp:80 \
    --target-tags=gke-redmine-08042373-node redmine
```

A successful response looks like:

```bash
Created [.../projects/bitnami-tutorials/global/firewalls/redmine].
NAME    NETWORK SRC_RANGES RULES  SRC_TAGS TARGET_TAGS
redmine default 0.0.0.0/0  tcp:80          gke-redmine-08042373-node
```

You can alternatively open up port 80 from the [Developers Console](https://console.developers.google.com/).

## Access your Redmine server

Now that the firewall is open, you can access the service. Find the external IP of the service you just set up:

```bash
$ kubectl describe services redmine
Name:                   redmine
Labels:                 name=redmine
Selector:               name=redmine
Type:                   LoadBalancer
IP:                     10.99.248.210
LoadBalancer Ingress:   104.197.52.11
Port:                   <unnamed> 80/TCP
NodePort:               <unnamed> 31512/TCP
Endpoints:              10.96.0.5:3000,10.96.2.4:3000,10.96.2.5:3000
Session Affinity:       None
No events.
```

Then, visit `http://x.x.x.x` where `x.x.x.x` is the IP address listed next to `LoadBalancer Ingress` in the response.

## Scaling the Redmine application

Since the Redmine pod is defined as a service that uses a replication controller, you can easily resize the number of pods in the replication controller as follows:

```bash
$ kubectl scale --replicas=5 rc redmine
```

The configuration for the redmine controller will be updated, to specify that there should be 5 replicas running. The replication controller adjusts the number of pods it is running to match that, and you will be able to see the additional pods running:

```bash
$ kubectl get pods -l name=redmine
NAME            READY     REASON    RESTARTS   AGE
redmine-lmbph   1/1       Running   1          54s
redmine-lxfmy   1/1       Running   1          25m
redmine-nqzqc   1/1       Running   0          25m
redmine-qyvl8   1/1       Running   0          54s
redmine-zrc9d   1/1       Running   1          25m
```

You can scale down the number of Redmine pods in the same manner.

## Take down and restart Redmine

Because we used a persistent disk for the MariaDB pod and used Google cloud storage for files uploaded in Redmine, your Redmine state is preserved even when the pods it's running on are deleted. Lets try it.

```bash
$ kubectl delete rc redmine
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
$ kubectl create -f redmine-controller.yml
```

Once the pods have restarted, the `redmine` and `mariadb` services pick them up immediately based on their labels, and your Redmine application is restored.

## Cleanup

To delete your application completely:


*If you intend to teardown the entire cluster then jump to Step 4.*

  1. Delete the services:

  ```bash
  $ kubectl delete service redmine
  $ kubectl delete service mariadb
  ```

  2. Delete the controller:

  ```bash
  $ kubectl delete rc redmine
  $ kubectl delete rc mariadb
  ```

  3. Delete the secret key store

  ```bash
  $ kubectl delete secret redmine-secrets
  ```

  4. Delete your cluster:

  ```bash
  $ gcloud beta container clusters delete redmine
  ```

  5. Delete the firewall rule:

  ```bash
  $ gcloud compute firewall-rules delete redmine
  ```

  6. Delete the disks:

  ```bash
  $ gcloud compute disks delete mariadb-disk
  ```

  7. Delete the bucket and developer key from the [Google Developers Console](https://console.developers.google.com/)
