# Makefile for installing dependencies and setting up Podman VM and Kind cluster

# Variables
BREW := /opt/homebrew/bin/brew
K8s_PROVIDER := minikube
PODMAN_MACHINE_NAME := podman-local-k8s
PODMAN_CPUS := 6
PODMAN_DISK := 100
PODMAN_MEM := 14000
PODMAN_ROOT := true
KIND_EXPERIMENTAL_PROVIDER := podman
MINIKUBE_CPUS := max
MINIKUBE_MEM := max
MINIKUBE_DISK := 60g
MINIKUBE_PORTS := 30000-30001:30000-30001,30860-30862:30860-30862,30870-30871:30870-30871

# Targets
.PHONY: install_deps setup_cluster stop_cluster start_cluster cleanup deploy_kafka deploy_prometheus deploy_grafana deploy_airflow
all: install_deps setup_cluster deploy_kafka deploy_prometheus deploy_grafana deploy_airflow

# Target to install dependencies listed in Brewfile
install_deps:
	@if [ ! -x "$(BREW)" ]; then \
		echo "Error: Brew is not installed. Please install Brew before running this target."; \
		exit 1; \
	fi

	@echo "Installing dependencies listed in Brewfile..."
	@brew bundle

	@echo "Add Helm Chart Repositories..."
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	@helm repo add grafana https://grafana.github.io/helm-charts
	@helm repo add airflow-stable https://airflow-helm.github.io/charts
	@helm repo up

# Target to create Podman virtual machine and Kind cluster
setup_cluster: install_deps
	@echo "Creating Podman virtual machine..." 
	@if ! podman machine list | grep -q $(PODMAN_MACHINE_NAME); then \
		podman machine init --cpus $(PODMAN_CPUS) --disk-size $(PODMAN_DISK) --memory $(PODMAN_MEM) --rootful=$(PODMAN_ROOT) --volume $(HOME):$(HOME) $(PODMAN_MACHINE_NAME); \
	else \
		echo "Podman virtual machine was already created."; \
	fi

	@echo "Check Podman virtual machine status..." 
	@if podman machine inspect $(PODMAN_MACHINE_NAME) | grep -q '"State": "running"'; then \
		echo "Podman virtual machine is already running."; \
	else \
		echo "Podman virtual machine is not running. Starting it now..."; \
		podman machine start $(PODMAN_MACHINE_NAME); \
		podman system connection default $(PODMAN_MACHINE_NAME)-root; \
	fi

	@if [ "$(K8s_PROVIDER)" = "kind" ]; then \
		echo "⚠️  WARNING: Make sure the system helper service is installed or set DOCKER_HOST in order to use Podman with Docker CLI. Press [ENTER] to continue or Ctrl+C to abort."; \
		read -p "" dummy; \
		echo "Creating Kind cluster..."; \
		if kind get clusters -q | grep -q 'local-k8s'; then \
			echo "Kind cluster already exist."; \
		else \
			kind create cluster --config=kind-cluster.yaml; \
		fi; \
	else \
		echo "Creating minikube cluster..."; \
		minikube start --memory=$(MINIKUBE_MEM) --cpus=$(MINIKUBE_CPUS) --disk-size=$(MINIKUBE_DISK) --ports=$(MINIKUBE_PORTS) --driver=podman --container-runtime=cri-o --profile=k8s-local; \
	fi

# Target to destroy Podman virtual machine and Kind cluster
cleanup:
	@if [ "$(K8s_PROVIDER)" = "kind" ]; then \
		echo "Destroying Kind cluster..."; \
		if kind get clusters -q | grep -q 'local-k8s'; then \
			kind delete cluster --name local-k8s; \
		else \
			echo "Kind cluster not found."; \
		fi; \
	else \
		echo "Destroying Minikube cluster..."; \
		minikube stop --profile=k8s-local; \
		minikube delete --profile=k8s-local; \
	fi

	@echo "Check Podman virtual machine status..." 
	@if podman machine inspect $(PODMAN_MACHINE_NAME) | grep -q '"State": "running"'; then \
		echo "Stoping it now..."; \
		podman machine stop $(PODMAN_MACHINE_NAME); \
	else \
		echo "Podman virtual machine is not running."; \
	fi

	@echo "Deleting Podman virtual machine..." 
	@if ! podman machine list | grep -q $(PODMAN_MACHINE_NAME); then \
		echo "Podman virtual machine not detected."; \
	else \
		podman machine rm -f $(PODMAN_MACHINE_NAME); \
	fi

