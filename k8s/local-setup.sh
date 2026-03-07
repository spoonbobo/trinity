#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$SCRIPT_DIR/charts/trinity-platform"
VALUES_LOCAL="$CHART_DIR/values.local.yaml"
NAMESPACE="trinity-local"
RELEASE_NAME="trinity"

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-7168}"
MINIKUBE_DISK="${MINIKUBE_DISK:-40g}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── Step 1: Install Homebrew ──────────────────────────────────────────────
install_brew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew already installed"
    return
  fi
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if ! grep -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
  fi
  ok "Homebrew installed"
}

# ─── Step 2: Install required tools ───────────────────────────────────────
install_tools() {
  local tools=("docker" "minikube" "kubectl" "helm")
  local casks=("docker")
  local formulae=("minikube" "kubectl" "helm")

  for cask in "${casks[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
      ok "$cask (cask) already installed"
    else
      info "Installing $cask (cask)..."
      brew install --cask "$cask"
    fi
  done

  for formula in "${formulae[@]}"; do
    if brew list "$formula" &>/dev/null; then
      ok "$formula already installed"
    else
      info "Installing $formula..."
      brew install "$formula"
    fi
  done

  ok "All tools installed"
}

# ─── Step 3: Ensure Docker Desktop is running ─────────────────────────────
ensure_docker() {
  if docker info &>/dev/null; then
    ok "Docker Desktop is running"
    return
  fi

  info "Starting Docker Desktop..."
  open -a Docker
  local retries=0
  while ! docker info &>/dev/null; do
    retries=$((retries + 1))
    if [ $retries -gt 60 ]; then
      fail "Docker Desktop did not start within 2 minutes. Please start it manually and re-run."
    fi
    sleep 2
  done
  ok "Docker Desktop is running"
}

# ─── Step 4: Start minikube ───────────────────────────────────────────────
start_minikube() {
  if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    ok "Minikube is already running"
  else
    info "Starting minikube (cpus=$MINIKUBE_CPUS, memory=${MINIKUBE_MEMORY}MB, disk=$MINIKUBE_DISK)..."
    minikube start \
      --driver=docker \
      --cpus="$MINIKUBE_CPUS" \
      --memory="$MINIKUBE_MEMORY" \
      --disk-size="$MINIKUBE_DISK" \
      --kubernetes-version=stable
    ok "Minikube started"
  fi

  info "Enabling ingress addon..."
  minikube addons enable ingress 2>/dev/null || true
  ok "Ingress addon enabled"

  info "Enabling metrics-server addon..."
  minikube addons enable metrics-server 2>/dev/null || true
  ok "Metrics-server addon enabled"
}

# ─── Step 5: Build and load images into minikube ──────────────────────────
build_images() {
  info "Configuring shell to use minikube's Docker daemon..."
  eval "$(minikube docker-env)"

  local images=(
    "trinity-auth-service:latest|$PROJECT_ROOT/web/auth-service"
    "trinity-gateway-orchestrator:latest|$PROJECT_ROOT/web/gateway-orchestrator"
    "trinity-gateway-proxy:latest|$PROJECT_ROOT/web/gateway-proxy"
    "trinity-terminal-proxy:latest|$PROJECT_ROOT/web/terminal-proxy"
    "trinity-frontend:latest|$PROJECT_ROOT/web/frontend"
    "trinity-site:latest|$PROJECT_ROOT/site"
  )

  for entry in "${images[@]}"; do
    local img="${entry%%|*}"
    local ctx="${entry##*|}"
    local dockerfile="$ctx/Dockerfile"

    if [ ! -f "$dockerfile" ]; then
      warn "Skipping $img -- no Dockerfile at $dockerfile"
      continue
    fi

    info "Building $img from $ctx..."
    docker build -t "$img" "$ctx" || {
      warn "Failed to build $img -- skipping (you can build it later)"
      continue
    }
    ok "Built $img"
  done

  if [ -f "$PROJECT_ROOT/web/Dockerfile.openclaw" ]; then
    info "Building openclaw:local..."
    docker build -t "openclaw:local" -f "$PROJECT_ROOT/web/Dockerfile.openclaw" "$PROJECT_ROOT/web" || {
      warn "Failed to build openclaw:local -- skipping"
    }
    ok "Built openclaw:local"
  fi

  eval "$(minikube docker-env --unset)"
  ok "All available images built inside minikube"
}

