# Use the base execution environment image (defaults to Red Hat AAP 2.4 minimal EE)
ARG EE_BASE_IMAGE=registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9:latest
FROM $EE_BASE_IMAGE

# Set build arguments
ARG OFFLINE_BUILD=false
ARG PACKER_VERSION=1.14.2
ARG INSTALL_PACKER_PLUGINS=true
ARG INSTALL_COLLECTIONS=true

# Set labels
LABEL name="ansible-ee-packer" \
    version="3.3.12" \
    description="Custom Ansible Execution Environment with Packer 1.14.2, VMware SSL support, sshpass, and Packer plugins" \
      maintainer="root" \
    created="2025-09-14T00:00:00Z"

# Switch to root for installations
USER root

# Install system dependencies (supports Debian/Ubuntu and RHEL-based images)
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends \
            curl \
            openssh-client \
            sshpass \
            ca-certificates \
            python3-pip \
        && rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
        # RHEL 9 with microdnf - skip curl as curl-minimal is already installed
        microdnf install -y --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
            openssh-clients \
            sshpass \
            ca-certificates \
            python3-pip \
        && microdnf clean all; \
    elif command -v dnf >/dev/null 2>&1; then \
        # RHEL with dnf - skip curl as curl-minimal is already installed  
        dnf -y --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install \
            openssh-clients \
            sshpass \
            ca-certificates \
            python3-pip \
        && dnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
        yum -y --setopt=tsflags=nodocs install \
            curl \
            openssh-clients \
            sshpass \
            ca-certificates \
            python3-pip \
        && yum clean all; \
    else \
        echo "Unsupported base image: no known package manager found" >&2; exit 1; \
    fi

# Ensure a common CA bundle path for Python/Requests across distros
RUN set -eux; \
    if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then \
        if [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then \
            mkdir -p /etc/ssl/certs && ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt || true; \
        elif [ -f /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ]; then \
            mkdir -p /etc/ssl/certs && ln -sf /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/ssl/certs/ca-certificates.crt || true; \
        fi; \
    fi

# Install Python packages from requirements.txt (includes ansible-core upgrade)
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --upgrade --no-cache-dir pip && \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    python3 -m pip install --no-cache-dir jmespath 'requests[security]' && \
    rm -f /tmp/requirements.txt && \
    ansible --version

# Install HashiCorp Packer using curl (avoid package manager network issues)
# For air-gapped environments, set OFFLINE_BUILD=true and pre-copy packer binary to context
ARG PACKER_VERSION=1.14.2
RUN if [ "$OFFLINE_BUILD" = "false" ]; then \
        curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" -o /tmp/packer.zip && \
        cd /tmp && \
        python3 -m zipfile -e packer.zip . && \
        mv packer /usr/local/bin/packer && \
        chmod +x /usr/local/bin/packer && \
        rm packer.zip; \
    else \
        echo "Offline build: expecting packer binary in /usr/local/bin/"; \
    fi && \
    packer version

# Install Packer plugins to a single system path to avoid duplication
ENV PACKER_PLUGIN_PATH=/opt/packer/plugins
RUN mkdir -p "$PACKER_PLUGIN_PATH" && \
    if [ "$OFFLINE_BUILD" = "false" ] && [ "$INSTALL_PACKER_PLUGINS" = "true" ]; then \
        PACKER_PLUGIN_PATH="$PACKER_PLUGIN_PATH" packer plugins install github.com/hashicorp/vsphere && \
        PACKER_PLUGIN_PATH="$PACKER_PLUGIN_PATH" packer plugins install github.com/hashicorp/ansible; \
    else \
        echo "Skipping plugin installation (offline or INSTALL_PACKER_PLUGINS=false)"; \
    fi && \
    PACKER_PLUGIN_PATH="$PACKER_PLUGIN_PATH" packer plugins installed

# Create custom directories
RUN mkdir -p /opt/custom-scripts \
             /opt/custom-configs \
             /usr/share/ansible/collections

# Install Ansible collections
COPY requirements.yml /tmp/requirements.yml
# Copy collections directory (may contain local .tar.gz files)
COPY collections/ /tmp/collections/

RUN if [ "$INSTALL_COLLECTIONS" = "true" ]; then \
        # Install local collections first (if any .tar.gz files exist)
        if ls /tmp/collections/*.tar.gz 1> /dev/null 2>&1; then \
            echo "=== Installing local collections ===" && \
            for collection in /tmp/collections/*.tar.gz; do \
                echo "Installing local collection: $(basename $collection)" && \
                ansible-galaxy collection install "$collection" \
                    --collections-path /usr/share/ansible/collections \
                    --force; \
            done; \
        else \
            echo "No local .tar.gz collections found"; \
        fi && \
        echo "=== Installing collections from requirements.yml ===" && \
        ansible-galaxy collection install -r /tmp/requirements.yml \
            --collections-path /usr/share/ansible/collections \
            --force && \
        echo "=== Final collection verification ===" && \
        ansible-galaxy collection list && \
        echo "=== Testing json_query filter ===" && \
        ansible localhost -m debug -a "msg={{ ['test'] | ansible.utils.json_query('[0]') }}" || \
        echo "Collection installation completed"; \
    else \
        echo "Skipping Ansible collections per INSTALL_COLLECTIONS=false"; \
    fi && \
    rm -rf /tmp/collections

# Keep requirements.yml for runtime use
COPY requirements.yml /opt/requirements.yml

# Set custom environment variables
ENV ANSIBLE_COLLECTIONS_PATH="/usr/share/ansible/collections" \
    PYTHONHTTPSVERIFY=1 \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Display final installation summary
RUN echo "=== FINAL INSTALLATION SUMMARY ===" && \
    echo "Ansible version:" && ansible --version && \
    echo && \
    echo "Packer version:" && packer version && \
    echo && \
    echo "Installed collections:" && \
    ansible-galaxy collection list && \
    echo && \
    echo "Python packages:" && \
    python3 -m pip list | grep -E "(ansible|packer|vmware|crypto|requests)" && \
    echo "=== BUILD COMPLETE ==="

# Ensure ansible user exists (default runtime user remains root)
RUN id -u ansible >/dev/null 2>&1 || useradd -m -u 1000 ansible
USER root

# Set working directory
WORKDIR /tmp

# Health check (optional)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ansible --version && packer version || exit 1
