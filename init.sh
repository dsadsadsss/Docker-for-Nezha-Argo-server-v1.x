#!/usr/bin/env bash

# 首次运行时执行以下流程，再次运行时存在 /etc/supervisor/conf.d/damon.conf 文件，直接到最后一步
if [ ! -s /etc/supervisor/conf.d/damon.conf ]; then
  
  # 设置 Github CDN 及若干变量，如是 IPv6 only 或者大陆机器，需要 Github 加速网，可自行查找放在 GH_PROXY 处 ，如 https://mirror.ghproxy.com/ ，能不用就不用，减少因加速网导致的故障。
  GH_PROXY='https://ghproxy.lvedong.eu.org/'
  GRPC_PROXY_PORT=${GRPC_PROXY_PORT:-'443'}
  DASH_VER=${DASH_VER:-'v2.2.0'}

  if [[ "$DASH_VER" =~ ^(v)?0\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
    GRPC_PORT=${GRPC_PORT:-'5555'}
    WEB_PORT=${WEB_PORT:-'8080'}
    AGENT_VER=${AGENT_VER:-'v0.17.5'}
  else
    GRPC_PORT=${GRPC_PORT:-'8008'}
    WEB_PORT=${WEB_PORT:-'8008'}
    AGENT_VER=${AGENT_VER:-'v2.2.2'}
  fi
  CADDY_HTTP_PORT=2052
  PRO_PORT=${PORT:-'80'}
  WORK_DIR=/dashboard
  IS_UPDATE=${IS_UPDATE:-'yes'}
  # 如不分离备份的 github 账户，默认与哪吒登陆的 github 账户一致
  GH_BACKUP_USER=${GH_BACKUP_USER:-$GH_USER}

  error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
  info() { echo -e "\033[32m\033[01m$*\033[0m"; }   # 绿色
  hint() { echo -e "\033[33m\033[01m$*\033[0m"; }   # 黄色

  # 如参数不齐全，容器退出，另外处理某些环境变量填错后的处理
  [[ -z "$GH_USER" || -z "$GH_CLIENTID" || -z "$GH_CLIENTSECRET" || -z "$ARGO_AUTH" || -z "$ARGO_DOMAIN" ]] && error " There are variables that are not set. "
  [[ "$ARGO_AUTH" =~ TunnelSecret ]] && grep -qv '"' <<< "$ARGO_AUTH" && ARGO_AUTH=$(sed 's@{@{"@g;s@[,:]@"\0"@g;s@}@"}@g' <<< "$ARGO_AUTH")  # Json 时，没有了"的处理
  [[ "$ARGO_AUTH" =~ ey[A-Z0-9a-z=]{120,250}$ ]] && ARGO_AUTH=$(awk '{print $NF}' <<< "$ARGO_AUTH") # Token 复制全部，只取最后的 ey 开始的
  [ -n "$GH_REPO" ] && grep -q '/' <<< "$GH_REPO" && GH_REPO=$(awk -F '/' '{print $NF}' <<< "$GH_REPO")  # 填了项目全路径的处理

  # 检测是否需要启用 Github CDN，如能直接连通，则不使用
  [ -n "$GH_PROXY" ] && wget --server-response --quiet --output-document=/dev/null --no-check-certificate --tries=2 --timeout=3 https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/README.md >/dev/null 2>&1 && unset GH_PROXY

  # 设置 DNS
  echo -e "nameserver 127.0.0.11\nnameserver 8.8.4.4\nnameserver 223.5.5.5\nnameserver 2001:4860:4860::8844\nnameserver 2400:3200::1\n" > /etc/resolv.conf

  # 设置 +8 时区 (北京时间)
  ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  dpkg-reconfigure -f noninteractive tzdata

  # 判断处理器架构
  case "$(uname -m)" in
    aarch64|arm64 )
      ARCH=arm64
      ;;
    x86_64|amd64 )
      ARCH=amd64
      ;;
    armv7* )
      ARCH=arm
      ;;
    * ) error " $(text 2) "
  esac

   # 使用caddy反代
    GRPC_PROXY_RUN="$WORK_DIR/caddy run --config $WORK_DIR/Caddyfile --watch"
