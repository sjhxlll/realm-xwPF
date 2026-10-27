#!/bin/bash

# xwPF - Realm 端口转发管理工具
# Bootstrap 引导器 + 入口

# 安装路径
INSTALL_DIR="/usr/local/bin"
LIB_DIR="$INSTALL_DIR/lib"
SHORTCUT_PATH="/usr/local/bin/pf"

# 仓库地址：必须与实际维护的 fork 一致。
# 指向他人仓库会导致 _bootstrap 用上游旧文件覆盖本地修改（旧版无加速源回退，realm 下载直连超时）。
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/sjhxlll/realm-xwPF/main}"

# GitHub 加速源：国内直连 github.com / raw.githubusercontent.com / api.github.com 常超时或被重置，
# 统一改用加速源前缀访问，直连只作为最后的兜底。
# 可覆盖：GH_PROXY="" 只用直连；GH_PROXY="https://your.proxy/" 换主加速源。
GH_PROXY="${GH_PROXY:-https://v6.gh-proxy.org/}"

# 候选加速源（逗号分隔，均已在 2026-10 实测可转发 raw / api / releases 下载）
GH_PROXY_MIRRORS="${GH_PROXY_MIRRORS:-https://v6.gh-proxy.org/,https://gh-proxy.com/,https://ghfast.top/,https://ghproxy.net/}"

# =1 时先试直连再走加速源（海外机器可用）；默认加速源在前
GH_PROXY_DIRECT_FIRST="${GH_PROXY_DIRECT_FIRST:-0}"

# 模块列表（加载顺序）
LIB_FILES=("core.sh" "rules.sh" "server.sh" "realm.sh" "ui.sh")

# 颜色
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

# 生成候选 URL：加速源在前、直连在后（国内网络直连基本只会白等超时）
_url_candidates() {
    local url="$1" prefix
    [ "$GH_PROXY_DIRECT_FIRST" = "1" ] && printf '%s\n' "$url"

    if [ -n "$GH_PROXY" ]; then
        printf '%s\n' "${GH_PROXY}${url}"
        IFS=',' read -ra _mirrors <<< "$GH_PROXY_MIRRORS"
        for prefix in "${_mirrors[@]}"; do
            prefix="${prefix//[[:space:]]/}"
            [ -z "$prefix" ] && continue
            [ "$prefix" = "$GH_PROXY" ] && continue
            printf '%s\n' "${prefix}${url}"
        done
    fi

    [ "$GH_PROXY_DIRECT_FIRST" = "1" ] || printf '%s\n' "$url"
}

# 下载函数：按候选地址逐个尝试，curl 失败再用 wget，成功即返回
# 注意：代理偶尔会返回 200 + 空/错误页，故除 -f 外还要校验文件非空
_download() {
    local url="$1" target="$2" cand
    while IFS= read -r cand; do
        if curl -fsSL --connect-timeout 10 --max-time 60 "$cand" -o "$target" 2>/dev/null && [ -s "$target" ]; then
            return 0
        fi
        if wget -q -O "$target" --timeout=15 --tries=1 "$cand" 2>/dev/null && [ -s "$target" ]; then
            return 0
        fi
        rm -f "$target"
    done < <(_url_candidates "$url")
    return 1
}

# 安装/更新脚本文件到系统（幂等）
_bootstrap() {
    echo -e "${_YELLOW}正在安装/更新脚本文件...${_NC}"

    mkdir -p "$LIB_DIR"

    # 下载入口脚本
    if _download "$REPO_RAW_URL/xwPF.sh" "$INSTALL_DIR/xwPF.sh"; then
        chmod +x "$INSTALL_DIR/xwPF.sh"
        echo -e "  ${_GREEN}✓${_NC} xwPF.sh"
    else
        echo -e "  ${_RED}✗${_NC} xwPF.sh 下载失败"
        return 1
    fi

    # 下载所有模块
    local failed=0
    for f in "${LIB_FILES[@]}"; do
        if _download "$REPO_RAW_URL/lib/$f" "$LIB_DIR/$f"; then
            echo -e "  ${_GREEN}✓${_NC} lib/$f"
        else
            echo -e "  ${_RED}✗${_NC} lib/$f 下载失败"
            failed=1
        fi
    done

    [ "$failed" -eq 1 ] && return 1

    # 创建快捷命令
    ln -sf "$INSTALL_DIR/xwPF.sh" "$SHORTCUT_PATH"
    echo -e "${_GREEN}✓ 快捷命令已创建: pf${_NC}"

    echo -e "${_GREEN}=== 脚本安装完成${_NC}"
    echo ""
}

# 加载模块
_load_libs() {
    if [ ! -d "$LIB_DIR" ] || [ ! -f "$LIB_DIR/core.sh" ]; then
        echo -e "${_RED}错误: 未找到模块目录，请先安装${_NC}"
        echo -e "${_BLUE}wget -qO- ${REPO_RAW_URL}/xwPF.sh | sudo bash -s install${_NC}"
        return 1
    fi

    for f in "${LIB_FILES[@]}"; do
        if [ -f "$LIB_DIR/$f" ]; then
            source "$LIB_DIR/$f"
        else
            echo -e "${_RED}错误: 缺少模块 $f${_NC}"
            return 1
        fi
    done
}

# 主入口
case "${1:-}" in
    install)
        [ "$(id -u)" -ne 0 ] && { echo -e "${_RED}错误: 需要 root 权限${_NC}"; exit 1; }
        _bootstrap || exit 1
        _load_libs || exit 1
        _SKIP_SCRIPT_UPDATE=1 smart_install
        ;;
    *)
        _load_libs || exit 1
        main "$@"
        ;;
esac
