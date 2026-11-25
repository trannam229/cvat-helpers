#!/usr/bin/env bash
# cvat-helpers installer for macOS and Linux (WSL included).
#   install.sh             install or update the helpers UI (installs CVAT first if none is found)
#   install.sh uninstall   switch CVAT back to the stock UI
# Environment overrides: CVAT_DIR (where a fresh CVAT goes), CVAT_HELPERS_IMAGE (UI image to use).
set -euo pipefail

CVAT_VERSION="v2.84.0"
HELPERS_IMAGE="${CVAT_HELPERS_IMAGE:-ghcr.io/trannam229/cvat-helpers:v2.84.0-helpers.1}"
STOCK_UI_IMAGE="cvat/ui:${CVAT_VERSION}"
SERVER_IMAGE="cvat/server:${CVAT_VERSION}"
OVERRIDE_NAME="docker-compose.helpers.yml"
CVAT_URL="http://localhost:8080"
# Files a CVAT Compose deployment reads from disk (docker-compose.yml bind mounts included).
CVAT_FILES=(
    docker-compose.yml
    components/serverless/docker-compose.serverless.yml
    components/analytics/grafana_conf.yml
    components/analytics/vector/vector.toml
    components/analytics/grafana/dashboards/all_events.json
    components/analytics/grafana/dashboards/management.json
    components/analytics/grafana/dashboards/monitoring.json
    components/analytics/grafana/dashboards/users_exceptions.json
)

ACTION="${1:-install}"
PROJECT="cvat"
CVAT_DIR="${CVAT_DIR:-$HOME/cvat}"
COMPOSE_FILES=()
FRESH=0

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\n[LỖI] %s\n' "$*" >&2; exit 1; }
# Reads answers from the terminal even when the script itself comes from a pipe (curl | bash).
ask() { local answer; read -r -p "$1 " answer </dev/tty; [[ "$answer" =~ ^[yYcC] ]]; }
ask_default_yes() { local answer; read -r -p "$1 " answer </dev/tty; [[ ! "$answer" =~ ^[nNkK] ]]; }

ensure_docker() {
    command -v docker >/dev/null 2>&1 ||
        die "Chưa cài Docker. Cài Docker Desktop (https://www.docker.com/products/docker-desktop/) rồi chạy lại."
    if ! docker info >/dev/null 2>&1; then
        say "Docker chưa chạy, đang mở Docker Desktop..."
        if [[ "$(uname)" == Darwin ]]; then open -a Docker || true; fi
        for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 3; done
        docker info >/dev/null 2>&1 || die "Docker vẫn chưa chạy. Mở Docker Desktop, đợi biểu tượng báo Running rồi chạy lại."
    fi
    docker compose version >/dev/null 2>&1 || die "Cần Docker Compose v2 (lệnh 'docker compose')."
}

is_arm_host() { [[ "$(uname -m)" =~ ^(arm64|aarch64)$ ]]; }

# CVAT publishes some images for amd64 only; Docker Desktop runs them under emulation on ARM.
ensure_image() {
    local image="$1" platform="${2:-}"
    docker image inspect "$image" >/dev/null 2>&1 && return 0
    say "Tải image $image"
    if [[ -n "$platform" ]]; then
        docker pull --platform "$platform" "$image"
    else
        docker pull "$image"
    fi
}

label() { docker inspect cvat_server --format "{{index .Config.Labels \"$1\"}}"; }

