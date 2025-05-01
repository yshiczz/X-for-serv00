#!/usr/bin/bash

USERNAME=$(whoami)
USERNAME_DOMAIN=$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
WORKDIR="/home/${USERNAME}/domains/${USERNAME_DOMAIN}.useruno.com/public_nodejs"
WSPATH=${WSPATH:-'serv00'}
UUID=${UUID:-'de04add9-5c68-8bab-950c-08cd5320df18'}
WEB_USERNAME=${WEB_USERNAME:-'admin'}
WEB_PASSWORD=${WEB_PASSWORD:-'password'}

set_language() {
    devil lang set english
}

set_domain_dir() {
    local DOMAIN="${USERNAME_DOMAIN}.useruno.com"
    if devil www list | grep nodejs | grep "/domains/${DOMAIN}"; then
        if [ ! -d ${WORKDIR}/public ]; then
            git clone https://github.com/k0baya/mikutap ${WORKDIR}/public
        fi
        return 0
    else
        echo "正在检测 NodeJS 环境，请稍候..."
        nohup devil www del ${DOMAIN} >/dev/null 2>&1
        devil www add ${DOMAIN} nodejs /usr/local/bin/node22
        rm -rf ${WORKDIR}/public
        git clone https://github.com/k0baya/mikutap ${WORKDIR}/public
    fi
}

reserve_port() {
    local port_list
    local port_count
    local current_port
    local needed_ports
    local max_attempts
    local attempts

    local add_port
    add_port() {
        local port=$1
        local result=$(devil port add tcp "$port")
        echo "尝试添加预留端口 $port: $result"
    }

    local delete_udp_port
    delete_udp_port() {
        local port=$1
        local result=$(devil port del udp "$port")
        echo "删除 UDP 端口 $port: $result"
    }

    update_port_list() {
        port_list=$(devil port list)
        port_count=$(echo "$port_list" | grep -c 'tcp')
    }

    # 循环删除 UDP 端口
    port_list=$(devil port list)
    while echo "$port_list" | grep -q 'udp'; do
        UDP_PORT=$(echo "$port_list" | grep 'udp' | awk 'NR==1{print $1}')
        delete_udp_port $UDP_PORT
        update_port_list
    done

    update_port_list

    # 随机选择起始端口
    start_port=$(( RANDOM % 63077 + 1024 ))  # 1024-64000之间的随机数

    if [ $start_port -le 32512 ]; then
        current_port=$start_port
        increment=1
    else
        current_port=$start_port
        increment=-1
    fi

    max_attempts=100
    attempts=0

    if [ "$port_count" -ge 1 ]; then
        PORT3=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
        echo "预留端口为 $PORT3"
        return 0
    else
        needed_ports=$((1 - port_count))

        while [ $needed_ports -gt 0 ]; do
            if add_port $current_port; then
                update_port_list
                needed_ports=$((3 - port_count))

                if [ $needed_ports -le 0 ]; then
                    break
                fi
            fi
            current_port=$((current_port + increment))
            attempts=$((attempts + 1))

            if [ $attempts -ge $max_attempts ]; then
                echo "超过最大尝试次数，无法添加足够的预留端口"
                exit 1
            fi
        done
    fi

    update_port_list
    PORT3=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
    echo "预留端口为 $PORT3"
}