if [ -z "$API_TOKEN" ]; then
    if [ -n "$UUID" ] && [ "$UUID" != "0" ]; then
   cat > $WORK_DIR/Caddyfile  << EOF
{
    http_port $CADDY_HTTP_PORT
}

:$PRO_PORT {
    handle /${UUID} {
        file_server {
            root /tmp
            browse
        }
        rewrite * /list.log
    }

    reverse_proxy /vls* {
        to localhost:8002
    }

    reverse_proxy /vms* {
        to localhost:8001
    }
   
    reverse_proxy {
        to localhost:$WEB_PORT
    }
}

:$GRPC_PROXY_PORT {
    reverse_proxy {
        to localhost:$GRPC_PORT
        transport http {
            versions h2c 2
        }
    }
    tls $WORK_DIR/nezha.pem $WORK_DIR/nezha.key
}

EOF
 else
  cat > $WORK_DIR/Caddyfile  << EOF
{
    http_port $CADDY_HTTP_PORT
}

:$PRO_PORT {
    reverse_proxy {
        to localhost:$WEB_PORT
    }
}

:$GRPC_PROXY_PORT {
    reverse_proxy {
        to localhost:$GRPC_PORT
        transport http {
            versions h2c 2
        }
    }
    tls $WORK_DIR/nezha.pem $WORK_DIR/nezha.key
}

EOF
 fi
else
if [ -n "$UUID" ] && [ "$UUID" != "0" ]; then
   cat > $WORK_DIR/Caddyfile  << EOF
{
    http_port $CADDY_HTTP_PORT
}

:$PRO_PORT {
    handle /${UUID} {
        file_server {
            root /tmp
            browse
        }
        rewrite * /list.log
    }

    reverse_proxy /vls* {
        to localhost:8002
    }

    reverse_proxy /vms* {
        to localhost:8001
    }
    reverse_proxy /upload* {
        to localhost:8009
    }
    reverse_proxy {
        to localhost:$WEB_PORT
    }
}

:$GRPC_PROXY_PORT {
    reverse_proxy {
        to localhost:$GRPC_PORT
        transport http {
            versions h2c 2
        }
    }
    tls $WORK_DIR/nezha.pem $WORK_DIR/nezha.key
}

EOF
 else
  cat > $WORK_DIR/Caddyfile  << EOF
{
    http_port $CADDY_HTTP_PORT
}

:$PRO_PORT {
    reverse_proxy /upload* {
        to localhost:8009
    }
    reverse_proxy {
        to localhost:$WEB_PORT
    }
}

:$GRPC_PROXY_PORT {
    reverse_proxy {
        to localhost:$GRPC_PORT
        transport http {
            versions h2c 2
        }
    }
    tls $WORK_DIR/nezha.pem $WORK_DIR/nezha.key
}

EOF
 fi
