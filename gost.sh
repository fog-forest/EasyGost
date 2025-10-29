#!/bin/bash

# 颜色与状态常量定义
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"

# 基础配置参数
shell_version="1.1.2"
ct_new_ver="2.11.5" # 2.x 不再跟随官方更新
gost_conf_path="/etc/gost/config.json"
raw_conf_path="/etc/gost/rawconf"
github_proxy="https://github.misaka.nyc.mn/"

# 检查并更新gost版本
function checknew() {
    checknew=$(gost -V 2>&1 | awk '{print $2}')
    echo -e "${Info} 你的gost版本为: $checknew"
    read -p "是否更新到版本 $ct_new_ver? (y/n): " checknewnum

    if [ "$checknewnum" = "y" ]; then
        echo -e "${Info} 备份现有配置到/tmp目录..."
        cp -r /etc/gost /tmp/
        Install_ct
        rm -rf /etc/gost
        mv /tmp/gost /etc/

        # 根据系统类型重启服务
        if [ "$release" = "alpine" ]; then
            rc-service gost restart
        else
            systemctl restart gost
        fi
        echo -e "${Info} gost已更新至版本 $ct_new_ver"
    else
        echo -e "${Info} 已取消更新操作"
        exit 0
    fi
}

# 检测系统版本与架构
function check_sys() {
    # 检测发行版
    if [ -f /etc/alpine-release ]; then
        release="alpine"
    elif [ -f /etc/redhat-release ]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi

    # 检测架构
    bit=$(uname -m)
    if [ "$bit" != "x86_64" ]; then
        echo -e "${Info} 检测到非x86_64架构"
        read -p "请输入芯片架构（/386/armv5/armv6/armv7/armv8）：" bit
    else
        bit="amd64"
    fi
}

# 安装依赖组件
function Installation_dependency() {
    gzip_ver=$(gzip -V 2>/dev/null)
    if [ -z "$gzip_ver" ]; then
        echo -e "${Info} 安装必要依赖组件..."
        case $release in
        centos)
            yum update -y
            yum install -y gzip wget curl
            ;;
        alpine)
            apk update
            apk add -y gzip wget curl openrc
            openrc
            touch /run/openrc/softlevel
            ;;
        *) # debian/ubuntu
            apt-get update -y
            apt-get install -y gzip wget curl
            ;;
        esac
    fi
}

# 检查是否为root用户
function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作"
        echo -e "${Error} 请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 获取权限"
        exit 1
    fi
}

# 检查服务文件目录
function check_file() {
    if [ "$release" = "alpine" ]; then
        # Alpine使用OpenRC
        if [ ! -d "/etc/init.d/" ]; then
            mkdir -p /etc/init.d
            chmod -R 755 /etc/init.d
        fi
    else
        # 其他系统使用systemd
        if [ ! -d "/usr/lib/systemd/system/" ]; then
            mkdir -p /usr/lib/systemd/system
            chmod -R 755 /usr/lib/systemd/system
        fi
    fi
}

# 清理残留文件
function check_nor_file() {
    echo -e "${Info} 清理残留文件..."
    # 清理当前目录临时文件
    rm -rf "$(pwd)"/gost
    rm -rf "$(pwd)"/gost.service
    rm -rf "$(pwd)"/config.json
    rm -rf /etc/gost

    # 清理服务文件
    if [ "$release" = "alpine" ]; then
        rm -rf /etc/init.d/gost
    else
        rm -rf /usr/lib/systemd/system/gost.service
    fi

    # 清理二进制文件
    rm -rf /usr/bin/gost
}