generate_dotenv() {

    generate_uuid() {
    local uuid
    uuid=$(uuidgen -r)
    while [[ ${uuid:0:1} =~ [0-9] ]]; do
        uuid=$(uuidgen -r)
    done
    echo "$uuid"
    }

    printf "请输入 ARGO_AUTH（必填）："
    read -r ARGO_AUTH
    printf "请输入 ARGO_DOMAIN_TR（必填）："
    read -r ARGO_DOMAIN_TR
    echo "请在Cloudflare中为隧道添加域名 ${ARGO_DOMAIN_TR} 指向 HTTP://localhost:${PORT3},添加完成请按回车继续"
    read
    printf "请输入 UUID（默认值：de04add9-5c68-8bab-950c-08cd5320df18）："
    read -r UUID
    printf "请输入 WSPATH（默认值：serv00）："
    read -r WSPATH
    printf "请输入 WEB_USERNAME（默认值：admin）："
    read -r WEB_USERNAME
    printf "请输入 WEB_PASSWORD（默认值：password）："
    read -r WEB_PASSWORD

    if [ -z "${ARGO_AUTH}" ] || [ -z "${ARGO_DOMAIN_TR}" ]; then
    echo "Error! 所有选项都不能为空！"
    rm -rf ${WORKDIR}/*
    rm -rf ${WORKDIR}/.*
    exit 1
    fi

    if [ -z "${UUID}" ]; then
        echo "正在生成 UUID..."
        UUID=$(generate_uuid)
    fi
    if [ -z "${WSPATH}" ]; then
        WSPATH='serv00'
    fi
    if [ -z "${WEB_USERNAME}" ]; then
        WEB_USERNAME='admin'
    fi
    if [ -z "${WEB_PASSWORD}" ]; then
        WEB_PASSWORD='password'
    fi

    cat > ${WORKDIR}/.env << EOF
ARGO_AUTH=${ARGO_AUTH}
ARGO_DOMAIN_TR=${ARGO_DOMAIN_TR}
UUID=${UUID}
WSPATH=${WSPATH}
WEB_USERNAME=${WEB_USERNAME}
WEB_PASSWORD=${WEB_PASSWORD}
EOF
}

get_app() {
    echo "正在下载 app.js 请稍候..."
    wget -t 10 -qO ${WORKDIR}/app.js https://raw.githubusercontent.com/yshiczz/X-for-serv00/main/app.js
    if [ $? -ne 0 ]; then
        echo "app.js 下载失败！请检查网络情况！"
        exit 1
    fi
    echo "正在下载 package.json 请稍候..."
    wget -t 10 -qO ${WORKDIR}/package.json https://raw.githubusercontent.com/yshiczz/X-for-serv00/main/package.json
    if [ $? -ne 0 ]; then
        echo "package.json 下载失败！请检查网络情况！"
        exit 1
    fi

    echo "正在安装依赖..."
    nohup npm22 install > /dev/null 2>&1
}

get_core() {
    local TMP_DIRECTORY=$(mktemp -d)
    local ZIP_FILE="${TMP_DIRECTORY}/Xray-freebsd-64.zip"
    echo "正在下载 Web.js 请稍候..."
    wget -t 10 -qO "$ZIP_FILE" https://github.com/XTLS/Xray-core/releases/latest/download/Xray-freebsd-64.zip
    if [ $? -ne 0 ]; then
        echo "Web.js 安装失败！请检查网络情况！"
        exit 1
    else
        unzip -qo "$ZIP_FILE" -d "$TMP_DIRECTORY"
        install -m 755 "${TMP_DIRECTORY}/xray" "${WORKDIR}/web.js"
        rm -rf "$TMP_DIRECTORY"
    fi

    echo "正在下载 GEOSITE 数据库，请稍候..."
    wget -t 10 -qO ${WORKDIR}/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
    if [ $? -ne 0 ]; then
        echo "GEOSITE 数据库下载失败！请检查网络情况！"
        exit 1
    fi

    echo "正在下载 GEOIP 数据库，请稍候..."
    wget -t 10 -qO ${WORKDIR}/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
    if [ $? -ne 0 ]; then
        echo "GEOIP 数据库下载失败！请检查网络情况！"
        exit 1
    fi
}

generate_config() {
    cat > ${WORKDIR}/config.json << EOF
{
    "log": {
        "loglevel": "error"
    },
    "inbounds":[
        {
            "port":${PORT3},
            "listen":"127.0.0.1",
            "protocol":"trojan",
            "settings":{
                "clients":[
                    {
                        "password":"${UUID}"
                    }
                ]
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-trojan"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing":{
        "domainStrategy":"AsIs",
        "rules":[
            {
                "type":"field",
                "domain":[
                    "geosite:category-ads-all"
                ],
                "outboundTag":"block"
            }
        ]
    }
}
EOF
}

generate_argo() {
  cat > argo.sh << ABC
#!/usr/bin/bash

USERNAME=\$(whoami)
USERNAME_DOMAIN=\$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
WORKDIR="/home/\${USERNAME}/domains/\${USERNAME_DOMAIN}.useruno.com/public_nodejs"

cd \${WORKDIR}
source \${WORKDIR}/.env

check_file() {
    wget -t 10 https://cloudflared.bowring.uk/binaries/cloudflared-freebsd-latest.7z

    if [ \$? -ne 0 ]; then
        echo "Cloudflared 客户端安装失败！请检查 hosts 文件是否屏蔽了下载地址！" > list
        exit 1
    else
        7z x cloudflared-freebsd-latest.7z -bb > /dev/null \
        && rm cloudflared-freebsd-latest.7z \
        && mv -f ./temp/* ./cloudflared \
        && rm -rf temp \
        && chmod +x cloudflared
    fi
}


run() {
        if [[ -n "\${ARGO_AUTH}" && -n "\${ARGO_DOMAIN_TR}" ]]; then
            nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 run --token \${ARGO_AUTH} > /dev/null 2>&1 &
    else
        echo '请设置环境变量 \$ARGO_AUTH 和 \$ARGO_DOMAIN_TR' > \${WORKDIR}/list
        exit 1
    fi
    }

export_list() {
  cat > list << EOF
*******************************************
V2-rayN:
----------------------------
trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-trojan%3Fed%3D2560&security=tls&host=\${ARGO_DOMAIN_TR}&type=ws&sni=\${ARGO_DOMAIN_TR}#Argo-k0baya-Trojan
*******************************************
小火箭:
----------------------------
trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?peer=\${ARGO_DOMAIN_TR}&plugin=obfs-local;obfs=websocket;obfs-host=\${ARGO_DOMAIN_TR};obfs-uri=/${WSPATH}-trojan?ed=2560#Argo-k0baya-Trojan
*******************************************
Clash:
----------------------------
- {name: Argo-k0baya-Trojan, type: trojan, server: upos-sz-mirrorcf1ov.bilivideo.com, port: 443, password: ${UUID}, udp: true, tls: true, sni: \${ARGO_DOMAIN_TR}, skip-cert-verify: false, network: ws, ws-opts: { path: /${WSPATH}-trojan?ed=2560, headers: { Host: \${ARGO_DOMAIN_TR} } } }
*******************************************
EOF
echo "trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-trojan%3Fed%3D2560&security=tls&host=\${ARGO_DOMAIN_TR}&type=ws&sni=\${ARGO_DOMAIN_TR}#uno-tr" > sub

}
[ ! -e \${WORKDIR}/cloudflared ] && check_file
run
export_list
ABC
}

set_language
set_domain_dir
reserve_port

cd ${WORKDIR}
[ ! -e ${WORKDIR}/.env ] && generate_dotenv
[ ! -e ${WORKDIR}/app.js ] || [ ! -e ${WORKDIR}/package.json ] && get_app
[ ! -e ${WORKDIR}/web.js ] && get_core
generate_config
generate_argo

[ -e ${WORKDIR}/argo.sh ] && echo "请访问 https://${USERNAME_DOMAIN}.useruno.com/status 获取服务端状态, 当 cloudflared 与 web.js 正常运行后，访问 https://${USERNAME_DOMAIN}.useruno.com/list 获取配置"
