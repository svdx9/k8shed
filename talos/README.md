# talos configuration

specific details for my thinkcentre cluster (disk, nic)

image factory URL used: https://factory.talos.dev/?arch=amd64&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Fnfs-utils&extensions=siderolabs%2Fnfsd&platform=metal&target=metal&version=1.12.1

reminder to self: note the .sops.yaml file in this dir, make sure am in the correct directory when encrypt/decrypt configurations in place:

## encrypt

```
sops --encrypt --in-place controlplane.yaml
sops --encrypt --in-place worker.yaml
sops --encrypt --in-place talosconfig
```

## decrypt

```
sops --decrypt controlplane.yaml
sops --decrypt worker.yaml
sops --decrypt talosconfig
```
