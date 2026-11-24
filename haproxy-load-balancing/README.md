## HAProxy load balancing example

HAProxy in front of small [whoami](https://github.com/traefik/whoami) containers. Each response shows which container served it.

### Usage
1. Make sure you have Docker installed
2. Run `docker compose up -d`
3. Run `curl localhost:3000` a few times and see each time we're being served by a different server (`Name: node1` / `node2`)
4. Open the stats page at [localhost:8404](http://localhost:8404) to see the backends and their health
5. Explore the `haproxy/haproxy.cfg` file and see how the load balancing is configured

Other setups: `./run.sh docker-compose-3.yml` (3 servers) or `./run.sh docker-compose-acl.yml` (routing by path: `/node-moti`, `/node-yossi`, or `?node=moti`).

### Exercises
- Stop a server (`docker compose stop node1`), watch it turn red on the stats page, and see traffic go only to the healthy one. Requests in the first few seconds may hang: health checks need a few failures (`fall 3`, every 2s by default) before a server is marked DOWN.
- Add another instance to the loop and make sure the load balancer sends traffic to it.
- Make the session sticky (same user gets responses from the same server) - you can use cookies.

### References
* [HAProxy configuration manual](https://docs.haproxy.org/3.2/configuration.html)
* [HAProxy official Docker image](https://hub.docker.com/_/haproxy)
