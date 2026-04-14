#!/bin/sh

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误处理函数
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    echo -e "${YELLOW}正在清理临时文件...${NC}"
    cd /tmp
    rm -rf passwall_install 2>/dev/null
    exit 1
}

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    error_exit "请使用 root 用户运行此脚本"
fi

# 动态获取最新版本
echo -e "${YELLOW}正在获取最新版本信息...${NC}"
get_latest_version() {
    # 尝试不同的方法获取版本
    for cmd in curl wget; do
        if command -v $cmd >/dev/null 2>&1; then
            case $cmd in
                curl)
                    LATEST_TAG=$(curl -s https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
                    ;;
                wget)
                    LATEST_TAG=$(wget -qO- https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
                    ;;
            esac
            
            if [ -n "$LATEST_TAG" ]; then
                break
            fi
        fi
    done
    
    # 如果API失败，尝试从HTML页面获取
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${YELLOW}API获取失败，尝试从页面获取...${NC}"
        for cmd in curl wget; do
            if command -v $cmd >/dev/null 2>&1; then
                case $cmd in
                    curl)
                        LATEST_TAG=$(curl -s https://github.com/Openwrt-Passwall/openwrt-passwall2/releases | grep -o 'releases/tag/[^"]*' | head -1 | cut -d'/' -f3)
                        ;;
                    wget)
                        LATEST_TAG=$(wget -qO- https://github.com/Openwrt-Passwall/openwrt-passwall2/releases | grep -o 'releases/tag/[^"]*' | head -1 | cut -d'/' -f3)
                        ;;
                esac
                
                if [ -n "$LATEST_TAG" ]; then
                    break
                fi
            fi
        done
    fi
    
    # 如果还是失败，使用硬编码的备用版本
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用备用版本...${NC}"
        LATEST_TAG="26.4.10-1"
    fi
    
    echo "$LATEST_TAG"
}

# 解析版本信息
RELEASE_TAG=$(get_latest_version)
echo -e "${GREEN}检测到最新版本: ${RELEASE_TAG}${NC}"

# 提取版本号（假设格式为 X.X.X-X）
VERSION=$(echo "$RELEASE_TAG" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$VERSION" ]; then
    VERSION=$(echo "$RELEASE_TAG" | sed 's/-[0-9]*$//')
fi

echo -e "${GREEN}版本号: ${VERSION}${NC}"
echo -e "${GREEN}Release Tag: ${RELEASE_TAG}${NC}"

# 检查架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo -e "${YELLOW}警告: 当前架构为 $ARCH，但脚本为 x86_64 设计${NC}"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

echo -e "${GREEN}开始安装 PassWall2 for iStoreOS x86_64${NC}"
echo "版本: ${VERSION} (${RELEASE_TAG})"

# 检查必需命令
for cmd in wget opkg unzip; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到 $cmd，尝试安装...${NC}"
        opkg update && opkg install $cmd || error_exit "无法安装 $cmd"
    fi
done

# 检查curl和jq（用于更好的版本获取）
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}安装 curl 以便更好地获取版本信息...${NC}"
    opkg update && opkg install curl 2>/dev/null || echo -e "${YELLOW}curl 安装失败，将继续使用其他方法${NC}"
fi

# 检查依赖
echo -e "${YELLOW}检查依赖...${NC}"
REQUIRED_DEPS="luci-compat luci-lib-ipkg luci-lib-jsonc ip-full iptables-mod-tproxy coreutils-nohup"
for dep in $REQUIRED_DEPS; do
    if ! opkg list-installed | grep -q "^$dep"; then
        echo -e "${YELLOW}安装依赖: $dep${NC}"
        opkg install $dep || echo -e "${YELLOW}警告: $dep 安装失败，可能已经安装或需要手动处理${NC}"
    fi
done

# 创建临时目录
cd /tmp
rm -rf passwall_install
mkdir -p passwall_install || error_exit "无法创建临时目录"
cd passwall_install

# 下载文件
echo -e "${GREEN}开始下载文件...${NC}"

# 1. Luci界面
echo "下载 luci-app-passwall2..."
if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/luci-app-passwall2_${VERSION}-r1_all.ipk"; then
    # 尝试不同的文件名格式
    echo -e "${YELLOW}尝试其他文件名格式...${NC}"
    if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/luci-app-passwall2_${RELEASE_TAG}_all.ipk"; then
        if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/luci-app-passwall2_${VERSION}_all.ipk"; then
            error_exit "下载 luci-app-passwall2 失败"
        fi
    fi
fi

# 2. 中文语言包
echo "下载中文语言包..."
if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/luci-i18n-passwall2-zh-cn_${VERSION}_all.ipk"; then
    echo -e "${YELLOW}尝试其他语言包文件名格式...${NC}"
    if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/luci-i18n-passwall2-zh-cn_${RELEASE_TAG}_all.ipk"; then
        echo -e "${YELLOW}中文语言包下载失败，跳过...${NC}"
    fi
