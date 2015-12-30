# Prerequisites for Liferay

## Container engine environment

Set up your **Google Container Engine** environment using [these instructions](https://cloud.google.com/container-engine/docs/before-you-begin).

1. Sign up for a **Google Account**: [Go](https://cloud.google.com/container-engine/docs/before-you-begin#sign_up_for_a_google_account)
2. Enable **billing**: [Go](https://cloud.google.com/container-engine/docs/before-you-begin#enable_billing)
3. Enable the **Container Engine API**: [Go](https://cloud.google.com/container-engine/docs/before-you-begin#enable_the_container_engine_api)
4. **Install the gcloud** command line interface: [Go](https://cloud.google.com/container-engine/docs/before-you-begin#install_the_gcloud_command_line_interface) (or follow the following steps)
  1. Download and install **Google Cloud SDK** by running the following command in your shell or Terminal:
  
     ```
     curl https://sdk.cloud.google.com | bash
     ```
     
  2. **Restart** your **shell**:
  
     ```
     exec -l $SHELL
     ```
    
  3. Run `gcloud init` to authenticate, **set up a default configuration**, and clone the project's Git repository.
  
     ```
     gcloud init
     ```
     
5. **Install kubectl**

  ```
  gcloud components update kubectl
  ```
  
6. Set gcloud defaults: [Optional](https://cloud.google.com/container-engine/docs/before-you-begin#optional_set_gcloud_defaults)

## Create your cluster

A cluster consists of a master API server hosted by Google and a set of worker nodes.

Create a cluster named **liferay**:

```
gcloud beta container clusters create liferay
```

A successful create response looks like:

```
Creating cluster liferay...done.
Created [.../projects/your_project_id/zones/us-central1-c/clusters/liferay].
kubeconfig entry generated for liferay.
NAME     ZONE            MASTER_VERSION  MASTER_IP       MACHINE_TYPE   NUM_NODES  STATUS
liferay  us-central1-c   1.1.1           104.197.190.87  n1-standard-1  3          RUNNING
```

> **Note:**
>
> You might get a response like this:
> 
> ```
> ERROR: (gcloud.beta.container.clusters.create) The required property  [zone] is not currently set.
> It can be set on a per-command basis by re-running your command with  the [--zone] flag.
> ```
> 
> That means that you forgot **set your zone**. You can list the zones and set one of them:
> 
> ```
> gcloud compute zones list
> gcloud config set compute/zone europe-west1-c
> ```


Now that your cluster is up and running, we are set to launch the components that make up our deployment.

# MariaDB

## Create a persistent disk

We'll make use of volumes to create a persistent disk for the MariaDB master. This volume is used in the pod definition of the MariaDB master controller `mariadb-master-controller.yml`.

Create the persistent disk using:

```
gcloud compute disks create --size 200GB mariadb-disk
Created [.../projects/your_project_id/zones/104.197.190.87/disks/mariadb-disk].
NAME         ZONE          SIZE_GB TYPE        STATUS
mariadb-disk us-central1-b 200     pd-standard READY
```

## Create master replication controller

The first thing that we're going to do is start a replication controller for MariaDB master. We'll use a **replication controller** to create the MariaDB master pod — even though it's a single pod, the controller is still useful **for monitoring health** and **restarting the pod if required**.

We'll use the config file `mariadb-master-controller.yml` which creates a single MariaDB master pod with the label `name=mariadb-master`. The pod uses the [bitnami/mariadb](https://hub.docker.com/r/bitnami/mariadb/) image and specifies the user and database to create as well as the replication parameters using **environment variables**.

> **Note:**
>
> You should change the value of the `MARIADB_PASSWORD` and `MARIADB_REPLICATION_PASSWORD` env variables to your choosing.

To **create the replication controller**:

```
kubectl create -f mariadb-master-controller.yml
```

See it running. It may take a minute to change from *Pending* to *Running*:

```
kubectl get pods -l name=mariadb-master
NAME                   READY     STATUS    RESTARTS   AGE
mariadb-master-2nm57   1/1       Running   0          48s
```

> **Note:**
> 
> If you get an output like this:
> 
> ```
> NAME                   READY     STATUS          RESTARTS   AGE
> mariadb-master-u8qc5   0/1       ImageNotReady   0          1m
> ```
> 
> You forgot create the persistent disk for the mariaDB master

## Create master service

**A service** is an abstraction which **defines a logical set of pods and a policy by which to access them**. It is effectively **a** named **load balancer** that **proxies traffic to one or more pods**.

When you set up a service, you tell it the pods to proxy **based on pod labels**. The pod that you created in previous step has the label `name=mariadb-master`.

We'll use the file `mariadb-master-service.yml` to create a service for the MariaDB master pod. The **selector** field of the service configuration **determines which pods will receive the traffic sent to the service**. So, the configuration specifies that we want this service to point to pods labeled with `name=mariadb-master`.

To **start the service**:

```
kubectl create -f mariadb-master-service.yml
```

See it running:

```
kubectl get services mariadb-master
NAME             CLUSTER_IP      EXTERNAL_IP   PORT(S)    SELECTOR              AGE
mariadb-master   10.223.250.10   <none>        3306/TCP   name=mariadb-master   40s
```

# Liferay

## Create the Docker container image

The Liferay image is built using the `Dockerfile` from the `dockerfiles` directory. Docker container images can extend from other existing images. Since Liferay is a Java application, we'll extend the `bitnami/tomcat` image.

In the Dockerfile the Liferay source is copied into the `/app` directory of the container. The base `bitnami/tomcat` image uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision. We use the infrastucture provided by *s6-overlay* to create a container initialization script `/etc/cont-init.d/60-liferay` which configures the database connection parameters for Liferay in `/app/liferay/WEB-INF/classes/portal-ext.properties` among other things.

Build the image by running:

```
cd dockerfiles
docker build -t gcr.io/<google-project-name>/liferay-tomcat .
```

Then push this image to the Google Container Registry:

```
gcloud docker push gcr.io/<google-project-name>/liferay-tomcat
```


## Create Google Cloud Storage bucket

To allow horizontal scaling of the Liferay application we'll use the Google Cloud Storage service, in S3 interoperability mode, to host files uploaded to the Liferay document's library. This also ensures that the uploaded files are persistent across pod startup and shut down.

For Liferay to be able to access Google Cloud Storage, we need to provide the access credentials to our Liferay pod.

To **create a bucket** and **developer key**:

1. Go to the [Google Developers Console](https://console.developers.google.com/).

2. Click the name of your project.

3. In the left sidebar, go to **Storage > Browser**.

4. Select **Create bucket** and give it the name (*liferay-test* in this case).

  ![image](/gke/liferay/images/liferay_bucket.png)
  
5. In the left sidebar, go to **Storage > Settings**.

6. Select **Interoperability**.

7. If you have not set up interoperability before, click **Enable interoperability access**.

8. Click **Create a new key**.

  ![image](/gke/liferay/images/liferay_s3.png)

Make a note of the generated **Access Key** and **Secret**, in the next section we'll specify them in the secrets definition.

## Create secret store

A **secret key store** is intended to **hold sensitive information such as passwords, access keys, etc**. Having this information in a key store is safer and more flexible then putting it in to the pod definition.

We'll create a key store to save the sensitive configuration parameters of our deployment. This includes, but is not limited to the database password, session tokens, cloud storage access key id and secret.

Begin by encoding our secrets in *base64*, starting with the **database password**:

```
DBPWD=$(base64 -w128 <<< "secretpassword")
```

Next, we encode the **S3 credentials** (*Access Key* and *Secret*) as generated in [Create Google Cloud Storage bucket](##create_google_cloud_storage_bucket):

```
S3AK=$(base64 <<< "GOOGBPHUGSK2TFQ4LCEI")
S3S=$(base64 <<< "WLkMGbMXGpuZ6dpePLVwARiiEcJ3yoonZ8Relgby")
```

To show them:

```
echo -e "\\nDB Password:\t$DBPWD\nAccess Key:\t$S3AK\nSecret:\t\t$S3S\n"
```

Update `liferay-secrets.yml` with the *base64* encoded **database password** and **S3 credentials**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: liferay-secrets
  namespace: default
  labels:
    name: liferay-secrets
data:
  database-password: "c2VjcmV0cGFzc3dvcmQK"
  s3-access-key: "R09PR0JQSFVHU0syVEZRNExDRUkK"
  s3-secret: "V0xrTUdiTVhHcHVaNmRwZVBMVndBUmlpRWNKM3lvb25aOFJlbGdieQo="
```

or use these commands:

```
sed -i s/"database-password:.*"/"database-password: \"$DBPWD\""/g liferay-secrets.yml
sed -i s/"s3-access-key:.*"/"s3-access-key: \"$S3AK\""/g liferay-secrets.yml
sed -i s/"s3-secret:.*"/"s3-secret: \"$S3S\""/g liferay-secrets.yml
```

To **create the secret key store**:

```
kubectl create -f liferay-secrets.yml
```

See it running:

```
kubectl get secrets -l name=liferay-secrets
NAME              TYPE      DATA      AGE
liferay-secrets   Opaque    3         1m
```

This secret key store will be mounted at `/etc/secrets` in *read-only* mode in the Liferay pods.

## Create replication controller

The controller and its pod template is described in the file `liferay-controller.yml`. It specifies 1 replica of the pod with the label `name=liferay-tomcat`.

> **Note:**
>
> Change the image name to `gcr.io/bitnamigcetest/liferay-tomcat` as per the build instructions in [Liferay Docker container image](##create_the_docker_container_image)

To **start the replication controller**:

```
kubectl create -f liferay-controller.yml
```

See it running. It may take a minute to change from *Pending* to *Running*:

```
kubectl get pods -l name=liferay-tomcat
NAME                  READY     STATUS    RESTARTS   AGE

```

## Create service

We want a service to group the Liferay pods. The service specification for the Liferay service is defined in `liferay-service.yml` and specifies the label `name=liferay-tomcat` as the pod `selector`.

To **start the service**:

```
kubectl create -f liferay-service.yml
```

See it running:

```
kubectl get services liferay-tomcat
NAME             CLUSTER_IP      EXTERNAL_IP   PORT(S)    SELECTOR              AGE
```

# Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Tomcat service accessible from the internet we have to open the TCP port `80`.

First we need to get the node prefix for the cluster using:

```
kubectl get nodes
NAME                             LABELS                                                  STATUS    AGE
gke-liferay-866210e3-node-7dv4   kubernetes.io/hostname=gke-liferay-866210e3-node-7dv4   Ready     2h
gke-liferay-866210e3-node-p9va   kubernetes.io/hostname=gke-liferay-866210e3-node-p9va   Ready     2h
gke-liferay-866210e3-node-spii   kubernetes.io/hostname=gke-liferay-866210e3-node-spii   Ready     2h
```

The value of `--target-tag` in the command below is the node prefix for the cluster up to `-node`. We can match the node name with the `sed` tool or we can copy the tag manually.

* Manual approach:

 ```
 gcloud compute firewall-rules create \
   --allow=tcp:80 \
   --target-tags=gke-liferay-866210e3-node \
   liferay-http
 ```
 
* Using `sed` tool:
 
 ```
 gcloud compute firewall-rules create \
   --allow=tcp:80 \
   --target-tags=$(kubectl get nodes -o name | sed -n -e 's/node\/\(.*-node\)\(-.*\)$/\1/p' | uniq) \
   liferay-http
 ```
 
A successful response looks like:
 
```
Created [.../projects/your_project_id/global/firewalls/liferay-http].
NAME         NETWORK SRC_RANGES RULES  SRC_TAGS TARGET_TAGS
liferay-http default 0.0.0.0/0  tcp:80          gke-liferay-866210e3-node
```

Alternatively, you can open up port `80` from the [Developers Console](https://console.developers.google.com/).

# Access your Liferay server

Now that the firewall is open, you can access the service over the internet. Find the external IP of the Apache service you just set up using:

```
kubectl describe services liferay-tomcat
```
