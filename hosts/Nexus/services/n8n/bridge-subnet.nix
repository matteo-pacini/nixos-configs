# Subnet of the podman network n8n runs on (nexus-n8n_default).
#
# Podman allocates a subnet per network in creation order, and the network is
# torn down and recreated on every stop (see ExecStop in docker-compose.nix),
# so the value drifts the moment another podman network exists at recreation
# time. Three places depend on it: the network itself, the metrics vhost's
# source-IP gate in ../caddy.nix, and the fail2ban exemption in
# ../fail2ban.nix. Two of those fail silently and identically when it drifts —
# the agent starts collecting 403s and is then banned for collecting them.
#
# Pinning to the value podman already chose makes this a no-op today: the
# create only runs when `podman network inspect` fails.
"10.89.0.0/24"
