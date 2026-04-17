# ansible-ee-packer

Ansible Execution Environment with HashiCorp Packer, VMware support, `sshpass`,
and Packer plugins (`hashicorp/vsphere`, `hashicorp/ansible`).

- Version: **3.3.12**
- Base: `registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9:latest`
- Packer: **1.14.2**

## Usage

```bash
docker login registry.redhat.io   # base image auth
./build.sh                        # build
./test.sh                         # smoke test
./build.sh --push                 # build + push (set DOCKER_HUB_REGISTRY to override)
./build.sh --help                 # all flags
```

## Customize

- Collections → [requirements.yml](requirements.yml)
- Python packages → [requirements.txt](requirements.txt)
- System packages / build steps → [Containerfile](Containerfile)
- Offline collections: drop `.tar.gz` files in [collections/](collections), then `./build.sh --offline`
# ansible-ee-packer

Custom Ansible Execution Environment with HashiCorp Packer, VMware SSL support,
`sshpass`, and pre-installed Packer plugins. Built directly from a `Containerfile`
(ansible-builder is not used).

- **Version:** 3.3.12
- **Base image:** `registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9:latest`
- **Ansible:** provided by the AAP base image (ansible-core 2.15.x)
- **Packer:** 1.14.2 (plugins: `hashicorp/vsphere`, `hashicorp/ansible`)

## Quick start

1. Log in to `registry.redhat.io` (needed for the base image):

   ```bash
   docker login registry.redhat.io
   ```

2. Build the image:

   ```bash
   ./build.sh
   ```

3. Test it:

   ```bash
   ./test.sh
   ```

4. Build and push to your registry:

   ```bash
   ./build.sh --push
   # or override the default registry
   DOCKER_HUB_REGISTRY=your-registry.example.com/namespace ./build.sh --push
   ```

## build.sh options

| Flag | Description |
| --- | --- |
| `--push`, `-p` | Push to the registry after build |
| `--fast-push` | Use buildx + content cache to speed pushes |
| `--no-build` | Skip build, only push existing tags |
| `--no-plugins` | Skip installing Packer plugins |
| `--no-collections` | Skip installing Ansible collections |
| `--platform <list>` | Build for given platform(s), e.g. `linux/amd64,linux/arm64` |
| `--no-attest` | Disable provenance/SBOM attestations |
| `--single-tag` | Push only the version tag (skip `latest`) |
| `--offline` | Air-gapped build (expects `packer` pre-staged in image) |

Environment: `DOCKER_HUB_REGISTRY` (default `docker.io/graafnet`).

## Air-gapped build

1. Pre-download the Packer binary and place it at `/usr/local/bin/packer` in the
   build context (or modify the `Containerfile` accordingly).
2. Pre-stage any required Ansible collections as `.tar.gz` files in the
   [collections/](collections) directory — they will be installed first.
3. Build with:

   ```bash
   ./build.sh --offline
   ```

## Files

- [Containerfile](Containerfile) — image build instructions
- [build.sh](build.sh) — build/push helper
- [test.sh](test.sh) — post-build smoke tests
- [export-image.sh](export-image.sh) — save image as a portable `.tar.gz`
- [requirements.txt](requirements.txt) — Python dependencies
- [requirements.yml](requirements.yml) — Ansible collections
- [collections/](collections) — local collection tarballs for offline installs

## Customization

- **Collections:** edit [requirements.yml](requirements.yml)
- **Python packages:** edit [requirements.txt](requirements.txt)
- **System packages / extra steps:** edit [Containerfile](Containerfile)
- **Different base image:**

  ```bash
  docker build \
      --build-arg EE_BASE_IMAGE=python:3.11-slim \
      -t ansible-ee-packer:local \
      -f Containerfile .
  ```