fi

 
  # 下载需要的应用
  add_v_prefix() {
    local version=$1
    if [[ ! $version =~ ^v ]]; then
        version="v$version"
    fi
    echo "$version"
   }
   remove_v_prefix() {
    local version=$1
    if [[ $version =~ ^v ]]; then
        version="${version#v}"
    fi
    echo "$version"
    }
   CADDY_VER=${CADDY_VER:-'2.9.1'}
   CADDY_VER=$(remove_v_prefix "$CADDY_VER")
    wget -c ${GH_PROXY}https://github.com/caddyserver/caddy/releases/download/v${CADDY_VER}/caddy_${CADDY_VER}_linux_${ARCH}.tar.gz -qO- | tar xz -C $WORK_DIR caddy
   if [ "$IS_UPDATE" = 'no' ]; then
   DASH_VER=$(add_v_prefix "$DASH_VER")
   echo "DASH_VER = $DASH_VER"
   wget -O /tmp/dashboard.zip ${GH_PROXY}https://github.com/nezhahq/nezha/releases/download/${DASH_VER}/dashboard-linux-$ARCH.zip
   unzip /tmp/dashboard.zip -d /tmp
   if [ -s "/tmp/dist/dashboard-linux-${ARCH}" ]; then
   mv -f /tmp/dist/dashboard-linux-$ARCH $WORK_DIR/app
   else
   mv -f /tmp/dashboard-linux-$ARCH $WORK_DIR/app
   fi
   else
   DASHBOARD_LATEST=$(wget -qO- "${GH_PROXY}https://api.github.com/repos/naiba/nezha/releases/latest" | awk -F '"' '/"tag_name"/{print $4}')
   wget -O /tmp/dashboard.zip ${GH_PROXY}https://github.com/naiba/nezha/releases/download/$DASHBOARD_LATEST/dashboard-linux-$ARCH.zip
   unzip /tmp/dashboard.zip -d /tmp
   if [ -s "/tmp/dist/dashboard-linux-${ARCH}" ]; then
   mv -f /tmp/dist/dashboard-linux-$ARCH $WORK_DIR/app
   else
   mv -f /tmp/dashboard-linux-$ARCH $WORK_DIR/app
   fi
   fi
  
  wget -qO $WORK_DIR/cloudflared ${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH
  if [ "$IS_UPDATE" = 'no' ]; then
  
  AGENT_VER=$(add_v_prefix "$AGENT_VER")
  echo "AGENT_VER = $AGENT_VER"
  wget -O $WORK_DIR/nezha-agent.zip ${GH_PROXY}https://github.com/nezhahq/agent/releases/download/${AGENT_VER}/nezha-agent_linux_$ARCH.zip
  unzip $WORK_DIR/nezha-agent.zip -d $WORK_DIR/
  rm -rf $WORK_DIR/nezha-agent.zip /tmp/dist /tmp/dashboard.zip
  else  
  wget -O $WORK_DIR/nezha-agent.zip ${GH_PROXY}https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_$ARCH.zip
  unzip $WORK_DIR/nezha-agent.zip -d $WORK_DIR/
  rm -rf $WORK_DIR/nezha-agent.zip /tmp/dist /tmp/dashboard.zip
  fi
  
  [ -n "$API_TOKEN" ] && wget -O $WORK_DIR/nezfz ${GH_PROXY}https://github.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/releases/download/nezfuz/nezfz-linux-amd64

  # 根据参数生成哪吒服务端配置文件
  [ ! -d data ] && mkdir data
if [[ "$DASH_VER" =~ ^(v)?0\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  cat > ${WORK_DIR}/data/config.yaml << EOF
Debug: false
HTTPPort: $WEB_PORT
Language: zh-CN
GRPCPort: $GRPC_PORT
GRPCHost: $ARGO_DOMAIN
ProxyGRPCPort: $GRPC_PROXY_PORT
TLS: true
Oauth2:
  Type: "github" #Oauth2 登录接入类型，github/gitlab/jihulab/gitee/gitea ## Argo-容器版本只支持 github
  Admin: "$GH_USER" #管理员列表，半角逗号隔开
  ClientID: "$GH_CLIENTID" # 在 ${GH_PROXY}https://github.com/settings/developers 创建，无需审核 Callback 填 http(s)://域名或IP/oauth2/callback
  ClientSecret: "$GH_CLIENTSECRET"
  Endpoint: "" # 如gitea自建需要设置 ## Argo-容器版本只支持 github
site:
  Brand: "Nezha Probe"
  Cookiename: "nezha-dashboard" #浏览器 Cookie 字段名，可不改
  Theme: "default"
EOF
else
  seed="${ARGO_DOMAIN}${GH_CLIENTSECRET}${GH_CLIENTID}${GH_USER}"
  hash=$(echo -n "$seed" | sha256sum | cut -d' ' -f1)
  AGENT_UUID1="${hash:0:8}-${hash:8:4}-${hash:12:4}-${hash:16:4}-${hash:20:12}"

  token_hash=$(echo -n "TOKEN_${seed}" | sha256sum | cut -d' ' -f1)
  DASH_TOKEN1=$(echo -n "$token_hash" | tr 'abcdef' 'ABCDEF' | head -c 32)
  AGENT_UUID=${AGENT_UUID:-${AGENT_UUID1:-'fraewrwdf-das-2sd2-4324-f232df'}}
  DASH_TOKEN=${DASH_TOKEN:-${DASH_TOKEN1:-'fse-3432-d430-rw3-df32-dfs3-4334gtg'}}
  
    cat > ${WORK_DIR}/data/config.yaml << EOF
agent_secret_key: $DASH_TOKEN
debug: false
listen_port: $GRPC_PORT
language: zh-CN
site_name: "Nezha Probe"
install_host: $ARGO_DOMAIN:$GRPC_PROXY_PORT
location: Asia/Shanghai
tls: true
oauth2:
   GitHub:
     client_id: "$GH_CLIENTID"
     client_secret: "$GH_CLIENTSECRET"
     endpoint:
       auth_url: "https://github.com/login/oauth/authorize"
       token_url: "https://github.com/login/oauth/access_token"
     user_info_url: "https://api.github.com/user"
     user_id_path: "id"
EOF

    cat > ${WORK_DIR}/data/config.yml << EOF
client_secret: $DASH_TOKEN
debug: false
disable_auto_update: false
disable_command_execute: false
disable_force_update: false
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: true
ip_report_period: 1800
report_delay: 3
server: 127.0.0.1:$GRPC_PORT
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: false
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: $AGENT_UUID
EOF
fi


  # 下载包含本地数据的 sqlite.db 文件，生成18位随机字符串用于本地 Token
  if [[ "$DASH_VER" =~ ^(v)?0\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
   if [ ! -f "${WORK_DIR}/data/sqlite.db" ]; then
   wget -P ${WORK_DIR}/data/ ${GH_PROXY}https://github.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/raw/main/sqlite.db
   fi
   [ -z "$NO_SUIJI" ] && LOCAL_TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18)
   [ -n "$NO_SUIJI" ] && LOCAL_TOKEN="$NO_SUIJI"
   LOCAL_DATE=$(sqlite3 ${WORK_DIR}/data/sqlite.db "SELECT created_at FROM servers WHERE name LIKE '%local%' COLLATE NOCASE LIMIT 1;") 
   [ -z "$LOCAL_DATE" ] && LOCAL_DATE='2023-04-23 13:02:00.770756566+08:00'
   sqlite3 ${WORK_DIR}/data/sqlite.db "update servers set secret='${LOCAL_TOKEN}' where created_at='${LOCAL_DATE}'"
 fi
  # SSH path 与 GH_CLIENTSECRET 一样
  echo root:"$GH_CLIENTSECRET" | chpasswd root
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g;s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  service ssh restart

  # 判断 ARGO_AUTH 为 json 还是 token
  # 如为 json 将生成 argo.json 和 argo.yml 文件
  if [[ "$ARGO_AUTH" =~ TunnelSecret ]]; then
    ARGO_RUN="cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/argo.yml run"

    echo "$ARGO_AUTH" > $WORK_DIR/argo.json

    cat > $WORK_DIR/argo.yml << EOF
tunnel: $(cut -d '"' -f12 <<< "$ARGO_AUTH")
credentials-file: $WORK_DIR/argo.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: https://localhost:$GRPC_PROXY_PORT
    path: /proto.NezhaService/*
    originRequest:
      http2Origin: true
      noTLSVerify: true
  - hostname: $ARGO_DOMAIN
    service: ssh://localhost:22
    path: /$GH_CLIENTID/*
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$PRO_PORT
  - service: http_status:404
EOF

  # 如为 token 时
  elif [[ "$ARGO_AUTH" =~ ^ey[A-Z0-9a-z=]{120,250}$ ]]; then
    ARGO_RUN="cloudflared tunnel --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}"
  fi

  # 生成自签署SSL证书
  openssl genrsa -out $WORK_DIR/nezha.key 2048
  openssl req -new -subj "/CN=$ARGO_DOMAIN" -key $WORK_DIR/nezha.key -out $WORK_DIR/nezha.csr
  openssl x509 -req -days 36500 -in $WORK_DIR/nezha.csr -signkey $WORK_DIR/nezha.key -out $WORK_DIR/nezha.pem

  # 生成 backup.sh 文件的步骤1 - 设置环境变量
  cat > $WORK_DIR/backup.sh << EOF
#!/usr/bin/env bash

# backup.sh 传参 a 自动还原； 传参 m 手动还原； 传参 f 强制更新面板 app 文件及 cloudflared 文件，并备份数据至成备份库
IS_UPDATE=$IS_UPDATE
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PROXY=$GH_PROXY
GH_PAT=$GH_PAT
GH_BACKUP_USER=$GH_BACKUP_USER
GH_EMAIL=$GH_EMAIL
GH_REPO=$GH_REPO
ARCH=$ARCH
WORK_DIR=$WORK_DIR
DAYS=5
IS_DOCKER=1
DASH_VER=$DASH_VER
########
EOF

  # 生成 backup.sh 文件的步骤2 - 在线获取 template/bakcup.sh 模板生成完整 backup.sh 文件
  wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/backup.sh | sed '1,/^########/d' >> $WORK_DIR/backup.sh
  cat > $WORK_DIR/backup2.sh << EOF
#!/usr/bin/env bash

# backup.sh 传参 a 自动还原； 传参 m 手动还原； 传参 f 强制更新面板 app 文件及 cloudflared 文件，并备份数据至成备份库
IS_UPDATE=$IS_UPDATE
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PROXY=$GH_PROXY
GH_PAT=$GH_PAT
GH_BACKUP_USER=$GH_BACKUP_USER
GH_EMAIL=$GH_EMAIL
GH_REPO=$GH_REPO
ARCH=$ARCH
WORK_DIR=$WORK_DIR
DAYS=5
IS_DOCKER=1
DASH_VER=$DASH_VER
########
EOF

  # 生成 backup2.sh 文件的步骤2 - 在线获取 template/bakcup.sh 模板生成完整 backup.sh 文件
  wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/backup2.sh | sed '1,/^########/d' >> $WORK_DIR/backup2.sh
 cat > $WORK_DIR/update.sh << EOF
  #!/usr/bin/env bash

# backup.sh 传参 a 自动还原； 传参 m 手动还原； 传参 f 强制更新面板 app 文件及 cloudflared 文件，并备份数据至成备份库
IS_UPDATE=$IS_UPDATE
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PROXY=$GH_PROXY
GH_PAT=$GH_PAT
GH_BACKUP_USER=$GH_BACKUP_USER
GH_EMAIL=$GH_EMAIL
GH_REPO=$GH_REPO
ARCH=$ARCH
WORK_DIR=$WORK_DIR
DAYS=5
IS_DOCKER=1
DASH_VER=$DASH_VER
########
EOF

  # 生成 update.sh 文件的步骤2 - 在线获取 template/bakcup.sh 模板生成完整 backup.sh 文件
  wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/update.sh | sed '1,/^########/d' >> $WORK_DIR/update.sh
# 生成 restore.sh  
if [[ -n "$GH_BACKUP_USER" && -n "$GH_EMAIL" && -n "$GH_REPO" && -n "$GH_PAT" ]]; then
    # 生成 restore.sh 文件的步骤1 - 设置环境变量
    cat > $WORK_DIR/restore.sh << EOF
#!/usr/bin/env bash

# restore.sh 传参 a 自动还原 README.md 记录的文件，当本地与远程记录文件一样时不还原； 传参 f 不管本地记录文件，强制还原成备份库里 README.md 记录的文件； 传参 dashboard-***.tar.gz 还原成备份库里的该文件；不带参数则要求选择备份库里的文件名
GH_PROXY=$GH_PROXY
IS_UPDATE=$IS_UPDATE
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PAT=$GH_PAT
GH_BACKUP_USER=$GH_BACKUP_USER
GH_REPO=$GH_REPO
WORK_DIR=$WORK_DIR
TEMP_DIR=/tmp/restore_temp
NO_ACTION_FLAG=/tmp/flag
IS_DOCKER=1
DASH_VER=$DASH_VER
########
EOF

    # 生成 restore.sh 文件的步骤2 - 在线获取 template/restore.sh 模板生成完整 restore.sh 文件
    wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/restore.sh | sed '1,/^########/d' >> $WORK_DIR/restore.sh
  fi
# 生成 restore2.sh
if [[ -n "$GH_BACKUP_USER" && -n "$GH_EMAIL" && -n "$GH_REPO" && -n "$GH_PAT" ]]; then
    # 生成 restore.sh 文件的步骤1 - 设置环境变量
    cat > $WORK_DIR/restore2.sh << EOF
#!/usr/bin/env bash

# restore2.sh 传参 a 自动还原 README.md 记录的文件，当本地与远程记录文件一样时不还原； 传参 f 不管本地记录文件，强制还原成备份库里 README.md 记录的文件； 传参 dashboard-***.tar.gz 还原成备份库里的该文件；不带参数则要求选择备份库里的文件名
GH_PROXY=$GH_PROXY
IS_UPDATE=$IS_UPDATE
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PAT=$GH_PAT
GH_BACKUP_USER=$GH_BACKUP_USER
GH_REPO=$GH_REPO
WORK_DIR=$WORK_DIR
TEMP_DIR=/tmp/restore_temp
NO_ACTION_FLAG=/tmp/flag
IS_DOCKER=1
DASH_VER=$DASH_VER
########
EOF

    # 生成 restore2.sh 文件的步骤2 - 在线获取 template/2restore.sh 模板生成完整 restore2.sh 文件
    wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/restore2.sh | sed '1,/^########/d' >> $WORK_DIR/restore2.sh
# 恢复备份文件
chmod 777 $WORK_DIR/restore2.sh
$WORK_DIR/restore2.sh a
fi
# 生成 renew.sh 文件的步骤1 - 设置环境变量
  cat > $WORK_DIR/renew.sh << EOF
#!/usr/bin/env bash
LOCAL_TOKEN=$LOCAL_TOKEN
GH_PROXY=$GH_PROXY
WORK_DIR=/dashboard
TEMP_DIR=/tmp/renew
IS_UPDATE=$IS_UPDATE
DASH_VER=$DASH_VER
########
EOF


# 生成 renew.sh 文件的步骤2 - 在线获取 template/renew.sh 模板生成完整 renew.sh 文件
  wget -qO- ${GH_PROXY}https://raw.githubusercontent.com/dsadsadsss/Docker-for-Nezha-Argo-server-v1.x/main/template/renew.sh | sed '1,/^########/d' >> $WORK_DIR/renew.sh

  # 生成定时任务: 1.每天北京时间 3:30:00 更新备份和还原文件，2.每天北京时间 4:00:00 备份一次，并重启 cron 服务； 3.每分钟自动检测在线备份文件里的内容
  [ -z "$NO_AUTO_RENEW" ] && [ -s $WORK_DIR/renew.sh ] && ! grep -q "$WORK_DIR/renew.sh" /etc/crontab && echo "30 3 * * * root bash $WORK_DIR/renew.sh" >> /etc/crontab
  [ -s $WORK_DIR/backup.sh ] && ! grep -q "$WORK_DIR/backup.sh" /etc/crontab && echo "0 */2 * * * root bash $WORK_DIR/backup.sh a" >> /etc/crontab
  [ -s $WORK_DIR/update.sh ] && ! grep -q "$WORK_DIR/update.sh" /etc/crontab && echo "0 4 * * * root bash $WORK_DIR/update.sh a" >> /etc/crontab
  [ -z "$NO_RES" ] && [ -s $WORK_DIR/restore.sh ] && ! grep -q "$WORK_DIR/restore.sh" /etc/crontab && echo "* * * * * root bash $WORK_DIR/restore.sh a" >> /etc/crontab
  service cron restart

# 启动xxxry
wget -qO- https://github.com/dsadsadsss/d/releases/download/sd/kano-6-amd-w > $WORK_DIR/webapp
chmod 777 $WORK_DIR/webapp
WEB_RUN="$WORK_DIR/webapp"
if [[ "$DASH_VER" =~ ^(v)?0\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  if [ "$IS_UPDATE" = 'no' ]; then
   AG_RUN="$WORK_DIR/nezha-agent -s localhost:$GRPC_PORT --disable-auto-update --disable-force-update -p $LOCAL_TOKEN"
  else
   AG_RUN="$WORK_DIR/nezha-agent -s localhost:$GRPC_PORT -p $LOCAL_TOKEN"
  fi
else
    AG_RUN="$WORK_DIR/nezha-agent -c $WORK_DIR/data/config.yml"
fi
  # 生成 supervisor 进程守护配置文件
  cat > /etc/supervisor/conf.d/damon.conf << EOF
[supervisord]
nodaemon=true
logfile=/dev/null
pidfile=/run/supervisord.pid

[program:grpcproxy]
command=$GRPC_PROXY_RUN
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root

[program:nezha]
command=$WORK_DIR/app
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root

[program:agent]
command=$AG_RUN
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root

[program:argo]
command=$WORK_DIR/$ARGO_RUN
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root
EOF
if [ -n "$API_TOKEN" ] && [ "$API_TOKEN" != "0" ]; then
    cat >> /etc/supervisor/conf.d/damon.conf << EOF

[program:nezfz]
command=$WORK_DIR/nezfz
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root
EOF
fi
if [ -n "$UUID" ] && [ "$UUID" != "0" ]; then
    cat >> /etc/supervisor/conf.d/damon.conf << EOF

[program:webapp]
command=$WEB_RUN
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null
user=root
EOF
get_country_code() {
    country_code="UN"
    urls=("http://ipinfo.io/country" "https://ifconfig.co/country" "https://ipapi.co/country")

    for url in "${urls[@]}"; do
        if [ "$download_tool" = "curl" ]; then
            country_code=$(curl -s "$url")
        else
            country_code=$(wget -qO- "$url")
        fi

        if [ -n "$country_code" ] && [ ${#country_code} -eq 2 ]; then
            break
        fi
    done

    echo "     国家:    $country_code"
}
get_country_code
XIEYI='vl'
XIEYI2='vm'
CF_IP=${CF_IP:-'ip.sb'}
SUB_NAME=${SUB_NAME:-'nezha'}
up_url="${XIEYI}ess://${UUID}@${CF_IP}:443?path=%2F${XIEYI}s%3Fed%3D2048&security=tls&encryption=none&host=${ARGO_DOMAIN}&type=ws&sni=${ARGO_DOMAIN}#${country_code}-${SUB_NAME}"
VM_SS="{ \"v\": \"2\", \"ps\": \"${country_code}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/vms?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\", \"allowlnsecure\": \"flase\"}"
if command -v base64 >/dev/null 2>&1; then
  vm_url="${XIEYI2}ess://$(echo -n "$VM_SS" | base64 -w 0)"
fi
x_url="${up_url}\n${vm_url}"
encoded_url=$(echo -e "${x_url}\n${up_url2}" | base64 -w 0)
echo -e $encoded_url > /tmp/list.log
echo "============  <订阅地址:>  ========  "
echo "  "
echo "订阅地址1: 项目网址/$UUID"
echo "  "
echo "订阅地址2: $ARGO_DOMAIN/$UUID"
echo "  "
echo "=============================="
fi
  # 赋执行权给 sh 及所有应用
  [ -n "$API_TOKEN" ] && chmod +x $WORK_DIR/{cloudflared,app,nezfz,nezha-agent,*.sh}
  [ -z "$API_TOKEN" ] && chmod +x $WORK_DIR/{cloudflared,app,nezha-agent,*.sh}

fi


# 运行 supervisor 进程守护
supervisord -c /etc/supervisor/supervisord.conf
