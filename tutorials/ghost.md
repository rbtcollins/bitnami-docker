[TOC]

# Introduction

In this tutorial, we will use Bitnami containers to run the
<a href="https://ghost.org" target="_blank">Ghost blogging platform</a>, taking advantage of Docker
features such as linking and volumes.

### [node](https://github.com/bitnami/bitnami-docker-node)

Since Ghost is a node.js application, we will use the node container to run it.

### [MariaDB](https://github.com/bitnami/bitnami-docker-mariadb)

We will link node to a MariaDB container for Ghost to use as it's data store.

### [nginx](https://github.com/bitnami/bitnami-docker-nginx)

We will serve our Ghost app through an nginx server which we will make accessible to the host
machine. nginx will act as a reverse proxy to our node container that will run the Ghost server.

# Setting up Ghost

### Step 1: Download Ghost

Create an new project directory that will contain our app's content.

```bash
mkdir docker-ghost
cd docker-ghost
```

The latest version of Ghost can be downloaded from GitHub
<a href="https://ghost.org/download" target="_blank">https://ghost.org/download</a>.
Download and save the archive in your project directory using your browser, or command line.

```bash
curl -LO https://ghost.org/zip/ghost-0.6.4.zip
```

Next, unzip the archive into a subfolder named `ghost` in your project directory.

```bash
unzip ghost-0.6.4.zip -d ghost
```

### Step 2: Configure Ghost's database credentials

By default Ghost is setup to use a local sqlite database, since we are using MariaDB, we need to
change the configuration. We also need to tell Ghost to accept remote connections and use the port
exposed by the node container (3000), since we'll be reverse proxying from the nginx container.

Copy or rename the example configuration in the `ghost` subfolder.

```bash
cp ghost/config.example.js ghost/config.js
```

Next, edit `config.js` and replace the database and server configuration blocks for production with
the following:

```js
database: {
  client: 'mysql',
  connection: {
    host: 'mariadb',
    user: 'root',
    password: 'my-password',
    database: 'ghost'
  },
  debug: false
},
server: {
  host: '0.0.0.0',
  port: '3000'
}
```

Notice that the hostname we've used for our database connection is `mariadb`, we will use this when
setting up the link between our MariaDB and node containers. We also specify a password and
database, which we will pass as environment variables to the MariaDB container.

# Creating an nginx virtual host

The next step is to create a virtual host for the nginx container to reverse proxy to our node
container. The nginx container contains some example configurations, we will use and modify the node
app example.

### Step 1: Copy and save the virtual host configuration

Create a subfolder in your project directory for the nginx configuration called `nginx-vhost`.

```bash
mkdir nginx-vhost
```

Copy and save the text below into `nginx-vhost/ghost.conf`.

```nginx
server {
    listen 0.0.0.0:80;
    server_name my-ghost-blog.com;

    location / {
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header HOST $http_host;
        proxy_set_header X-NginX-Proxy true;

        proxy_pass http://ghost:3000;
        proxy_redirect off;
    }
}
```

The hostname we are proxying to is `ghost`, which we also use when setting up the link between our
nginx and node containers.

# Using Docker Compose

The easiest way to get up and running is using
<a href="https://docs.docker.com/compose/" target="_blank">Docker Compose</a>. It uses one YAML file
to define the different containers your application will use, the way they are configured as well
as the links between different containers.

### Step 1: Install Docker Compose

Follow this guide for installing Docker Compose.

- <a href="https://docs.docker.com/compose/install/" target="_blank">https://docs.docker.com/compose/install/</a>

### Step 2: Copy Docker Compose definition

Copy the definition below and save it as `docker-compose.yml` in your project directory.

```less
mariadb:
  image: bitnami/mariadb
  environment:
    - MARIADB_DATABASE=ghost
    - MARIADB_PASSWORD=my-password

ghost:
  image: bitnami/node
  links:
    - mariadb:mariadb
  volumes:
    - ghost:/app
  command: "sh -c 'npm install --production && npm start --production'"

nginx:
  image: bitnami/nginx
  links:
    - ghost:ghost
  ports:
    - 80:80
  volumes:
    - nginx-vhost:/bitnami/nginx/conf/vhosts
```

In this Docker Compose definition, we used the `volumes` property to mount the Ghost app and
our nginx virtual host.

`MARIADB_DATABASE` and `MARIADB_PASSWORD` are environment variables that the MariaDB image takes to
setup a database and password for the root user on first run. We used the same credentials we
defined in the [Ghost config.js file](#step-2-configure-ghosts-database-credentials).

Using the `links` property, we defined links between node and MariaDB, and nginx and node. We used
the same hostnames we used earlier when setting up the
[database credentials](#step-2-configure-ghosts-database-credentials) and
[nginx virtual host](#step-1-copy-and-save-the-virtual-host-configuration).

Finally, we expose port 80 for nginx to port 80 on the host, allowing us to access Ghost from the
host machine.

### Step 3: Running Docker Compose

It's really easy to start a Docker Compose app.

```bash
docker-compose up
```

Docker Compose will show log output from all the containers in your application.

### Step 4: Access your Ghost instance

To access the `server_name` we set up in our virtual host, you may need to create an entry in your
`/etc/hosts` file to point `my-ghost-blog.com` to localhost.

```bash
echo '127.0.0.1 my-ghost-blog.com' | sudo tee -a /etc/hosts
```

Now that everything is up and running, navigate to
<a href="http://my-ghost-blog.com/ghost" target="_blank">http://my-ghost-blog.com/ghost</a> or in
your browser to access your new Ghost instance!
