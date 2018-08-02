#!/bin/bash
# Filename: installNgxLua.sh
# Author: zhoubangjun
# Date: 2017/12/4
# Desc: 在原有的nginx上添加lua模块
# Usage: /bin/bash installNgxLua.sh
# LastModify: 2018/7/31


get_nginx_info(){
   which nginx >/dev/null
   [ $? -ne 0 ] && echo "Not found nginx" && exit 1

   ngxTmpFile=$(mktemp /tmp/nginx-XXXXXX)
   nginx -V &>${ngxTmpFile}

   nginxVs=$(cat ${ngxTmpFile} | head -1 | awk -F'/' '{print $2}')
   nginxPid=$(cat ${ngxTmpFile} | grep -oP "pid-path=.*nginx.pid" | awk -F'=' '{print $2}')
   nginxConfFile=$(cat ${ngxTmpFile} | grep -oP "conf-path=.*nginx.conf" | awk -F'=' '{print $2}')
   ngxPathDir=$(echo ${nginxConfFile%/*})

   [ "$(grep -oP 'lua' ${nginxConfFile})" != "" ] && echo "已经存在lua配置" \
       && exit 1

   [ "$(grep -oP 'lua-nginx' ${ngxTmpFile})" != "" ] && echo "已经安装过lua扩展" \
       && exit 1
}

install_lua(){
    yum install pcre-devel openssl-devel -y
    cd /tmp
    # download ngx_devel_kit
    [ -f v0.3.0.tar.gz ] \
        || wget -c https://github.com/simpl/ngx_devel_kit/archive/v0.3.0.tar.gz
    [ $? -ne 0 ] && echo "download failed" && exit 1
    [ -d ngx_devel_kit-0.3.0 ] && rm -rf ngx_devel_kit-0.3.0
    tar xf v0.3.0.tar.gz

    # download lua-nginx-module
    [ -f v0.10.10.tar.gz ] \
        || wget -c https://github.com/openresty/lua-nginx-module/archive/v0.10.10.tar.gz
    [ $? -ne 0 ] && echo "download failed" && exit 1
    [ -d lua-nginx-module-0.10.10 ] && rm -rf lua-nginx-module-0.10.10
    tar xf v0.10.10.tar.gz

    # install luajit
    [ -f LuaJIT-2.0.5.tar.gz ] \
        || wget -c http://luajit.org/download/LuaJIT-2.0.5.tar.gz
    [ $? -ne 0 ] && echo "download failed" && exit 1
    [ -d LuaJIT-2.0.5 ] && rm -rf LuaJIT-2.0.5
    tar xf LuaJIT-2.0.5.tar.gz
    cd LuaJIT-2.0.5
    make install PREFIX=/usr/local/luajit >/dev/null
    echo "/usr/local/luajit/lib" > /etc/ld.so.conf.d/luajit.conf
    ldconfig
    export LUAJIT_LIB=/usr/local/luajit/lib
    export LUAJIT_INC=/usr/local/luajit/include/luajit-2.0
    cd ..

    # download nginx-${nginxVs}
    [ -f nginx-${nginxVs}.tar.gz ] \
        || wget -c http://nginx.org/download/nginx-${nginxVs}.tar.gz
    [ $? -ne 0 ] && echo "download failed" && exit 1
    [ -d nginx-${nginxVs} ] && rm -rf nginx-${nginxVs}
    tar xf nginx-${nginxVs}.tar.gz

    cd nginx-${nginxVs}

    sed -i  's#$# --add-module=/tmp/ngx_devel_kit-0.3.0 --add-module=/tmp/lua-nginx-module-0.10.10#' ${ngxTmpFile}
    grep configure ${ngxTmpFile} | awk -F':' '{print $2}' > ${ngxTmpFile}.sh
    sed -i 's/^/.\/configure /' ${ngxTmpFile}.sh
    sh ${ngxTmpFile}.sh

    cpuCoresNum=$(cat /proc/cpuinfo | grep processor | wc -l)
    make -j${cpuCoresNum} >/dev/null

    # 替换旧的nginx二进制文件
    [ $? -ne 0 ] && echo "nginx 编译错误，请检查" && exit 1
    nginxBin=$(which nginx)
    mv ${nginxBin} ${nginxBin}.old

    cp objs/nginx ${nginxBin}
    nginx -t >/dev/null
    [ $? -ne 0 ] && echo "nginx 配置错误，请检查" && exit 1
    kill -USR2 $(cat ${nginxPid})
    [ -f ${nginxPid}.oldbin ] && kill -WINCH $(cat ${nginxPid}.oldbin) \
        || echo "no ${nginxPid}.oldbin"
    [ -f ${nginxPid}.oldbin ] && kill -QUIT $(cat ${nginxPid}.oldbin)

    echo "安装完成"
    rm -f ${ngxTmpFile} ${ngxTmpFile}.sh
    cd ..
}

deploy_waf(){
    wafRepoUrl="https://github.com/premier815/ngx_lua_waf"
    cd /tmp

    which git &>/dev/null
    [ $? -ne 0 ] && yum install git -y
    git clone  ${wafRepoUrl} -b master waf
    [ $? -ne 0 ] && echo "仓库clone失败" && exit 1

    [ -d ${ngxPathDir}/waf ] && rm -rf ${ngxPathDir}/waf
    mv waf ${ngxPathDir}

    # 添加lua配置
    cp ${nginxConfFile} ${nginxConfFile}.bak
    sed -i "/http_x_forwarded_for/a\ \ \ \ #waf\n\
    lua_package_path '${ngxPathDir}/waf/?.lua';\n\
    lua_shared_dict limit 10m;\n\
    init_by_lua_file ${ngxPathDir}/waf/init.lua;\n\
    access_by_lua_file ${ngxPathDir}/waf/waf.lua;\n" ${nginxConfFile}
    echo "lua配置完成"
}

main(){
    get_nginx_info
    install_lua
    deploy_waf
}

main
