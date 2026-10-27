# Jenkins controller with every tool the pipeline needs baked in, so builds are reproducible.
FROM jenkins/jenkins:lts-jdk17
USER root
ARG TARGETARCH=amd64
ARG KUBECTL_VERSION=v1.30.4
ARG HELM_VERSION=v3.15.4
ARG GITLEAKS_VERSION=8.18.4

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg git jq docker.io nodejs npm python3 \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl
# helm
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf /tmp/linux-${TARGETARCH}
# trivy (vulnerability scanner)
RUN curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
# gitleaks (secret scanner)
RUN GL_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
       | tar -xz -C /usr/local/bin gitleaks

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