# 安装gost主程序
function Install_ct() {
    check_root
    check_nor_file
    Installation_dependency
    check_file
    check_sys

    echo -e "${Info} 下载配置 - 国内机器建议使用镜像加速"
    read -e -p "是否使用大陆镜像加速下载? [y/n] (默认n):" addyn
    [ -z "$addyn" ] && addyn="n"

    # 下载地址选择（镜像/官方）
    if [ "$addyn" = "y" ] || [ "$addyn" = "Y" ]; then
        base_url="$github_proxy"
        echo -e "${Info} 使用镜像地址下载: $base_url"
    else
        base_url=""
        echo -e "${Info} 使用官方地址下载"
    fi

    # 下载并安装gost二进制文件
    echo -e "${Info} 开始下载gost v$ct_new_ver (架构: $bit)..."
    rm -rf "gost-linux-$bit-$ct_new_ver.gz"
    wget --no-check-certificate "${base_url}https://github.com/ginuerzh/gost/releases/download/v$ct_new_ver/gost-linux-$bit-$ct_new_ver.gz" || {
        echo -e "${Error} 下载失败，请检查网络连接"
        exit 1
    }
    gunzip "gost-linux-$bit-$ct_new_ver.gz"
    mv "gost-linux-$bit-$ct_new_ver" gost
    mv gost /usr/bin/
    chmod 755 /usr/bin/gost

    # 安装服务文件
    echo -e "${Info} 安装服务文件..."
    if [ "$release" = "alpine" ]; then
        # OpenRC服务文件
        wget --no-check-certificate "${base_url}https://raw.githubusercontent.com/fog-forest/EasyGost/master/gost.openrc"
        chmod 755 gost.openrc
        mv gost.openrc /etc/init.d/gost
    else
        # systemd服务文件
        wget --no-check-certificate "${base_url}https://raw.githubusercontent.com/fog-forest/EasyGost/master/gost.service"
        chmod 755 gost.service
        mv gost.service /usr/lib/systemd/system/
    fi

    # 安装配置文件
    echo -e "${Info} 配置文件初始化..."
    mkdir -p /etc/gost
    wget --no-check-certificate "${base_url}https://raw.githubusercontent.com/fog-forest/EasyGost/master/config.json"
    mv config.json /etc/gost/
    chmod -R 755 /etc/gost

    # 启动并设置开机自启
    echo -e "${Info} 启动服务并设置开机自启..."
    if [ "$release" = "alpine" ]; then
        rc-update add gost default
        rc-service gost restart
    else
        systemctl enable gost
        systemctl restart gost
    fi

    # 安装结果检查
    echo -e "\n${Info} 安装结果检查:"
    echo "------------------------------"
    if [ -f /usr/bin/gost ] && [ -f /etc/gost/config.json ]; then
        if [ "$release" = "alpine" ] && [ -f /etc/init.d/gost ]; then
            echo -e "${Green_font_prefix}gost安装成功${Font_color_suffix}"
        elif [ "$release" != "alpine" ] && [ -f /usr/lib/systemd/system/gost.service ]; then
            echo -e "${Green_font_prefix}gost安装成功${Font_color_suffix}"
        else
            echo -e "${Error} gost安装失败：服务文件未找到"
        fi
    else
        echo -e "${Error} gost安装失败：二进制文件或配置文件未找到"
    fi
}

# 卸载gost
function Uninstall_ct() {
    echo -e "${Info} 开始卸载gost..."
    rm -rf /usr/bin/gost

    # 清理服务文件
    if [ "$release" = "alpine" ]; then
        rm -rf /etc/init.d/gost
    else
        rm -rf /usr/lib/systemd/system/gost.service
    fi

    # 清理配置文件
    rm -rf /etc/gost
    rm -rf "$(pwd)"/gost.sh
    echo -e "${Info} gost已完全卸载"
}

# 启动gost服务
function Start_ct() {
    echo -e "${Info} 启动gost服务..."
    if [ "$release" = "alpine" ]; then
        rc-service gost start
    else
        systemctl start gost
    fi
    echo -e "${Info} gost服务已启动"
}

# 停止gost服务
function Stop_ct() {
    echo -e "${Info} 停止gost服务..."
    if [ "$release" = "alpine" ]; then
        rc-service gost stop
    else
        systemctl stop gost
    fi
    echo -e "${Info} gost服务已停止"
}

# 重启gost服务（并重载配置）
function Restart_ct() {
    echo -e "${Info} 重新加载配置并重启服务..."
    rm -rf "$gost_conf_path"
    confstart
    writeconf
    conflast

    if [ "$release" = "alpine" ]; then
        rc-service gost restart
    else
        systemctl restart gost
    fi
    echo -e "${Info} gost已重读配置并重启"
}

# 选择转发协议类型
function read_protocol() {
    echo -e "\n${Info} 请选择要设置的功能类型:"
    echo -e "-----------------------------------"
    echo -e "[1] TCP+UDP流量转发 (不加密)"
    echo -e "    说明: 适用于国内中转机，直接转发流量"
    echo -e "-----------------------------------"
    echo -e "[2] 加密隧道流量转发"
    echo -e "    说明: 用于转发加密等级较低的流量，适用于国内中转机"
    echo -e "          需在接收端配置协议[3]进行对接"
    echo -e "-----------------------------------"
    echo -e "[3] 解密并转发gost加密流量"
    echo -e "    说明: 解密由gost加密中转的流量，适用于国外接收端机器"
    echo -e "          可转发给本机代理服务或其他远程机器"
    echo -e "-----------------------------------"
    echo -e "[4] 一键安装SS/SOCKS5/HTTP代理"
    echo -e "    说明: 使用gost内置代理协议，轻量易管理"
    echo -e "-----------------------------------"
    echo -e "[5] 进阶：多节点负载均衡"
    echo -e "    说明: 支持多种加密方式的简单负载均衡"
    echo -e "-----------------------------------"
    echo -e "[6] 进阶：CDN自选节点转发"
    echo -e "    说明: 只需在中转机设置"
    echo -e "-----------------------------------"
    read -p "请输入选项 [1-6]: " numprotocol

    case $numprotocol in
    1) flag_a="nonencrypt" ;;
    2) encrypt ;;
    3) decrypt ;;
    4) proxy ;;
    5) enpeer ;;
    6) cdn ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 读取本地端口