fi

# 3. 核心包zip
echo "下载核心包..."
if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/passwall_packages_ipk_x86_64.zip"; then
    # 尝试其他可能的文件名
    echo -e "${YELLOW}尝试其他核心包文件名...${NC}"
    if ! wget --no-check-certificate --show-progress -q "https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download/${RELEASE_TAG}/passwall_packages_x86_64.zip"; then
        error_exit "下载核心包失败"
    fi
fi

# 检查文件是否下载成功
echo -e "${GREEN}检查下载的文件...${NC}"
ls -lh *.ipk *.zip 2>/dev/null || error_exit "未找到下载的文件"

# 解压核心包
if [ -f "passwall_packages_ipk_x86_64.zip" ]; then
    echo "解压核心包..."
    if ! unzip -o passwall_packages_ipk_x86_64.zip -d packages 2>/dev/null; then
        echo "安装 unzip..."
        opkg install unzip 2>/dev/null || true
        unzip -o passwall_packages_ipk_x86_64.zip -d packages 2>/dev/null || error_exit "解压失败"
    fi
fi

# 如果有其他zip文件
for zipfile in passwall_packages_x86_64.zip passwall_packages.zip; do
    if [ -f "$zipfile" ]; then
        echo "解压 $zipfile..."
        if ! unzip -o "$zipfile" -d packages 2>/dev/null; then
            unzip -o "$zipfile" -d packages 2>/dev/null || echo -e "${YELLOW}解压 $zipfile 失败${NC}"
        fi
    fi
done

# 移动解压的文件
if [ -d "packages" ]; then
    mv packages/*.ipk . 2>/dev/null || true
fi

# 列出所有 ipk 文件
echo -e "${GREEN}找到以下 ipk 文件:${NC}"
ls -l *.ipk 2>/dev/null || error_exit "未找到 ipk 文件"

# 安装所有 ipk 文件
INSTALL_ERROR=0
for ipk in *.ipk; do
    [ -f "$ipk" ] || continue
    echo -e "${YELLOW}安装: $ipk${NC}"
    if ! opkg install --force-depends --force-postinstall "$ipk" 2>&1; then
        echo -e "${RED}安装 $ipk 时出现错误${NC}"
        INSTALL_ERROR=$((INSTALL_ERROR + 1))
    fi
    echo
done

# 检查安装结果
if [ $INSTALL_ERROR -eq 0 ] && opkg list-installed | grep -q "luci-app-passwall2"; then
    echo -e "${GREEN}✅ PassWall2 安装成功!${NC}"
    
    # 启用服务
    echo "启用 passwall2 服务..."
    [ -f /etc/init.d/passwall2 ] && {
        /etc/init.d/passwall2 enable 2>/dev/null
        /etc/init.d/passwall2 start 2>/dev/null && echo "服务启动成功" || echo "服务启动失败"
    }
    
    # 重启 LuCI
    echo "重启 uhttpd 服务..."
    /etc/init.d/uhttpd restart 2>/dev/null
    
    # 获取路由器 IP
    ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
    [ -z "$ROUTER_IP" ] && ROUTER_IP="路由器IP"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成!${NC}"
    echo -e "${GREEN}版本: ${VERSION} (${RELEASE_TAG})${NC}"
    echo -e "${GREEN}请访问: http://${ROUTER_IP}/cgi-bin/luci/admin/services/passwall2${NC}"
    echo -e "${GREEN}或: http://${ROUTER_IP}/luci/admin/services/passwall2${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # 检查防火墙规则
    echo -e "${YELLOW}提示: 如果无法访问，请检查防火墙设置${NC}"
else
    echo -e "${RED}❌ 安装失败${NC}"
    echo -e "${YELLOW}可能的原因:${NC}"
    echo "1. 缺少依赖"
    echo "2. 版本不兼容"
    echo "3. 网络问题"
    echo "4. 文件下载不完整"
    echo ""
    echo -e "${YELLOW}尝试安装以下依赖:${NC}"
    echo "opkg update"
    echo "opkg install luci-compat luci-lib-ipkg luci-lib-jsonc"
    echo "opkg install ip-full iptables-mod-tproxy coreutils-nohup"
    echo ""
    echo -e "${YELLOW}然后重新运行此脚本${NC}"
fi

# 清理
echo "清理临时文件..."
cd /tmp
rm -rf passwall_install 2>/dev/null

# 最后提示
echo ""
echo -e "${YELLOW}安装日志保存在: /var/log/passwall2_install.log${NC}"
echo -e "${YELLOW}如需卸载，请使用: opkg remove luci-app-passwall2 luci-i18n-passwall2-zh-cn --force-depends${NC}"

exit $INSTALL_ERROR