# Fills PROJECT, CVAT_DIR and COMPOSE_FILES from the running cvat_server container.
find_running_cvat() {
    docker inspect cvat_server >/dev/null 2>&1 || return 1
    PROJECT="$(label com.docker.compose.project)"
    CVAT_DIR="$(label com.docker.compose.project.working_dir)"
    local files file
    IFS=',' read -r -a files <<<"$(label com.docker.compose.project.config_files)"
    COMPOSE_FILES=()
    for file in "${files[@]}"; do
        [[ "$(basename "$file")" == "$OVERRIDE_NAME" ]] && continue
        [[ -f "$file" ]] || die "CVAT đang chạy dùng file $file nhưng không thấy file này trên máy (CVAT được chạy từ môi trường khác, ví dụ Windows thay vì WSL?). Chạy installer ở đúng môi trường đã khởi động CVAT."
        COMPOSE_FILES+=("$file")
    done
    [[ ${#COMPOSE_FILES[@]} -gt 0 ]] || die "Không đọc được danh sách file Compose của CVAT đang chạy."
}

download_cvat() {
    say "Chưa thấy CVAT trên máy. Cài CVAT ${CVAT_VERSION} vào $CVAT_DIR"
    local file
    for file in "${CVAT_FILES[@]}"; do
        mkdir -p "$CVAT_DIR/$(dirname "$file")"
        curl -fsSL "https://raw.githubusercontent.com/cvat-ai/cvat/${CVAT_VERSION}/$file" -o "$CVAT_DIR/$file" ||
            die "Không tải được $file từ GitHub. Kiểm tra mạng rồi chạy lại."
    done
}

compose() {
    local args=(-p "$PROJECT") file
    for file in "${COMPOSE_FILES[@]}"; do args+=(-f "$file"); done
    docker compose "${args[@]}" "$@"
}

wait_for_cvat() {
    say "Đợi CVAT khởi động (lần đầu có thể mất vài phút)..."
    for _ in $(seq 1 120); do
        curl -fs "$CVAT_URL/api/server/about" >/dev/null 2>&1 && return 0
        sleep 5
    done
    die "CVAT chưa trả lời ở $CVAT_URL sau 10 phút. Xem log: docker logs cvat_server"
}

open_browser() {
    if [[ "$(uname)" == Darwin ]]; then open "$CVAT_URL"; elif command -v xdg-open >/dev/null; then xdg-open "$CVAT_URL" >/dev/null 2>&1 || true; fi
}

install_helpers() {
    if find_running_cvat; then
        local running
        running="$(docker inspect cvat_server --format '{{.Config.Image}}')"
        say "Tìm thấy CVAT đang chạy: $running ($CVAT_DIR)"
        if [[ "$running" != *":${CVAT_VERSION}" ]]; then
            printf 'Helpers được build cho CVAT %s, máy này đang chạy %s. Giao diện có thể lỗi với backend khác phiên bản.\n' "$CVAT_VERSION" "$running"
            ask "Vẫn cài? (y/N)" || die "Đã huỷ. Nâng/hạ CVAT về ${CVAT_VERSION} rồi chạy lại."
        fi
    elif [[ -f "$CVAT_DIR/docker-compose.yml" ]]; then
        say "Dùng CVAT có sẵn ở $CVAT_DIR (đang tắt)"
        COMPOSE_FILES=("$CVAT_DIR/docker-compose.yml")
        FRESH=1
    else
        download_cvat
        COMPOSE_FILES=("$CVAT_DIR/docker-compose.yml")
        FRESH=1
    fi

    ensure_image "$HELPERS_IMAGE"
    printf '# Written by the cvat-helpers installer: CVAT UI with the 3D helpers.\nservices:\n  cvat_ui:\n    image: %s\n' \
        "$HELPERS_IMAGE" >"$CVAT_DIR/$OVERRIDE_NAME"
    COMPOSE_FILES+=("$CVAT_DIR/$OVERRIDE_NAME")

    if [[ $FRESH -eq 1 ]]; then
        is_arm_host && ensure_image "$SERVER_IMAGE" linux/amd64
        say "Khởi động CVAT"
        compose up -d
    else
        say "Thay giao diện CVAT bằng bản helpers"
        compose up -d --no-deps cvat_ui
    fi

    wait_for_cvat
    [[ "$(docker inspect cvat_ui --format '{{.Config.Image}}')" == "$HELPERS_IMAGE" ]] ||
        die "cvat_ui không chạy image $HELPERS_IMAGE."

    if [[ $FRESH -eq 1 ]] && ask_default_yes "Tạo tài khoản admin cho CVAT bây giờ? (Y/n)"; then
        docker exec -it cvat_server bash -ic 'python3 ~/manage.py createsuperuser' </dev/tty
    fi

    say "Xong. CVAT có helpers đang chạy ở $CVAT_URL"
    printf 'Lưu ý: nếu sau này tự chạy "docker compose up", thêm "-f %s" để giữ giao diện helpers.\n' "$CVAT_DIR/$OVERRIDE_NAME"
    open_browser
}

uninstall_helpers() {
    find_running_cvat || die "Không thấy CVAT đang chạy (container cvat_server)."
    is_arm_host && ensure_image "$STOCK_UI_IMAGE" linux/amd64
    say "Trả CVAT về giao diện gốc"
    compose up -d --no-deps cvat_ui
    rm -f "$CVAT_DIR/$OVERRIDE_NAME"
    say "Đã gỡ helpers. cvat_ui chạy $(docker inspect cvat_ui --format '{{.Config.Image}}')"
}

ensure_docker
case "$ACTION" in
    install) install_helpers ;;
    uninstall) uninstall_helpers ;;
    *) die "Không hiểu lệnh '$ACTION'. Dùng: install.sh [install|uninstall]" ;;
esac
