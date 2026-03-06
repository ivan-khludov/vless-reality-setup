FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update && \
    apt-get install -y \
      systemd systemd-sysv \
      sudo curl jq git iproute2 ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

VOLUME ["/sys/fs/cgroup", "/run", "/run/lock"]

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]

