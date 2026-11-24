#!/usr/bin/env bash
# Wires up MySQL replication (primary -> replica) and initiates the Mongo replica set.
# Run after `docker compose up -d --wait`. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

primary() { docker exec mysql-primary mysql "$@"; }
replica() { docker exec mysql-replica mysql "$@"; }
mongo() { docker exec mongo1 mongosh --quiet --eval "$1"; }

echo "== waiting for all containers to be healthy =="
docker compose --progress quiet up -d --wait

echo "== replica refuses client writes (persisted across restarts) =="
replica -e "SET PERSIST read_only=ON; SET PERSIST super_read_only=ON;"

echo "== step 1: replication user on the primary =="
# This user is the only thing the replica knows about the primary.
primary -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"

echo "== step 2: point the replica at the primary =="
# First run only: wipe the replica's own GTID history. The image's first-boot
# init ran transactions on the replica (root user, timezone tables, ...); left
# alone they are "errant" GTIDs the primary never had, and the GTID sets of the
# two servers could never be equal.
if [ -z "$(replica -e 'SHOW REPLICA STATUS')" ]; then
  replica -e "RESET MASTER;"
fi
# SOURCE_AUTO_POSITION=1 = GTID: no binlog file names, no offsets.
# GET_SOURCE_PUBLIC_KEY=1: MySQL 8 auth (caching_sha2_password) needs TLS or the
# source's public key for the handshake.
# Works under super_read_only=ON: replication config and the applier threads are
# system operations, not client writes.
replica -e "
  STOP REPLICA;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='mysql-primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1,
    GET_SOURCE_PUBLIC_KEY=1;
  START REPLICA;"

echo "== step 3: verify - both threads must say Yes =="
for _ in $(seq 1 30); do
  status=$(replica -e "SHOW REPLICA STATUS\G")
  grep -q "Replica_IO_Running: Yes" <<<"$status" && grep -q "Replica_SQL_Running: Yes" <<<"$status" && break
  sleep 1
done
grep -E "Replica_(IO|SQL)_Running:|Seconds_Behind_Source|Last_(IO|SQL)_Error:" <<<"$status"

echo
echo "== step 4: initiate the mongo replica set =="
# One rs.initiate on one member, listing all three. They heartbeat each other
# and elect a primary on their own.
mongo '
  try { rs.status(); print("already initiated") }
  catch (e) {
    rs.initiate({ _id: "rs0", members: [
      { _id: 0, host: "mongo1:27017" },
      { _id: 1, host: "mongo2:27017" },
      { _id: 2, host: "mongo3:27017" }
    ]}); print("initiated")
  }'

echo "== waiting for the election =="
mongo '
  while (!rs.status().members.some(m => m.stateStr == "PRIMARY")) sleep(1000);
  rs.status().members.forEach(m => print(m.name, "->", m.stateStr))'

echo
echo "done. see README.md for the experiments."