function read_s_port() {
    case $flag_a in
    ss)
        echo -e "\n${Info} 配置Shadowsocks代理"
        read -p "请输入SS密码: " flag_b
        ;;
    socks)
        echo -e "\n${Info} 配置SOCKS5代理"
        read -p "请输入SOCKS5密码: " flag_b
        ;;
    http)
        echo -e "\n${Info} 配置HTTP代理"
        read -p "请输入HTTP密码: " flag_b
        ;;
    *)
        echo -e "\n${Info} 配置本地监听端口"
        read -p "请输入本机接收流量的端口: " flag_b
        ;;
    esac
}

# 读取目标IP/域名
function read_d_ip() {
    case $flag_a in
    ss)
        echo -e "\n${Info} 选择SS加密方式 (常用类型):"
        echo -e "-----------------------------------"
        echo -e "[1] aes-256-gcm"
        echo -e "[2] aes-256-cfb"
        echo -e "[3] chacha20-ietf-poly1305"
        echo -e "[4] chacha20"
        echo -e "[5] rc4-md5"
        echo -e "[6] AEAD_CHACHA20_POLY1305"
        echo -e "-----------------------------------"
        read -p "请选择加密方式 [1-6]: " ssencrypt

        case $ssencrypt in
        1) flag_c="aes-256-gcm" ;;
        2) flag_c="aes-256-cfb" ;;
        3) flag_c="chacha20-ietf-poly1305" ;;
        4) flag_c="chacha20" ;;
        5) flag_c="rc4-md5" ;;
        6) flag_c="AEAD_CHACHA20_POLY1305" ;;
        *)
            echo -e "${Error} 输入错误，请重试"
            exit
            ;;
        esac
        ;;
    socks)
        echo -e "\n${Info} 配置SOCKS5代理"
        read -p "请输入SOCKS5用户名: " flag_c
        ;;
    http)
        echo -e "\n${Info} 配置HTTP代理"
        read -p "请输入HTTP用户名: " flag_c
        ;;
    peer*)
        echo -e "\n${Info} 配置负载均衡节点列表"
        read -e -p "请输入落地列表文件名 (无需后缀): " flag_c
        touch "$flag_c.txt"
        echo -e "${Info} 已创建文件: $flag_c.txt"
        echo -e "${Info} 请添加负载均衡的节点信息"

        while true; do
            read -p "请输入落地节点IP或域名: " peer_ip
            read -p "请输入落地节点端口: " peer_port
            echo "$peer_ip:$peer_port" >>"$flag_c.txt"
            echo -e "${Info} 已添加节点: $peer_ip:$peer_port"

            read -e -p "是否继续添加节点? [Y/n] (默认y):" addyn
            [ -z "$addyn" ] && addyn="y"
            if [ "$addyn" = "n" ] || [ "$addyn" = "N" ]; then
                echo -e "${Info} 落地列表配置完成，文件位于: /root/$flag_c.txt"
                echo -e "${Info} 可随时编辑该文件修改节点，重启gost即可生效"
                break
            fi
        done
        ;;
    cdn*)
        echo -e "\n${Info} 配置CDN转发目标"
        read -p "请输入CDN节点IP: " flag_c
        echo -e "请选择目标端口:"
        echo -e "[1] 80 (HTTP默认端口)"
        echo -e "[2] 443 (HTTPS默认端口)"
        echo -e "[3] 自定义端口"
        read -p "请选择 [1-3]: " cdnport

        case $cdnport in
        1) flag_c="$flag_c:80" ;;
        2) flag_c="$flag_c:443" ;;
        3)
            read -p "请输入自定义端口: " customport
            flag_c="$flag_c:$customport"
            ;;
        *)
            echo -e "${Error} 输入错误，请重试"
            exit
            ;;
        esac
        echo -e "${Info} CDN目标地址: $flag_c"
        ;;
    *)
        echo -e "\n${Info} 配置目标地址"
        echo -e "目标IP可以是:"
        echo -e "  - 远程机器的公网IP"
        echo -e "  - 当前机器的公网IP"
        echo -e "  - 本机回环地址 (127.0.0.1)"
        if [ "$is_cert" = "y" ] || [ "$is_cert" = "Y" ]; then
            echo -e "${Red_font_prefix}注意: 落地机开启自定义TLS证书时，必须填写域名${Font_color_suffix}"
        fi
        read -p "请输入目标IP或域名: " flag_c
        ;;
    esac
}

