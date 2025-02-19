#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

task() {
    echo -e "${MAGENTA}[TASK]${NC} $1"
}

run_with_spinner() {
    local msg="$1"
    shift
    local cmd=("$@")
    local pid
    local spin_chars='🕘🕛🕒🕡'
    local delay=0.1
    local i=0

    "${cmd[@]}" > /dev/null 2>&1 &
    pid=$!

    printf "${MAGENTA}[TASK]${NC} %s...  " "$msg"

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${MAGENTA}[TASK]${NC} %s... ${CYAN}%s${NC}" "$msg" "${spin_chars:$i:1}"
        sleep "$delay"
    done

    wait "$pid"
    local exit_status=$?

    printf "\r\033[K"
    return $exit_status
}

RUSTUP_HOME="${HOME}/.rustup"
CARGO_HOME="${HOME}/.cargo"

load_rust_env() {
    info "Loading Rust environment..."
    export RUSTUP_HOME="${RUSTUP_HOME}"
    export CARGO_HOME="${CARGO_HOME}"
    export PATH="${CARGO_HOME}/bin:${PATH}"
    
    if [ -f "${CARGO_HOME}/env" ]; then
        source "${CARGO_HOME}/env" > /dev/null 2>&1
        success "Rust environment loaded"
    else
        warn "Rust environment file not found at ${CARGO_HOME}/env"
    fi
}

install_dependencies() {
    info "Checking system dependencies..."
    
    if command -v apt &>/dev/null; then
        run_with_spinner "Updating package lists" sudo apt update &&
        run_with_spinner "Installing build tools" sudo apt install -y build-essential libssl-dev curl
        
    elif command -v yum &>/dev/null; then
        run_with_spinner "Installing development tools" sudo yum groupinstall -y 'Development Tools' &&
        run_with_spinner "Installing system libraries" sudo yum install -y openssl-devel curl
        
    elif command -v dnf &>/dev/null; then
        run_with_spinner "Installing development tools" sudo dnf groupinstall -y 'Development Tools' &&
        run_with_spinner "Installing system libraries" sudo dnf install -y openssl-devel curl
        
    elif command -v pacman &>/dev/null; then
        run_with_spinner "Updating system packages" sudo pacman -Syu --noconfirm &&
        run_with_spinner "Installing base-devel" sudo pacman -S --noconfirm base-devel openssl curl
        
    else
        error "Unsupported package manager. Install dependencies manually."
        exit 1
    fi
}

install_rust() {
    if command -v rustup &>/dev/null; then
        info "Found existing Rust installation"
        if run_with_spinner "Updating Rust toolchain" rustup update; then
            success "Rust updated to latest version"
        else
            error "Failed to update Rust"
            exit 1
        fi
    else
        info "Starting Rust installation (this may take a few minutes)..."
        if run_with_spinner "Installing Rust" bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"; then
            success "Rust installed successfully"
        else
            error "Rust installation failed!"
            exit 1
        fi
    fi
}

force_update_path() {
    info "Force updating PATH"
    export PATH="${CARGO_HOME}/bin:${PATH}"
    if [[ ":$PATH:" != *":${CARGO_HOME}/bin:"* ]]; then
        warn "Failed to update PATH. Manual intervention required."
        exit 1
    fi
    success "PATH updated successfully"
}

update_shell_profile() {
    local shell_profile
    case "$SHELL" in
        */bash) shell_profile="${HOME}/.bashrc" ;;
        */zsh) shell_profile="${HOME}/.zshrc" ;;
        *) shell_profile="${HOME}/.profile" ;;
    esac

    local env_line="source \"${CARGO_HOME}/env\""

    if ! grep -qF "$env_line" "$shell_profile" 2>/dev/null; then
        if run_with_spinner "Updating shell profile" bash -c "echo -e '\n# Rust environment\n${env_line}' >> '$shell_profile'"; then
            success "Shell profile updated"
        else
            error "Failed to update shell profile"
            exit 1
        fi
    fi
}

verify_installation() {
    info "Verifying installation..."
    if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
        rust_version=$(rustc --version 2>/dev/null)
        cargo_version=$(cargo --version 2>/dev/null)
        success "Rust components verified"
        echo -e "${CYAN}${rust_version}${NC}"
        echo -e "${CYAN}${cargo_version}${NC}"
    else
        error "Rust components not found!"
        exit 1
    fi
}

main() {
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        error "This script must be sourced, not executed. Please run:"
        echo -e "\n  source ${0}\n"
        exit 1
    fi

    info "🚀 Starting Rust setup process..."
    install_dependencies
    install_rust
    load_rust_env
    force_update_path
    update_shell_profile
    verify_installation

    success "✨ Rust setup completed successfully!"
    echo -e "👉 Current shell has been configured. New shells will automatically have Rust available."
}

main
