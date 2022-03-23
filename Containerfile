ARG EE_BASE_IMAGE=quay.io/ansible/ansible-runner:latest
ARG EE_BUILDER_IMAGE=quay.io/ansible/ansible-builder:latest

FROM $EE_BASE_IMAGE as galaxy
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=
USER root

ADD _build /build
WORKDIR /build

RUN ansible-galaxy role install -r requirements.yml --roles-path /usr/share/ansible/roles \
    && ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path /usr/share/ansible/collections

FROM $EE_BUILDER_IMAGE as builder

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY _build/requirements.txt _build/bindep.txt /
RUN ansible-builder introspect --sanitize --user-pip=requirements.txt --user-bindep=bindep.txt --write-bindep=/tmp/src/bindep.txt --write-pip=/tmp/src/requirements.txt \
    && assemble

FROM $EE_BASE_IMAGE
USER root

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY --from=builder /output/ /output/
RUN /output/install-from-bindep \
    && rm -rf /output/wheels \
    && alternatives --set python /usr/bin/python3 \
    && dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo \
    && dnf config-manager --set-disabled docker-ce-stable \
    && rpm --install --nodeps --replacefiles --excludepath=/usr/bin/runc https://download.docker.com/linux/centos/8/x86_64/stable/Packages/containerd.io-1.5.10-3.1.el8.x86_64.rpm \
    && dnf --assumeyes --enablerepo=docker-ce-stable install docker-ce \
    && molecule --version \
    && molecule drivers \
    && ansible-lint --version \
    && docker --version \
    && podman --version \
    && git --version
