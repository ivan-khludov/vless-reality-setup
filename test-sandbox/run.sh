#!/usr/bin/env bash
set -euo pipefail

image_name="vless-reality-test-sandbox"
container_name="vless-reality-test-sandbox"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not found in PATH." >&2
  exit 1
fi

echo "Building test sandbox image: ${image_name}..."
echo "(Uses host network for apt; first build may take a few minutes.)"
docker build --network=host -t "${image_name}" -f "${script_dir}/Dockerfile" "${script_dir}"

echo
echo "Starting sandbox container '${container_name}' with systemd as PID 1..."
echo "Repository is mounted at /opt/vless-reality-setup inside the container."
echo
echo "Inside the container you can run:"
echo "  cd /opt/vless-reality-setup"
echo "  sudo ./bin/vless-manager.sh"
echo

# Ensure no leftover container with the same name.
docker rm -f "${container_name}" >/dev/null 2>&1 || true

# Start container in the background with systemd (/sbin/init) as PID 1.
# Use host network and cgroup namespace so systemd can manage services normally.
docker run -d --privileged \
  --name "${container_name}" \
  --hostname "${container_name}" \
  --add-host="${container_name}:127.0.0.1" \
  --network=host \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock \
  -v "${repo_root}":/opt/vless-reality-setup \
  "${image_name}" >/dev/null

cleanup() {
  docker stop "${container_name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Waiting for sandbox container to start..."
for i in {1..20}; do
  if docker ps --format '{{.Names}}' | grep -qx "${container_name}"; then
    break
  fi
  sleep 0.5
done

if ! docker ps --format '{{.Names}}' | grep -qx "${container_name}"; then
  echo "Container '${container_name}' failed to start. Run 'docker logs ${container_name}' for details." >&2
  exit 1
fi

# Attach an interactive shell inside the running container.
docker exec -it "${container_name}" bash -lc 'cd /opt/vless-reality-setup && exec bash'

