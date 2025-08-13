> podman info | grep -A 20 -B 5 "buildah\|conmon\|runtime"
host:
  arch: amd64
  buildahVersion: 1.38.0
  cgroupControllers:
  - cpu
  - memory
  - pids
  cgroupManager: cgroupfs
  cgroupVersion: v2
  conmon:
    package: conmon_2.1.6+ds1-1_amd64
    path: /usr/bin/conmon
    version: 'conmon version 2.1.6, commit: unknown'
  cpuUtilization:
    idlePercent: 79.73
    systemPercent: 8.88
    userPercent: 11.39
  cpus: 4
  databaseBackend: sqlite
  distribution:
    codename: bookworm
    distribution: debian
    version: "12"
  eventLogger: file
  freeLocks: 2041
  hostname: vbox
  idMappings:
    gidmap:
    - container_id: 0
      host_id: 1003
      size: 1
    - container_id: 1
      host_id: 231072
> podman info | grep -i health
dockeruser vbox:~/Projects/XCS/Dev/version10 main 
> conmon --help | grep -i health || echo "No health option in conmon --help | grep -i health || echo "No health option in conmon"
No health option in conmon

> which conmon
/usr/bin/conmon
> ls -la /usr/bin/conmon
156K -rwxr-xr-x 1 root root 153K Feb 11  2023 /usr/bin/conmon
> strings /usr/bin/conmon | grep -i health || echo "No health strings /usr/bin/conmon | grep -i health || echo "No health strings found"
No health strings found
> podman run -d --name test-systemd \
  --health-cmd="systemctl --version" \
  --health-interval=10s \
  alpine:latest sleep 60
Resolved "alpine" as an alias (/home/dockeruser/.cache/containers/short-name-aliases.conf)
Trying to pull docker.io/library/alpine:latest...
Getting image source signatures
Copying blob 9824c27679d3 skipped: already exists  
Copying config 9234e8fb04 done   | 
Writing manifest to image destination
58f88a596649217b24d75c359fca011b898335c1529848089a2f4c647cd5a83e
> sleep 15
dockeruser vbox:~/Projects/XCS/Dev/version10 main 
> podman inspect test-systemd --format '{{json .State.Health}}podman inspect test-systemd --format '{{json .State.Health}}' | jq
{
  "Status": "starting",
  "FailingStreak": 0,
  "Log": null
}