# 读取目标端口
function read_d_port() {
    case $flag_a in
    ss)
        echo -e "\n${Info} 配置SS服务端口"
        read -p "请输入SS代理服务端口: " flag_d
        ;;
    socks)
        echo -e "\n${Info} 配置SOCKS5服务端口"
        read -p "请输入SOCKS5代理服务端口: " flag_d
        ;;
    http)
        echo -e "\n${Info} 配置HTTP服务端口"
        read -p "请输入HTTP代理服务端口: " flag_d
        ;;
    peer*)
        echo -e "\n${Info} 选择负载均衡策略"
        echo -e "-----------------------------------"
        echo -e "[1] round - 轮询"
        echo -e "[2] random - 随机"
        echo -e "[3] fifo - 自上而下"
        echo -e "-----------------------------------"
        read -p "请选择策略 [1-3]: " numstra

        case $numstra in
        1) flag_d="round" ;;
        2) flag_d="random" ;;
        3) flag_d="fifo" ;;
        *)
            echo -e "${Error} 输入错误，请重试"
            exit
            ;;
        esac
        ;;
    cdn*)
        echo -e "\n${Info} 配置CDN转发"
        read -p "请输入HOST头信息: " flag_d
        ;;
    *)
        echo -e "\n${Info} 配置目标端口"
        read -p "请输入目标端口: " flag_d
        if [ "$is_cert" = "y" ] || [ "$is_cert" = "Y" ]; then
            flag_d="$flag_d?secure=true"
        fi
        ;;
    esac
}

# 写入原始配置
function writerawconf() {
    echo "${flag_a}/${flag_b}#${flag_c}#${flag_d}" >>"$raw_conf_path"
}

# 生成原始配置
function rawconf() {
    read_protocol
    read_s_port
    read_d_ip
    read_d_port
    writerawconf
}

