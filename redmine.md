
# Redmine Tutorial

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
  + [Redmine pod](#redmine-pod)
  + [Redmine service](#redmine-service)
- [Allow external traffic](#allow-external-traffic)
- [Access your Redmine server](#access-your-redmine-server)
- [Scaling the Redmine application](#scaling-the-redmine-application)
- [Take down and restart Redmine](#take-down-and-restart-redmine)
- [Cleanup](#cleanup)

This tutorial walks you through setting up [Redmine](http://redmine.org), backup by a MariaDB database and running on the Google Container Engine.

We create a Docker container image using the Redmine source code and also install the [Redmine S3](https://github.com/ka8725/redmine_s3) plugin to enable persistence of file uploads via [Google cloud storage](https://cloud.google.com/storage/).

The tutorial also demonstrates the setup of Redmine on an external IP, load balancing to a set of replicated servers backed by replicated Redmine nodes.

## Before you begin

Follow the instructions on the [Before You Begin](https://cloud.google.com/container-engine/docs/before-you-begin) page to set up your Container Engine environment.

## Download the configuration files

Download and unpack the `redmine.zip` file into your working directory. The ZIP file contains the configuration files used in this tutorial:

  - Dockerfile
  - run.sh
  - redmine-controller.yml
  - redmine-service.yml
  - mariadb-controller.yml
  - mariadb-service.yml

## Create a Docker container image

The Redmine image is built using the `Dockerfile` and `run.sh` script. Docker container images can extend from other existing images so for this image, we'll extend from the existing `bitnami/ruby` image.

Take a look the the `Dockerfile` contents:

```dockerfile
FROM bitnami/ruby:latest
ENV REDMINE_VERSION=3.0.4

RUN curl -L http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz \
      -o /tmp/redmine-${REDMINE_VERSION}.tar.gz \
 && curl -L https://github.com/ka8725/redmine_s3/archive/master.tar.gz \
      -o /tmp/redmine_s3.tar.gz \
 && mkdir -p /home/$BITNAMI_APP_USER/redmine/ \
 && tar -xf /tmp/redmine-${REDMINE_VERSION}.tar.gz --strip=1 -C /home/$BITNAMI_APP_USER/redmine/ \
 && mkdir -p /home/$BITNAMI_APP_USER/redmine/plugins/redmine_s3 \
 && tar -xf /tmp/redmine_s3.tar.gz --strip=1 -C /home/$BITNAMI_APP_USER/redmine/plugins/redmine_s3 \
 && cd /home/$BITNAMI_APP_USER/redmine \
 && cp -a config/database.yml.example config/database.yml \
 && cp -a plugins/redmine_s3/config/s3.yml.example config/s3.yml \
 && bundle install --without development test \
 && chown -R $BITNAMI_APP_USER:$BITNAMI_APP_USER /home/$BITNAMI_APP_USER/redmine/ \
 && rm -rf /tmp/redmine-${REDMINE_VERSION}.tar.gz /tmp/redmine_s3.tar.gz

COPY run.sh /home/$BITNAMI_APP_USER/redmine/run.sh
RUN sudo chmod 755 /home/$BITNAMI_APP_USER/redmine/run.sh

WORKDIR /home/$BITNAMI_APP_USER/redmine/
CMD ["/home/bitnami/redmine/run.sh"]
```

Next, lets take a look at the `run.sh` script referenced in the `Dockerfile`.

```bash
#!/bin/bash
set -e

REDMINE_SESSION_TOKEN=${REDMINE_SESSION_TOKEN:-rXvLWjqs4tqKNjdHgkqTLjqfj4wWkLCr}

# automatically fetch database parameters from bitnami/mariadb
DATABASE_HOST=${DATABASE_HOST:-${MARIADB_PORT_3306_TCP_ADDR}}
DATABASE_NAME=${DATABASE_NAME:-${MARIADB_ENV_MARIADB_DATABASE}}
DATABASE_USER=${DATABASE_USER:-${MARIADB_ENV_MARIADB_USER}}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-${MARIADB_ENV_MARIADB_PASSWORD}}

# s3 / google cloud storage configuration (uploads)
S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID:-}
S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY:-}
S3_BUCKET=${S3_BUCKET:-}
S3_ENDPOINT=${S3_ENDPOINT:-storage.googleapis.com}

if [[ -z ${DATABASE_HOST} || -z ${DATABASE_NAME} || \
      -z ${DATABASE_USER} || -z ${DATABASE_PASSWORD} ]]; then
  echo "ERROR: "
  echo "  Please configure the database connection."
  echo "  Cannot continue without a database. Aborting..."
  exit 1
fi

if [[ -z ${S3_ACCESS_KEY_ID} || -z ${S3_SECRET_ACCESS_KEY} ||
      -z ${S3_BUCKET} || -z ${S3_ENDPOINT} ]]; then
  echo "ERROR: "
  echo "  Please configure a s3 / google cloud storage bucket."
  echo "  Cannot continue. Aborting..."
  exit 1
fi

# configure redmine database connection settings
cat > config/database.yml <<EOF
production:
  adapter: mysql2
  database: ${DATABASE_NAME}
  host: ${DATABASE_HOST}
  username: ${DATABASE_USER}
  password: "${DATABASE_PASSWORD}"
  encoding: utf8
EOF

# configure cloud storage settings
cat > config/s3.yml <<EOF
production:
  access_key_id: ${S3_ACCESS_KEY_ID}
  secret_access_key: ${S3_SECRET_ACCESS_KEY}
  bucket: ${S3_BUCKET}
  endpoint: ${S3_ENDPOINT}
EOF

# create the secret session token file
cat > config/initializers/secret_token.rb <<EOF
RedmineApp::Application.config.secret_key_base = '${REDMINE_SESSION_TOKEN}'
EOF

echo "Running database migrations..."
bundle exec rake db:migrate RAILS_ENV=production

echo "Starting redmine server..."
exec bundle exec rails server -b 0.0.0.0 -p 3000 -e production
```

This script automates the linking with the MariaDB service and sets up the Redmine database connection parameters accordingly. It also configures the Google cloud storage and performs the database migration tasks before starting up the Redmine application server.

Build this image by running:

```bash
$ docker build -t gcr.io/<google-project-name>/redmine .
```

Then push this image to the Google Container Registry:

```bash
$ gcloud docker push gcr.io/<google-project-name>/redmine
```

## Create your cluster

Now you are ready to create your Container Engine cluster on which you'll run Redmine. A cluster consists of a master API server hosted by Google and a set of worker nodes.

Create a cluster named `redmine`:

```bash
$ gcloud beta container clusters create redmine
```

A successful create response looks like:

```
Creating cluster redmine...done.
Created [.../projects/bitnami-tutorials/zones/us-central1-b/clusters/redmine].
kubeconfig entry generated for redmine.
NAME     ZONE           MASTER_VERSION  MASTER_IP      MACHINE_TYPE   STATUS
redmine  us-central1-b  0.19.3          23.251.159.83  n1-standard-1  RUNNING
```

Now that your cluster is up and running, everything is set to launch the Redmine app.

## Create MariaDB pod and service

### Create persistent disk

We will make use of [persistent disks](https://cloud.google.com/compute/docs/disks/) for MariaDB, allowing the database server to preserve its state across pod shutdown and startup.

```bash
$ gcloud compute disks create --size 200GB mariadb-disk
```

We will use the `mariadb-disk` in the MariaDB pod definition in the next step.

### MariaDB pod

The first thing that we're going to do is start up a [pod](https://cloud.google.com/container-engine/docs/pods) for MariaDB. We'll use a replication controller to create the pod—even though it's a single pod, the controller is still useful for monitoring health and restarting the pod if required.

We'll use this config file: `mariadb-controller.yml`. Take a look at its contents:

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: mariadb
  labels:
    name: mariadb
spec:
  replicas: 1
  selector:
    name: mariadb
  template:
    metadata:
      labels:
        name: mariadb
    spec:
      containers:
        - name: mariadb
          image: bitnami/mariadb
          env:
            - name: MARIADB_DATABASE
              value: redmine_production
            - name: MARIADB_USER
              value: redmine
            - name: MARIADB_PASSWORD
              value: secretpassword
          ports:
            - containerPort: 3306
              name: mariadb
          volumeMounts:
            - name: mariadb-persistent-storage
              mountPath: /bitnami/mariadb/data
          livenessProbe:
            TCPSocket:
              port: 3306
            initialDelaySeconds: 30
            timeoutSeconds: 1
      volumes:
        - name: mariadb-persistent-storage
          gcePersistentDisk:
            pdName: mariadb-disk
            fsType: ext4
```

> **Note**": You should change the value of the `MARIADB_PASSWORD` env variable to one of your choosing.

This file specifies a pod with a single container

To create the pod:

```bash
$ kubectl create -f mariadb-controller.yml
```

Check to see if the pod is running. It may take a minute to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=mariadb
NAME            READY     REASON    RESTARTS   AGE
mariadb-gfc2z   1/1       Running   0          4m
```

### MariaDB service

A [service](https://cloud.google.com/container-engine/docs/services/) is an abstraction which defines a logical set of pods and a policy by which to access them. It is effectively a named load balancer that proxies traffic to one or more pods.

When you set up a service, you tell it the pods to proxy based on pod labels. Note that the pod that you created in step one has the label `name=mariadb`.

We'll use the file `mariadb-service.yml` to create a service for MariaDB:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  labels:
    name: mariadb
spec:
  ports:
    - port: 3306
      targetPort: 3306
      protocol: TCP
  selector:
    name: mariadb
```

The `selector` field of the service configuration determines which pods will receive the traffic sent to the service. So, the configuration is specifying that we want this service to point to pods labeled with `name=mariadb`.

Start the service:

```bash
$ kubectl create -f mariadb-service.yml
```

See it running:

```bash
$ kubectl get services mariadb
NAME      LABELS         SELECTOR       IP(S)          PORT(S)
mariadb   name=mariadb   name=mariadb   10.99.254.81   3306/TCP
```

## Create Redmine pod and service

Now that you have the backend for Redmine up and running, lets set up the Redmine web servers.

### Create Google cloud storage bucket

We will be using a Google cloud storage bucket for persistence of files uploaded to our Redmine application. We will also generate a developer key which will enable the Redmine application to access bucket.

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

### Redmine pod

The controller and its pod template is described in the file `redmine-controller.yml`:

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: redmine
  labels:
    name: redmine
spec:
  replicas: 3
  selector:
    name: redmine
  template:
    metadata:
      labels:
        name: redmine
    spec:
      containers:
        - name: redmine
          image: gcr.io/bitnami-tutorials/redmine
          env:
            - name: DATABASE_NAME
              value: redmine_production
            - name: DATABASE_USER
              value: redmine
            - name: DATABASE_PASSWORD
              value: secretpassword
            - name: REDMINE_SESSION_TOKEN
              value: MySecretSessionTokenProtectsMeFromBlackHats
            - name: S3_ACCESS_KEY_ID
              value: GOOGUF56OWN3R3LFYOZE
            - name: S3_SECRET_ACCESS_KEY
              value: A+uW0XLz9Y+EHUGRUf1V2uApcI/TenhBtUnPao7i
            - name: S3_BUCKET
              value: redmine-uploads
          ports:
            - containerPort: 3000
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 30
            timeoutSeconds: 1
```

> **Note**:
> 1. Change the image name to `gcr.io/<google-project-name>/redmine` as per the build instructions in [Create a Docker container image](#create-a-docker-container-image).
> 2. Change the value of `DATABASE_PASSWORD` with the one specified for `MARIADB_PASSWORD` in `mariadb-controller.yml`
> 3. Change the value of `REDMINE_SESSION_TOKEN` to a alphanumeric string of your choosing.
> 4. Change the values of `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` and `S3_BUCKET` with the ones generated in [Create Google cloud storage bucket](#create-google-cloud-storage-bucket)

It specifies 3 replicas of the server. Using this file, you can start your Redmine servers with:

```bash
$ kubectl create -f redmine-controller.yml
```

Check to see if the pod is running. It may take a few minutes to change from `Pending` to `Running`:

```bash
$ kubectl get pods -l name=redmine
NAME            READY     REASON    RESTARTS   AGE
redmine-77gyd   1/1       Running   0          35s
redmine-fea4b   1/1       Running   0          35s
redmine-mjlft   1/1       Running   0          35s
```

Once the servers are up, you can list the pods in the cluster, to verify that they're all running:

```bash
$ kubectl get pods
```

You'll see a single MariaDB pod and three Redmine pods.

### Redmine service

As with the other pods, we want a service to group the Redmine server pods. However, this time it's different: this service is user-facing, so we want it to be externally visible. That is, we want a client to be able to request the service from outside the cluster. To accomplish this, we can set the `type: LoadBalancer` field in the service configuration.

The service specification for the Redmine is in `redmine-service.yml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redmine
  labels:
    name: redmine
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 3000
      protocol: TCP
  selector:
    name: redmine
```

Start up the service:

```bash
$ kubectl create -f redmine-service.yml
```

See it running:

```bash
$ kubectl get services redmine
NAME      LABELS         SELECTOR       IP(S)           PORT(S)
redmine   name=redmine   name=redmine   10.99.240.130   80/TCP
```

## Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Redmine service accessible from outside you have to open the firewall for port 80.

First we need to get the node prefix for the cluster using `kubectl get nodes`:

```bash
$ kubectl get nodes
NAME                             LABELS                                                  STATUS
gke-redmine-32bde88b-node-0xnf   kubernetes.io/hostname=gke-redmine-32bde88b-node-0xnf   Ready
gke-redmine-32bde88b-node-8uuw   kubernetes.io/hostname=gke-redmine-32bde88b-node-8uuw   Ready
gke-redmine-32bde88b-node-hru2   kubernetes.io/hostname=gke-redmine-32bde88b-node-hru2   Ready
```

The value of `--target-tag` in the command below is the node prefix for the cluster up to `-node`.

```bash
$ gcloud compute firewall-rules create --allow=tcp:80 \
    --target-tags=gke-redmine-XXXX-node redmine
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
IP:                     0.99.249.169
LoadBalancer Ingress:   104.197.21.152
Port:                   <unnamed> 80/TCP
NodePort:               <unnamed> 31322/TCP
Endpoints:              10.96.0.5:3000,10.96.0.6:3000,10.96.2.4:3000
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

  1. Delete the firewall rule:

  ```bash
  $ gcloud compute firewall-rules delete redmine
  ```

  2. Delete the services:

  ```bash
  $ kubectl delete service redmine
  $ kubectl delete service mariadb
  ```

  3. Delete the controller:

  ```bash
  $ kubectl delete rc redmine
  $ kubectl delete rc mariadb
  ```

  4. Delete your cluster:

  ```bash
  $ gcloud beta container clusters delete redmine
  ```

  5. Delete the disks:

  ```bash
  $ gcloud compute disks delete mariadb-disk
  ```

  6. Delete the bucket and developer key from the [Google Developers Console](https://console.developers.google.com/)
