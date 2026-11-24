# DB replication lab

```text
 MySQL (async, GTID)                       MongoDB (replica set rs0)
 mysql-primary ──binlog──▶ mysql-replica     mongo1 ◀──▶ mongo2 ◀──▶ mongo3
 (writable)                (super_read_only)  3 voters, majority = 2, self-electing
```

Two replication models side by side: MySQL, where promotion is a **manual** flag flip, and MongoDB, where members **elect** a primary as long as a majority survives.

All commands run from `db-replication/`. Everything goes through `docker exec`; no ports are published.

## 1. Run it

```bash
docker compose up -d --wait
```

```bash
./setup-replication.sh
```

The script (commented, safe to re-run):

1. Sets `read_only` + `super_read_only` on the replica. Even root can't write there.
2. Creates a `repl` user on the primary. That user is the entire coupling between the two servers.
3. Wipes the replica's own GTID history (first run only), then points it at the primary with `SOURCE_AUTO_POSITION=1`: GTID-based, no binlog file names or offsets.
4. Checks `SHOW REPLICA STATUS`: `Replica_IO_Running` (fetching binlog events) and `Replica_SQL_Running` (applying them) must both be `Yes`. Two threads, two kinds of lag.
5. Runs one `rs.initiate` on `mongo1` listing all three members; they elect a primary on their own.

## 2. MySQL: watch replication

```bash
docker exec mysql-primary mysql -e "
  CREATE DATABASE shop;
  CREATE TABLE shop.orders (id INT PRIMARY KEY AUTO_INCREMENT, item VARCHAR(50));
  INSERT INTO shop.orders (item) VALUES ('keyboard'), ('mouse');"
```

```bash
docker exec mysql-replica mysql -e "SELECT * FROM shop.orders"
```

Rows are there within a second. Compare GTID sets:

```bash
docker exec mysql-primary mysql -Ne "SELECT @@gtid_executed"
```

```bash
docker exec mysql-replica mysql -Ne "SELECT @@gtid_executed"
```

Identical = fully caught up. This is the honest lag check; `Seconds_Behind_Source` is only an estimate.

## 3. MySQL: the guard rail

```bash
docker exec mysql-replica mysql -e "INSERT INTO shop.orders (item) VALUES ('monitor')"
```

`ERROR 1290 ... --super-read-only` — root can't write either. Replication still applies, because the applier thread isn't a client write.

## 4. MySQL: promote the replica

Kill the primary:

```bash
docker stop mysql-primary
```

Promote (in production, wait for the relay log to drain before `STOP REPLICA`):

```bash
docker exec mysql-replica mysql -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  SET GLOBAL super_read_only=OFF;
  SET GLOBAL read_only=OFF;"
```

```bash
docker exec mysql-replica mysql -e "INSERT INTO shop.orders (item) VALUES ('promoted!'); SELECT * FROM shop.orders"
```

Promotion was a flag flip and an unbind. No election, no quorum, and nothing stops the old primary from also accepting writes when it comes back (it boots writable here). That gap is where split brain comes from; real setups start every server `read_only=ON` and let only the promotion procedure unset it.

## 5. MongoDB: automatic failover

```bash
docker exec mongo1 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, "->", m.stateStr))'
```

Kill the primary (`mongo1` if it won the first election):

```bash
docker stop mongo1
```

After ~15s, ask a survivor:

```bash
docker exec mongo2 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, "->", m.stateStr))'
```

2 of 3 is a majority, so they elected a new primary. No human involved.

## 6. MongoDB: lose the majority

```bash
docker stop mongo2
```

After ~15s:

```bash
docker exec mongo3 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, "->", m.stateStr))'
```

`mongo3` stays `SECONDARY`: healthy, up to date, and unable to elect itself, since 1 of 3 isn't a majority. This is what a surviving site looks like after losing the other two members.

## 7. MongoDB: forced reconfig

Shrink the set to just the survivor:

```bash
docker exec mongo3 mongosh --quiet --eval '
  cfg = rs.conf();
  cfg.members = cfg.members.filter(m => m.host == "mongo3:27017");
  rs.reconfig(cfg, {force: true})'
```

After ~10s:

```bash
docker exec mongo3 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, "->", m.stateStr))'
```

`mongo3` is `PRIMARY`. `force: true` skips the majority check, so if the "dead" members are actually alive somewhere, you now have two primaries. Only run it when you know they're gone.

## Gotchas

- **`Authentication requires secure connection`** on the replica: MySQL 8's `caching_sha2_password` needs TLS or the source's public key. The script passes `GET_SOURCE_PUBLIC_KEY=1`.
- **Errant GTIDs**: a fresh replica has its own transactions (from container init). Without the `RESET MASTER` in the script, the replica's GTID set would never equal the primary's, and failover tools would flag it as diverged.
- **Mongo from your laptop**: the replica set config stores `mongo1:27017` etc., which resolve only inside the Docker network. A driver connecting from outside discovers hosts it can't reach, so use `docker exec`.

## Not covered

Cross-region latency, TLS on replication, semi-sync replication, and priority-0 / hidden Mongo members (set `priority: 0` on a member in `rs.conf()` to try it).

## Cleanup

```bash
docker compose down -v
```