# 解析配置参数
function eachconf_retrieve() {
    d_server=${trans_conf#*#}
    d_port=${d_server#*#}
    d_ip=${d_server%#*}
    flag_s_port=${trans_conf%%#*}
    s_port=${flag_s_port#*/}
    is_encrypt=${flag_s_port%/*}
}

# 生成配置文件头部
function confstart() {
    echo "{
    \"Debug\": true,
    \"Retries\": 0,
    \"ServeNodes\": [" >>"$gost_conf_path"
}

# 生成多路由配置头部
function multiconfstart() {
    echo "        {
            \"Retries\": 0,
            \"ServeNodes\": [" >>"$gost_conf_path"
}

# 生成配置文件尾部
function conflast() {
    echo "    ]
}" >>"$gost_conf_path"
}

# 生成多路由配置尾部
function multiconflast() {
    if [ $i -eq $count_line ]; then
        echo "            ]
        }" >>"$gost_conf_path"
    else
        echo "            ]
        }," >>"$gost_conf_path"
    fi
}

# 加密隧道配置
function encrypt() {
    echo -e "\n${Info} 选择加密隧道类型"
    echo -e "-----------------------------------"
    echo -e "[1] TLS隧道"
    echo -e "[2] WS隧道"
    echo -e "[3] WSS隧道"
    echo -e "-----------------------------------"
    echo -e "注意: 同一转发链路中，中转与落地的传输类型必须一致"
    echo -e "本脚本默认同时转发TCP和UDP流量"
    read -p "请选择转发传输类型 [1-3]: " numencrypt

    case $numencrypt in
    1)
        flag_a="encrypttls"
        echo -e "${Info} TLS隧道配置"
        read -e -p "落地机是否使用自定义TLS证书? [y/n] (默认n):" is_cert
        [ -z "$is_cert" ] && is_cert="n"
        if [ "$is_cert" = "y" ] || [ "$is_cert" = "Y" ]; then
            echo -e "${Red_font_prefix}注意: 稍后请填写落地机的域名而非IP${Font_color_suffix}"
        fi
        ;;
    2)
        flag_a="encryptws"
        echo -e "${Info} WS隧道配置"
        ;;
    3)
        flag_a="encryptwss"
        echo -e "${Info} WSS隧道配置"
        read -e -p "落地机是否使用自定义TLS证书? [y/n] (默认n):" is_cert
        [ -z "$is_cert" ] && is_cert="n"
        if [ "$is_cert" = "y" ] || [ "$is_cert" = "Y" ]; then
            echo -e "${Red_font_prefix}注意: 稍后请填写落地机的域名而非IP${Font_color_suffix}"
        fi
        ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 均衡负载配置
function enpeer() {
    echo -e "\n${Info} 选择负载均衡传输类型"
    echo -e "-----------------------------------"
    echo -e "[1] 不加密转发"
    echo -e "[2] TLS隧道"
    echo -e "[3] WS隧道"
    echo -e "[4] WSS隧道"
    echo -e "-----------------------------------"
    echo -e "注意: 同一转发链路中，中转与落地的传输类型必须一致"
    echo -e "本脚本默认同一配置使用相同的传输类型"
    echo -e "官方文档: https://docs.ginuerzh.xyz/gost/load-balancing"
    read -p "请选择传输类型 [1-4]: " numpeer

    case $numpeer in
    1) flag_a="peerno" ;;
    2) flag_a="peertls" ;;
    3) flag_a="peerws" ;;
    4) flag_a="peerwss" ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# CDN转发配置
function cdn() {
    echo -e "\n${Info} 选择CDN传输类型"
    echo -e "-----------------------------------"
    echo -e "[1] 不加密转发"
    echo -e "[2] WS隧道"
    echo -e "[3] WSS隧道"
    echo -e "-----------------------------------"
    echo -e "注意: 同一转发链路中，中转与落地的传输类型必须一致"
    echo -e "此功能只需在中转机设置"
    read -p "请选择CDN转发传输类型 [1-3]: " numcdn

    case $numcdn in
    1) flag_a="cdnno" ;;
    2) flag_a="cdnws" ;;
    3) flag_a="cdnwss" ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 证书配置
function cert() {
    echo -e "\n${Info} 自定义TLS证书配置 (仅用于落地机)"
    echo -e "-----------------------------------"
    echo -e "[1] ACME一键申请证书"
    echo -e "[2] 手动上传证书"
    echo -e "-----------------------------------"
    echo -e "说明: 使用自定义证书可提高安全性，配置后对本机所有TLS/WSS解密生效"
    read -p "请选择证书配置方式 [1-2]: " numcert

    case $numcert in
    1)
        check_sys
        # 安装socat依赖
        echo -e "${Info} 安装证书申请所需依赖..."
        case $release in
        centos) yum install -y socat ;;
        alpine) apk add -y socat ;;
        *) apt-get install -y socat ;;
        esac

        read -p "请输入ZeroSSL的账户邮箱 (需在zerossl.com注册): " zeromail
        read -p "请输入解析到本机的域名: " domain

        # 安装acme.sh
        echo -e "${Info} 安装ACME证书申请工具..."
        curl https://get.acme.sh | sh
        "$HOME"/.acme.sh/acme.sh --set-default-ca --server zerossl
        "$HOME"/.acme.sh/acme.sh --register-account -m "$zeromail" --server zerossl
        echo -e "${Info} ACME证书申请程序安装成功"

        echo -e "\n${Info} 选择证书申请方式"
        echo -e "-----------------------------------"
        echo -e "[1] HTTP申请（需要80端口未占用）"
        echo -e "[2] Cloudflare DNS API 申请（需要API密钥）"
        echo -e "-----------------------------------"
        read -p "请选择证书申请方式 [1-2]: " certmethod

        if [ "$certmethod" = 1 ]; then
            echo -e "${Red_font_prefix}注意: 请确保本机80端口未被占用，否则会申请失败${Font_color_suffix}"
            if "$HOME"/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force; then
                echo -e "${Info} SSL证书生成成功（高安全性ECC证书）"
                [ ! -d "$HOME/gost_cert" ] && mkdir "$HOME/gost_cert"
                if "$HOME"/.acme.sh/acme.sh --installcert -d "$domain" \
                    --fullchainpath "$HOME/gost_cert/cert.pem" \
                    --keypath "$HOME/gost_cert/key.pem" --ecc --force; then
                    echo -e "${Info} SSL证书配置成功，证书会自动续签"
                    echo -e "${Info} 证书位置: $HOME/gost_cert"
                    echo -e "${Info} 提示: 删除gost_cert目录并重启gost，将自动启用内置证书"
                fi
            else
                echo -e "${Error} SSL证书生成失败"
                exit 1
            fi
        else
            read -p "请输入Cloudflare账户邮箱: " cfmail
            read -p "请输入Cloudflare Global API Key: " cfkey
            export CF_Key="$cfkey"
            export CF_Email="$cfmail"

            if "$HOME"/.acme.sh/acme.sh --issue --dns dns_cf -d "$domain" --standalone -k ec-256 --force; then
                echo -e "${Info} SSL证书生成成功（高安全性ECC证书）"
                [ ! -d "$HOME/gost_cert" ] && mkdir "$HOME/gost_cert"
                if "$HOME"/.acme.sh/acme.sh --installcert -d "$domain" \
                    --fullchainpath "$HOME/gost_cert/cert.pem" \
                    --keypath "$HOME/gost_cert/key.pem" --ecc --force; then
                    echo -e "${Info} SSL证书配置成功，证书会自动续签"
                    echo -e "${Info} 证书位置: $HOME/gost_cert"
                    echo -e "${Info} 提示: 删除gost_cert目录并重启gost，将自动启用内置证书"
                fi
            else
                echo -e "${Error} SSL证书生成失败"
                exit 1
            fi
        fi
        ;;
    2)
        [ ! -d "$HOME/gost_cert" ] && mkdir "$HOME/gost_cert"
        echo -e "${Info} 已在用户目录创建证书目录: $HOME/gost_cert"
        echo -e "${Info} 请将证书文件 cert.pem 与密钥文件 key.pem 上传到该目录"
        echo -e "${Info} 注意: 证书与密钥文件名必须与上述一致，目录名也请勿更改"
        echo -e "${Info} 上传成功后，重启gost会自动启用；删除该目录后重启将使用内置证书"
        ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 解密配置
function decrypt() {
    echo -e "\n${Info} 选择解密传输类型"
    echo -e "-----------------------------------"
    echo -e "[1] TLS解密"
    echo -e "[2] WS解密"
    echo -e "[3] WSS解密"
    echo -e "-----------------------------------"
    echo -e "注意: 必须与中转机的加密类型对应，默认同时处理TCP和UDP流量"
    read -p "请选择解密传输类型 [1-3]: " numdecrypt

    case $numdecrypt in
    1) flag_a="decrypttls" ;;
    2) flag_a="decryptws" ;;
    3) flag_a="decryptwss" ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 代理类型配置
function proxy() {
    echo -e "\n${Info} 选择代理类型"
    echo -e "-----------------------------------"
    echo -e "[1] Shadowsocks"
    echo -e "[2] SOCKS5 (建议加隧道用于Telegram)"
    echo -e "[3] HTTP"
    echo -e "-----------------------------------"
    read -p "请选择代理类型 [1-3]: " numproxy

    case $numproxy in
    1) flag_a="ss" ;;
    2) flag_a="socks" ;;
    3) flag_a="http" ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 生成配置内容
function method() {
    if [ $i -eq 1 ]; then
        case $is_encrypt in
        nonencrypt)
            echo "        \"tcp://:$s_port/$d_ip:$d_port\",
        \"udp://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        cdnno)
            echo "        \"tcp://:$s_port/$d_ip?host=$d_port\",
        \"udp://:$s_port/$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        peerno)
            echo "        \"tcp://:$s_port?ip=/root/$d_ip.txt&strategy=$d_port\",
        \"udp://:$s_port?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        encrypttls)
            echo "        \"tcp://:$s_port\",
        \"udp://:$s_port\"
    ],
    \"ChainNodes\": [
        \"relay+tls://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        encryptws)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+ws://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        encryptwss)
            echo "        \"tcp://:$s_port\",
		  \"udp://:$s_port\"
	],
	\"ChainNodes\": [
		\"relay+wss://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        peertls)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+tls://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        peerws)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+ws://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        peerwss)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+wss://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        cdnws)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+ws://$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        cdnwss)
            echo "        \"tcp://:$s_port\",
    	\"udp://:$s_port\"
	],
	\"ChainNodes\": [
    	\"relay+wss://$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        decrypttls)
            if [ -d "$HOME/gost_cert" ]; then
                echo "        \"relay+tls://:$s_port/$d_ip:$d_port?cert=/root/gost_cert/cert.pem&key=/root/gost_cert/key.pem\"" >>"$gost_conf_path"
            else
                echo "        \"relay+tls://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            fi
            ;;
        decryptws)
            echo "        \"relay+ws://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        decryptwss)
            if [ -d "$HOME/gost_cert" ]; then
                echo "        \"relay+wss://:$s_port/$d_ip:$d_port?cert=/root/gost_cert/cert.pem&key=/root/gost_cert/key.pem\"" >>"$gost_conf_path"
            else
                echo "        \"relay+wss://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            fi
            ;;
        ss)
            echo "        \"ss://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        socks)
            echo "        \"socks5://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        http)
            echo "        \"http://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        *)
            echo "config error"
            ;;
        esac
    elif [ $i -gt 1 ]; then
        case $is_encrypt in
        nonencrypt)
            echo "                \"tcp://:$s_port/$d_ip:$d_port\",
                \"udp://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        peerno)
            echo "                \"tcp://:$s_port?ip=/root/$d_ip.txt&strategy=$d_port\",
                \"udp://:$s_port?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        cdnno)
            echo "                \"tcp://:$s_port/$d_ip?host=$d_port\",
                \"udp://:$s_port/$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        encrypttls)
            echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+tls://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        encryptws)
            echo "                \"tcp://:$s_port\",
	            \"udp://:$s_port\"
	        ],
	        \"ChainNodes\": [
	            \"relay+ws://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        encryptwss)
            echo "                \"tcp://:$s_port\",
		        \"udp://:$s_port\"
		    ],
		    \"ChainNodes\": [
		        \"relay+wss://$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        peertls)
            echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+tls://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        peerws)
            echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+ws://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        peerwss)
            echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+wss://:?ip=/root/$d_ip.txt&strategy=$d_port\"" >>"$gost_conf_path"
            ;;
        cdnws)
            echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+ws://$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        cdnwss)
            echo "                 \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+wss://$d_ip?host=$d_port\"" >>"$gost_conf_path"
            ;;
        decrypttls)
            if [ -d "$HOME/gost_cert" ]; then
                echo "        		  \"relay+tls://:$s_port/$d_ip:$d_port?cert=/root/gost_cert/cert.pem&key=/root/gost_cert/key.pem\"" >>"$gost_conf_path"
            else
                echo "        		  \"relay+tls://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            fi
            ;;
        decryptws)
            echo "        		  \"relay+ws://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            ;;
        decryptwss)
            if [ -d "$HOME/gost_cert" ]; then
                echo "        		  \"relay+wss://:$s_port/$d_ip:$d_port?cert=/root/gost_cert/cert.pem&key=/root/gost_cert/key.pem\"" >>"$gost_conf_path"
            else
                echo "        		  \"relay+wss://:$s_port/$d_ip:$d_port\"" >>"$gost_conf_path"
            fi
            ;;
        ss)
            echo "        \"ss://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        socks)
            echo "        \"socks5://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        http)
            echo "        \"http://$d_ip:$s_port@:$d_port\"" >>"$gost_conf_path"
            ;;
        *)
            echo "config error"
            ;;
        esac
    else
        echo "config error"
        exit
    fi
}

# 生成完整配置文件
function writeconf() {
    count_line=$(awk 'END{print NR}' "$raw_conf_path")
    for ((i = 1; i <= $count_line; i++)); do
        if [ $i -eq 1 ]; then
            trans_conf=$(sed -n "${i}p" "$raw_conf_path")
            eachconf_retrieve
            method
        elif [ $i -gt 1 ]; then
            if [ $i -eq 2 ]; then
                echo "    ],
    \"Routes\": [" >>"$gost_conf_path"
                trans_conf=$(sed -n "${i}p" "$raw_conf_path")
                eachconf_retrieve
                multiconfstart
                method
                multiconflast
            else
                trans_conf=$(sed -n "${i}p" "$raw_conf_path")
                eachconf_retrieve
                multiconfstart
                method
                multiconflast
            fi
        fi
    done
}

# 显示所有配置
function show_all_conf() {
    echo -e "\n${Info} 当前GOST配置列表"
    echo -e "--------------------------------------------------------"
    echo -e "序号 | 方法               | 本地端口 | 目的地地址:端口"
    echo -e "--------------------------------------------------------"

    count_line=$(awk 'END{print NR}' "$raw_conf_path")
    if [ $count_line -eq 0 ]; then
        echo -e "${Info} 暂无配置，请先添加配置"
        return
    fi

    for ((i = 1; i <= $count_line; i++)); do
        trans_conf=$(sed -n "${i}p" "$raw_conf_path")
        eachconf_retrieve

        # 转换方法名称为中文显示
        case $is_encrypt in
        nonencrypt) str="不加密中转" ;;
        encrypttls) str="TLS隧道中转" ;;
        encryptws) str="WS隧道中转" ;;
        encryptwss) str="WSS隧道中转" ;;
        peerno) str="不加密负载均衡" ;;
        peertls) str="TLS隧道负载均衡" ;;
        peerws) str="WS隧道负载均衡" ;;
        peerwss) str="WSS隧道负载均衡" ;;
        decrypttls) str="TLS解密转发" ;;
        decryptws) str="WS解密转发" ;;
        decryptwss) str="WSS解密转发" ;;
        ss) str="Shadowsocks代理" ;;
        socks) str="SOCKS5代理" ;;
        http) str="HTTP代理" ;;
        cdnno) str="不加密CDN转发" ;;
        cdnws) str="WS隧道CDN转发" ;;
        cdnwss) str="WSS隧道CDN转发" ;;
        *) str="" ;;
        esac

        echo -e "  $i  | $str        | $s_port    | $d_ip:$d_port"
        echo -e "--------------------------------------------------------"
    done
}

# 定时重启配置
function cron_restart() {
    echo -e "\n${Info} gost定时重启任务配置"
    echo -e "-----------------------------------"
    echo -e "[1] 配置定时重启任务"
    echo -e "[2] 删除定时重启任务"
    echo -e "-----------------------------------"
    read -p "请选择 [1-2]: " numcron

    case $numcron in
    1)
        echo -e "\n${Info} 选择定时重启类型"
        echo -e "-----------------------------------"
        echo -e "[1] 每X小时重启一次"
        echo -e "[2] 每日固定时间重启"
        echo -e "-----------------------------------"
        read -p "请选择 [1-2]: " numcrontype

        case $numcrontype in
        1)
            read -p "请输入间隔小时数: " cronhr
            if [ "$release" = "alpine" ]; then
                echo "0 */$cronhr * * * /etc/init.d/gost restart" >>/etc/crontabs/root
            else
                echo "0 */$cronhr * * * systemctl restart gost" >>/etc/crontab
            fi
            echo -e "${Info} 定时重启设置成功！每$cronhr小时重启一次"
            ;;
        2)
            read -p "请输入每天重启的时间 (0-23): " cronhr
            if [ "$release" = "alpine" ]; then
                echo "0 $cronhr * * * /etc/init.d/gost restart" >>/etc/crontabs/root
            else
                echo "0 $cronhr * * * systemctl restart gost" >>/etc/crontab
            fi
            echo -e "${Info} 定时重启设置成功！每天$cronhr点重启"
            ;;
        *)
            echo -e "${Error} 输入错误，请重试"
            exit
            ;;
        esac
        ;;
    2)
        if [ "$release" = "alpine" ]; then
            sed -i "/gost/d" /etc/crontabs/root
        else
            sed -i "/gost/d" /etc/crontab
        fi
        echo -e "${Info} 定时重启任务已删除"
        ;;
    *)
        echo -e "${Error} 输入错误，请重试"
        exit
        ;;
    esac
}

# 更新脚本自身
function update_sh() {
    echo -e "${Info} 检查脚本更新..."
    check_sys
    Installation_dependency
    ol_version=$(curl -L -s --connect-timeout 5 "${github_proxy}https://raw.githubusercontent.com/fog-forest/EasyGost/master/gost.sh" | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')

    if [ -n "$ol_version" ]; then
        if [ "$shell_version" != "$ol_version" ]; then
            echo -e "${Info} 发现新版本 $ol_version (当前版本 $shell_version)"
            read -r -p "是否更新? [Y/N] " update_confirm
            case $update_confirm in
            [yY][eE][sS] | [yY])
                wget -N --no-check-certificate "${github_proxy}https://raw.githubusercontent.com/fog-forest/EasyGost/master/gost.sh"
                echo -e "${Info} 脚本已更新至最新版本"
                exit 0
                ;;
            *)
                echo -e "${Info} 已取消更新"
                ;;
            esac
        else
            echo -e "${Info} 当前已是最新版本 ($shell_version)"
        fi
    else
        echo -e "${Error} 检查更新失败，请检查网络连接"
    fi
}

# 主程序入口
update_sh
echo && echo -e "==============================================="
echo -e "          gost 一键安装配置脚本 ${Red_font_prefix}v$shell_version${Font_color_suffix}"
echo -e "==============================================="
echo -e "  作者: KANIKIG | 文档: https://github.com/KANIKIG/Multi-EasyGost"
echo -e "-----------------------------------------------"
echo -e "  特性:"
echo -e "  ① 采用systemd及配置文件管理gost服务"
echo -e "  ② 支持多条转发规则同时生效，无需screen等工具"
echo -e "  ③ 系统重启后配置自动生效"
echo -e "  功能: 支持TCP+UDP转发、加密隧道、解密对接、代理服务等"
echo -e "==============================================="
echo -e "  ${Green_font_prefix}1.${Font_color_suffix} 安装 gost"
echo -e "  ${Green_font_prefix}2.${Font_color_suffix} 更新 gost"
echo -e "  ${Green_font_prefix}3.${Font_color_suffix} 卸载 gost"
echo -e "-----------------------------------------------"
echo -e "  ${Green_font_prefix}4.${Font_color_suffix} 启动 gost 服务"
echo -e "  ${Green_font_prefix}5.${Font_color_suffix} 停止 gost 服务"
echo -e "  ${Green_font_prefix}6.${Font_color_suffix} 重启 gost 服务 (重载配置)"
echo -e "-----------------------------------------------"
echo -e "  ${Green_font_prefix}7.${Font_color_suffix} 新增转发配置"
echo -e "  ${Green_font_prefix}8.${Font_color_suffix} 查看现有配置"
echo -e "  ${Green_font_prefix}9.${Font_color_suffix} 删除指定配置"
echo -e "-----------------------------------------------"
echo -e "  ${Green_font_prefix}10.${Font_color_suffix} 配置定时重启"
echo -e "  ${Green_font_prefix}11.${Font_color_suffix} 自定义TLS证书"
echo -e "===============================================" && echo
read -e -p "请输入操作编号 [1-11]: " num
case "$num" in
1) Install_ct ;;
2) checknew ;;
3) Uninstall_ct ;;
4) Start_ct ;;
5) Stop_ct ;;
6) Restart_ct ;;
7)
    rawconf
    rm -rf "$gost_conf_path"
    confstart
    writeconf
    conflast
    if [ "$release" = "alpine" ]; then
        rc-service gost restart
    else
        systemctl restart gost
    fi
    echo -e "${Info} 配置已生效，当前配置如下"
    show_all_conf
    ;;
8) show_all_conf ;;
9)
    show_all_conf
    read -p "请输入要删除的配置编号: " numdelete
    if echo "$numdelete" | grep -q '[0-9]'; then
        sed -i "${numdelete}d" "$raw_conf_path"
        rm -rf "$gost_conf_path"
        confstart
        writeconf
        conflast
        if [ "$release" = "alpine" ]; then
            rc-service gost restart
        else
            systemctl restart gost
        fi
        echo -e "${Info} 配置已删除，服务已重启"
    else
        echo -e "${Error} 请输入正确的数字"
    fi
    ;;
10) cron_restart ;;
11) cert ;;
*) echo -e "${Error} 请输入正确的编号 [1-11]" ;;
esac