# Target to stop Podman and Minikube 
stop_cluster:
	@if [ "$(K8s_PROVIDER)" = "kind" ]; then \
		echo "Not Supported with Kind!"; \
		exit 1; \
	fi

	@echo "Check Minikube status..." 
	@if minikube status --profile k8s-local | grep -q 'Running'; then \
		echo "Stoping it now..."; \
		minikube stop --profile k8s-local; \
	else \
		echo "Minikube is not running."; \
	fi


	@echo "Check Podman virtual machine status..." 
	@if podman machine inspect $(PODMAN_MACHINE_NAME) | grep -q '"State": "running"'; then \
		echo "Stoping it now..."; \
		podman machine stop $(PODMAN_MACHINE_NAME); \
	else \
		echo "Podman virtual machine is not running."; \
	fi

# Target to start Podman and Minikube 
start_cluster:
	@if [ "$(K8s_PROVIDER)" = "kind" ]; then \
		echo "Not Supported with Kind!"; \
		exit 1; \
	fi

	@echo "Check Podman virtual machine status..." 
	@if podman machine inspect $(PODMAN_MACHINE_NAME) | grep -q '"State": "running"'; then \
		echo "Podman virtual machine is already running."; \
	else \
		echo "Starting it now..."; \
		podman machine start $(PODMAN_MACHINE_NAME); \
	fi

	@echo "Check Minikube status..." 
	@if minikube status --profile k8s-local | grep -q 'Running'; then \
		echo "Minikube is already running."; \
	else \
		echo "Starting it now..."; \
		minikube start --profile k8s-local; \
	fi


# Target to deploy Kafka helm chart
deploy_kafka: install_deps
	@echo "Deploying Kafka Helm Chart..."
	@if kubectl cluster-info; then \
		helm upgrade --install kafka -f kafka.yaml oci://registry-1.docker.io/bitnamicharts/kafka; \
	else \
		echo "No Kubernetes context in use."; \
		exit 1;\
	fi \

# Target to deploy prometheus helm chart
deploy_prometheus: install_deps
	@echo "Deploying Prometheus Helm Chart..."
	@if kubectl cluster-info; then \
		helm upgrade --install promehteus -f prometheus.yaml prometheus-community/prometheus; \
	else \
		echo "No Kubernetes context in use."; \
		exit 1;\
	fi \

# Target to deploy grafana helm chart
deploy_grafana: install_deps
	@echo "Deploying Grafana Helm Chart..."
	@if kubectl cluster-info; then \
		helm upgrade --install grafana -f grafana.yaml grafana/grafana; \
	else \
		echo "No Kubernetes context in use."; \
		exit 1;\
	fi \

# Target to deploy Airflow helm chart
deploy_airflow: install_deps
	@echo "Deploying Airflow Helm Chart..."
	@if kubectl cluster-info; then \
		helm upgrade --install airflow -f airflow.yaml airflow-stable/airflow; \
	else \
		echo "No Kubernetes context in use."; \
		exit 1;\
	fi

# Help target to display available targets and their descriptions
help:
	@echo "Available targets:"
	@echo "  - install_deps: Install dependencies listed in Brewfile"
	@echo "  - setup_cluster: Create Podman virtual machine and Kind cluster"
	@echo "  - stop_cluster: Stop Podman and Minikube"
	@echo "  - start_cluster: Stop Podman and Minikube"
	@echo "  - deploy_kafka: Deploys Kafka using Helm."
	@echo "  - deploy_prometheus: Deploys Prometheus using Helm."
	@echo "  - deploy_grafana: Deploys Grafana using Helm."
	@echo "  - deploy_airflow: Deploys Airflow using Helm."
	@echo "  - all: Run all the targest above."
	@echo "  - cleanup: Remove Podman virtual machine and Kind cluster"

# Default target
.DEFAULT_GOAL := help