# ─── Step 6: Create namespace ─────────────────────────────────────────────
create_namespace() {
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    ok "Namespace $NAMESPACE already exists"
  else
    info "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
    ok "Namespace $NAMESPACE created"
  fi
}

# ─── Step 7: Helm install/upgrade ─────────────────────────────────────────
helm_deploy() {
  if [ ! -f "$VALUES_LOCAL" ]; then
    fail "Missing $VALUES_LOCAL -- run this script from the project root"
  fi

  info "Running helm dependency update..."
  helm dependency update "$CHART_DIR" 2>/dev/null || true

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    info "Upgrading existing release $RELEASE_NAME..."
    helm upgrade "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_LOCAL" \
      --wait \
      --timeout 10m
  else
    info "Installing release $RELEASE_NAME..."
    helm install "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_LOCAL" \
      --wait \
      --timeout 10m
  fi
  ok "Helm release $RELEASE_NAME deployed in namespace $NAMESPACE"
}

# ─── Step 8: Setup /etc/hosts ─────────────────────────────────────────────
setup_hosts() {
  local minikube_ip
  minikube_ip="$(minikube ip 2>/dev/null || echo "")"

  if [ -z "$minikube_ip" ]; then
    warn "Could not determine minikube IP -- you may need to add trinity.local to /etc/hosts manually"
    return
  fi

  if grep -q "trinity.local" /etc/hosts 2>/dev/null; then
    ok "trinity.local already in /etc/hosts"
  else
    info "Adding $minikube_ip trinity.local to /etc/hosts (requires sudo)..."
    echo "$minikube_ip trinity.local" | sudo tee -a /etc/hosts >/dev/null
    ok "Added trinity.local -> $minikube_ip to /etc/hosts"
  fi
}

# ─── Step 9: Print status ────────────────────────────────────────────────
print_status() {
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Trinity Platform deployed on minikube!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${CYAN}Namespace:${NC}  $NAMESPACE"
  echo -e "  ${CYAN}Release:${NC}    $RELEASE_NAME"
  echo -e "  ${CYAN}URL:${NC}        http://trinity.local"
  echo -e "  ${CYAN}Admin:${NC}      admin@trinity.local / admin123"
  echo -e "  ${CYAN}Keycloak:${NC}   http://trinity.local/keycloak (admin / local-kc-admin-123)"
  echo -e "  ${CYAN}Grafana:${NC}    Disabled by default in local mode"
  echo ""
  echo -e "  ${YELLOW}Useful commands:${NC}"
  echo -e "    kubectl get pods -n $NAMESPACE          # Check pod status"
  echo -e "    kubectl logs -f <pod> -n $NAMESPACE     # Stream logs"
  echo -e "    minikube dashboard                      # K8s dashboard"
  echo -e "    minikube tunnel                         # Expose LoadBalancer services"
  echo -e "    helm upgrade trinity $CHART_DIR -n $NAMESPACE -f $VALUES_LOCAL"
  echo ""
  echo -e "  ${YELLOW}If ingress isn't reachable, run in a separate terminal:${NC}"
  echo -e "    minikube tunnel"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────
main() {
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  Trinity Platform - Local Minikube Setup     ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  case "${1:-all}" in
    install-tools)
      install_brew
      install_tools
      ;;
    start)
      ensure_docker
      start_minikube
      ;;
    build)
      ensure_docker
      build_images
      ;;
    deploy)
      create_namespace
      helm_deploy
      setup_hosts
      print_status
      ;;
    status)
      kubectl get pods -n "$NAMESPACE"
      ;;
    teardown)
      info "Uninstalling helm release..."
      helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
      info "Deleting namespace..."
      kubectl delete namespace "$NAMESPACE" 2>/dev/null || true
      ok "Teardown complete"
      ;;
    all)
      install_brew
      install_tools
      ensure_docker
      start_minikube
      build_images
      create_namespace
      helm_deploy
      setup_hosts
      print_status
      ;;
    *)
      echo "Usage: $0 {all|install-tools|start|build|deploy|status|teardown}"
      exit 1
      ;;
  esac
}

main "$@"
