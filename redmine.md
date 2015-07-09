
# Redmine Tutorial

- [Before you begin](#before-you-begin)
- [Step 1: Download the configuration files](#step-1-download-the-configuration-files)
- [Step 2: Create a Docker container image](#step-2-create-a-docker-container-image)
- [Step 3: Create your cluster](#step-3-create-your-cluster)
- [Step 4: Create MariaDB pod and service](#step-4-create-mariadb-pod-and-service)
  + [MariaDB pod](#mariadb-pod)
  + [MariaDB service](#mariadb-service)
- [Step 5: Create Redmine pod and service](#step-5-create-redmine-pod-and-service)
  + [Redmine pod](#redmine-pod)
  + [Redmine service](#redmine-service)
- [Step 6: Allow external traffic](#step-6-allow-external-traffic)
- [Step 7: Access you Redmine server](#step-7-access-you-redmine-server)
- [Step 8: Scaling the Redmine application](#step-8-scaling-the-redmine-application)
- [Cleanup](#cleanup)

This tutorial walks you through setting up [Redmine](http://redmine.org), backup by a MariaDB database and running on the Google Container Engine.

The tutorial uses the Redmine source code, turns it into a Docker container image and then runs that image on Google Container Engine.

It also shows how you can set up a web service on an external IP, load balancing to a set of replicated servers backed by replicated Redmine nodes.

## Before you begin

Follow the instructions on the [Before You Begin](https://cloud.google.com/container-engine/docs/before-you-begin) page to set up your Container Engine environment.

## Step 1: Download the configuration files

Download and unpack the `redmine.zip` file into your working directory. The ZIP file contains the configuration files used in this tutorial:

  - Dockerfile
  - run.sh
  - redmine-controller.yml
  - redmine-service.yml
  - mariadb-controller.yml
  - mariadb-service.yml

## Step 2: Create a Docker container image

Lets begin with the `Dockerfile` which will describe the Redmine image. Docker container images can extend from other existing images so for this image, we'll extend from the existing `bitnami/ruby` image. Take a look at its contents:


```dockerfile
FROM bitnami/ruby:latest
ENV REDMINE_VERSION=3.0.3

RUN curl -LO http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz -o /tmp/redmine-${REDMINE_VERSION}.tar.gz \
 && mkdir -p /home/$BITNAMI_APP_USER/redmine/ \
 && tar -xf redmine-${REDMINE_VERSION}.tar.gz --strip=1 -C /home/$BITNAMI_APP_USER/redmine/ \
 && cd /home/$BITNAMI_APP_USER/redmine \
 && cp -a config/database.yml.example config/database.yml \
 && bundle install --without development test \
 && chown -R $BITNAMI_APP_USER:$BITNAMI_APP_USER /home/$BITNAMI_APP_USER/redmine/ \
 && rm -rf /tmp/redmine-${REDMINE_VERSION}.tar.gz

COPY run.sh /home/$BITNAMI_APP_USER/redmine/run.sh
RUN sudo chmod 755 /home/$BITNAMI_APP_USER/redmine/run.sh

WORKDIR /home/$BITNAMI_APP_USER/redmine/
CMD ["/home/bitnami/redmine/run.sh"]
```

Next, lets take a look at the `run.sh` script referenced in the `Dockerfile`.

```bash
#!/bin/bash
set -e

REDMINE_SECRET_SESSION_TOKEN=${REDMINE_SECRET_SESSION_TOKEN:-JXXnKhcTWTbRgChXFkWjC3zs3PrTq47qJPgWJRsnRXgHPJCs7VrwhpMVWdmh3rhM}

# automatically fetch database parameters from bitnami/mariadb
DATABASE_HOST=${DATABASE_HOST:-${MARIADB_PORT_3306_TCP_ADDR}}
DATABASE_NAME=${DATABASE_NAME:-${MARIADB_ENV_MARIADB_DATABASE}}
DATABASE_USER=${DATABASE_USER:-${MARIADB_ENV_MARIADB_USER}}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-${MARIADB_ENV_MARIADB_PASSWORD}}

if [[ -z ${DATABASE_HOST} || -z ${DATABASE_NAME} || \
      -z ${DATABASE_USER} || -z ${DATABASE_PASSWORD} ]]; then
  echo "ERROR: "
  echo "  Please configure the database connection."
  echo "  Cannot continue without a database. Aborting..."
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

# create the secret session token file
cat > config/initializers/secret_token.rb <<EOF
RedmineApp::Application.config.secret_key_base = '${REDMINE_SECRET_SESSION_TOKEN}'
EOF

echo "Running database migrations..."
bundle exec rake db:migrate RAILS_ENV=production

echo "Starting redmine server..."
exec bundle exec rails server -b 0.0.0.0 -p 3000 -e production
```

This script will automate the linking with the MariaDB service and setup the database connection parameters accordingly. It will also perform the database migration tasks before starting up the Redmine application server.

Build this image by running:

```bash
$ docker build -t gcr.io/<google-project-name>/redmine .
```

Then push this image to the Google Container Registry:

```bash
$ gcloud docker push gcr.io/<google-project-name>/redmine
```

## Step 3: Create your cluster

Ok, now you are ready to create your Container Engine cluster on which you'll run Redmine. A cluster consists of a master API server hosted by Google and a set of worker nodes.

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

## Step 4: Create MariaDB pod and service

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
```

**You should change the password to one of your choosing.**

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
$ kubectl get services -l name=mariadb
NAME      LABELS         SELECTOR       IP(S)          PORT(S)
mariadb   name=mariadb   name=mariadb   10.99.254.81   3306/TCP
```

## Step 5: Create Redmine pod and service

Now that you have the backend for Redmine up and running, lets start the Redmine web servers.

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
            - name: REDMINE_SECRET_SESSION_TOKEN
              value: MySecretSessionTokenProtectsMeFromBlackHats
          ports:
            - containerPort: 3000
              protocol: TCP
```

**You should change the image name to `gcr.io/<google-project-name>/redmine` as per the build instructions in [Step 2: Create a Docker container image](#step-2-create-a-docker-container-image). You should also change the password to the one specified in the `mariadb-controller.yml`**

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

You'll see a single MariaDB pod, and three Redmine pods (as well as some Container Engine infrastructure pods).

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
$ kubectl get services -l name=redmine
NAME      LABELS         SELECTOR       IP(S)           PORT(S)
redmine   name=redmine   name=redmine   10.99.240.130   80/TCP
```

## Step 6: Allow external traffic

By default, the pod is only accessible by its internal IP within the cluster. In order to make the Redmine service accessible from outside you have to open the firewall for port 80.

```bash
$ gcloud compute firewall-rules create --allow=tcp:80 \
    --target-tags=gke-redmine-XXXX-node redmine
```

The value of `--target-tag` is the node prefix for the cluster up to `-node`. Find your node names with `kubectl get nodes`:

```bash
$ kubectl get nodes
NAME                             LABELS                                                  STATUS
gke-redmine-32bde88b-node-0xnf   kubernetes.io/hostname=gke-redmine-32bde88b-node-0xnf   Ready
gke-redmine-32bde88b-node-8uuw   kubernetes.io/hostname=gke-redmine-32bde88b-node-8uuw   Ready
gke-redmine-32bde88b-node-hru2   kubernetes.io/hostname=gke-redmine-32bde88b-node-hru2   Ready
```

You can alternatively open up port 80 from the [Developers Console](https://console.developers.google.com/).

## Step 7: Access you Redmine server

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

## Step 8: Scaling the Redmine application

Suppose your Redmine app has been running for a while, and it gets a sudden burst of publicity. You decide it would be a good idea to add more web servers to your Redmine. You can do this easily, since your servers are defined as a service that uses a replication controller. Resize the number of pods in the replication controller as follows.

```bash
$ kubectl scale --replicas=5 rc redmine
```

The configuration for that controller is updated, to specify that there should be 5 replicas running now. The replication controller adjusts the number of pods it is running to match that, and you will be able to see the additional pods running:

```bash
$ kubectl get pods -l name=redmine
```

Once your site has fallen back into obscurity, you can ramp down the number of web server pods in the same manner.

## Cleanup

Delete the Redmine service to clean up its external load balancer.

```bash
$ kubectl delete services redmine
```

When you're done with your cluster, you can shut it down:

```bash
$ gcloud beta container clusters delete redmine
The following clusters will be deleted.
 - [redmine] in [us-central1-b]

Do you want to continue (Y/n)?

Deleting cluster redmine...done.
Deleted [.../projects/bitnami-tutorials/zones/us-central1-b/clusters/redmine].
```

This deletes the Google Compute Engine instances that are running the cluster, and all services and pods that were running on them.

Remove the firewall rule that you created:

```bash
$ gcloud compute firewall-rules delete redmine
```
