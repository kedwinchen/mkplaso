OCI_ENGINE := podman
OCI_SPEC := Containerfile
OCI_IMAGE := mkplaso

.PHONY: all
all: build

.PHONY: clean
clean:
	$(OCI_ENGINE) rmi $(OCI_IMAGE)

.PHONY: oci-build
oci-build:
	$(OCI_ENGINE) build -t $(OCI_IMAGE) -f $(OCI_SPEC) .
