# macOS with Colima

Install host tools:

```bash
brew install colima docker docker-compose docker-buildx jq
```

If docker compose/buildx is unavailable, follow the Homebrew formula's caveats for adding its plugin directory to Docker's host cliPluginsExtraDirs. Never mount that host config into a box.

From the repository, start a VM sharing only workspaces:

```bash
colima start --vm-type vz --cpu 4 --memory 8 --disk 60 --mount "$PWD/workspaces:w"
docker context use colima
colima ssh -- ls /Users
```

The check must not expose the mounted host home. /Users can be absent or contain ancestor directories needed for the workspace path. If it lists your host username, verify the actual mounts:

```bash
colima ssh -- findmnt -o TARGET,SOURCE,FSTYPE
```

An ancestor directory for a workspace mount is not itself a home mount. Refuse any mount exposing the home root, its private files or host /tmp. If mounts are broader than intended:

```bash
colima stop
colima start --edit
```

Replace the mounts list with just the absolute workspace folder:

```yaml
mounts:
  - location: /absolute/path/to/agent-box/workspaces
    writable: true
```

Do not leave it empty: documented defaults can mount the home. Repeat both checks before make up. Custom workspace locations require sharing just those folders. Disable other runtimes or select the colima context.

Containers see only their own workspace at /workspace. Named volumes live on the VM disk; deleting the VM can delete them.

Sources: [configuration](https://colima.run/docs/configuration/), [mount defaults](https://github.com/abiosoft/colima/blob/main/embedded/defaults/colima.yaml).
