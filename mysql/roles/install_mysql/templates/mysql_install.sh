#!/bin/sh
# 编译安装管理MySQL
App=mysql
AppName=MySQL
AppBase=/app
AppDir=$AppBase/$App
AppInit=$AppDir/scripts/mysql_install_db
AppService=/etc/init.d/mysqld
AppDaemon=$AppDir/bin/mysqld_safe
AppAdmin=$AppDir/bin/mysqladmin
AppCnf=/etc/my.cnf

AppSrcBase=/app/src
AppSrcFile=mysql-*.tar.*
AppSrcDir=$(find $AppSrcBase -maxdepth 1 -name "$AppSrcFile" -type f  2> /dev/null | sed -e 's/.tar.*$//' -e 's/^.\///')
AppUser=$(grep "^[[:space:]]*user" $AppCnf 2> /dev/null | awk -F= '{print $2}' | sed 's/[[:space:]]//g')
AppDataDir=$(grep "^[[:space:]]*datadir" $AppCnf 2> /dev/null | awk -F= '{print $2}' | sed 's/[[:space:]]//g')

AppUser=${AppUser:-mysql}
AppGroup=$AppUser
AppDataDir=${AppDataDir:-$AppDir/data}

RemoveFlag=0
InstallFlag=0

# 获取PID
fpid()
{
    AppMasterPid=$(ps aux | grep "$AppDaemon" | grep -v "grep" | awk '{print $2}' 2> /dev/null)
    AppWorkerPid=$(ps aux | grep "mysqld" | grep -Ev "grep|mysqld_safe" | awk '{print $2}' 2> /dev/null)
}

# 查询状态
fstatus()
{
    fpid

    if [ ! -f "$AppAdmin" ]; then
            echo "$AppName 未安装"
    else
        echo "$AppName 已安装"
        if [ ! -d "$AppDataDir" ]; then
            echo "$AppName 未创建授权表"
        else
            if [ -z "$AppMasterPid" ]; then
                echo "$AppName 未启动"
            else
                echo "$AppName 正在运行"
            fi
        fi
    fi
}

# 删除
fremove()
{
    fpid
    RemoveFlag=1

    if [ -z "$AppMasterPid" ]; then
        if [ -d "$AppDir" ]; then
            rm -rf $AppDir && echo "删除 $AppName"
        else
            echo "$AppName 未安装"
        fi
    else
        echo "$AppName 正在运行" && exit 1
    fi
}

# 备份
fbackup()
{
    Day=$(date +%Y-%m-%d)
    BackupFile=$App.$Day.tgz

    if [ -f "$AppDaemon" ]; then
        cd $AppBase
        tar zcvf $BackupFile --exclude=data/* --exclude=var/* $App --backup=numbered
        [ $? -eq 0 ] && echo "$AppName 备份成功" || echo "$AppName 备份失败"
    else
        echo "$AppName 未安装"
    fi
}

# 安装
finstall()
{
    fpid
    InstallFlag=1

    if [ -z "$AppMasterPid" ]; then
        test -f "$AppAdmin" && echo "$AppName 已安装"
        [ $? -ne 0 ] && fupdate && fcpconf
    else
        echo "$AppName 正在运行"
    fi
}

# 拷贝配置
fcpconf()
{
    cp -vf --backup=numbered $AppDir/support-files/mysql.server $AppService
    chmod u+x $AppService
    cp -vf --backup=numbered $ScriptDir/my.cnf $AppCnf
}

# 更新
fupdate()
{
    Operate="更新"
    [ $InstallFlag -eq 1 ] && Operate="安装"
    [ $RemoveFlag -ne 1 ] && fbackup

    cd $AppSrcBase
    test -d "$AppSrcDir" && rm -rf $AppSrcDir
    
    yum -y install cmake wget gcc gcc-c++ ncurses-devel cmake make perl
    tar zxf $AppSrcFile || tar jxf $AppSrcFile || tar Jxf $AppSrcFile
    cd $AppSrcDir

    cmake . \
    "-DCMAKE_BUILD_TYPE:STRING=Release" \
    "-DCMAKE_INSTALL_PREFIX:PATH=$AppDir" \
    "-DDEFAULT_CHARSET=utf8" \
    "-DDEFAULT_COLLATION=utf8_general_ci" \
    "-DWITH_EMBEDDED_SERVER:BOOL=OFF" \
    "-DWITH_UNIT_TESTS:BOOL=OFF" \
    "-LAH"

    [ $? -eq 0 ] && make && make install
    if [ $? -eq 0 ]; then
        echo "$AppName $Operate成功"
        echo "$AppDir/lib" > /etc/ld.so.conf.d/mysql.conf
    else
        echo "$AppName $Operate失败"
        exit 1
    fi
}

# 新建运行用户
fuser()
{
    id -gn $AppGroup &> /dev/null
    if [ $? -ne 0 ]; then
        groupadd $AppGroup && echo "新建 $AppName 运行组：$AppGroup"
    else
        echo "$AppName 运行组：$AppGroup 已存在"
    fi

    id -un $AppUser &> /dev/null
    if [ $? -ne 0 ]; then
        useradd -s /bin/false -M -g $AppGroup $AppUser
        if [ $? -eq 0 ]; then
            echo "新建 $AppName 运行用户：$AppUser"
            echo "$0Ngdb3myS&19#1" | passwd --stdin $AppUser &> /dev/null
        fi
    else
        echo "$AppName 运行用户：$AppUser 已存在"
    fi
}

# 初始化授权表
finit()
{
    fuser

    if [ -n "$AppDataDir" ]; then
        echo "$AppDataDir" | grep -q "^/"
        if [ $? -eq 1 ]; then
            echo "错误：$AppName 配置文件 $AppCnf datadir 参数必须为绝对路径"
            exit 1
        fi
    else
        echo "$AppName 数据存储目录使用默认值"
    fi

    if [ ! -e "$AppDataDir" ]; then
        mkdir -p $AppDataDir && echo "新建 $AppName 数据存储目录：$AppDataDir"
    elif [ ! -d "$AppDataDir" ]; then
        echo "路径：$AppDataDir 非目录"
    else
        echo "$AppName 数据存储目录：$AppDataDir 已存在"
    fi

    $AppInit --basedir=$AppDir --datadir=$AppDataDir --user=$AppUser
    [ $? -eq 0 ] && echo "成功初始化 $AppName 授权表" || echo "初始化 $AppName 授权表失败"
}

# 启动
fstart()
{
    fpid

    if [ -n "$AppMasterPid" ]; then
        echo "$AppName 正在运行"
    else
        $AppService start && echo "启动 $AppName" || echo "$AppName 启动失败"
    fi
}

# 停止
fstop()
{
    fpid

    if [ -n "$AppMasterPid" ]; then
        $AppService stop && echo "停止 $AppName" || echo "$AppName 停止失败"
    else
        echo "$AppName 未启动"
    fi
}

# 重载配置
freload()
{
    fpid

    if [ -n "$AppWorkerPid" ]; then
        $AppService reload && echo "重载 $AppName 配置" || echo "$AppName 重载配置失败"
    else
        echo "$AppName 未启动"
    fi
}

# 重启
frestart()
{
    fpid
    [ -n "$AppMasterPid" ] && fstop
    fstart
}

# 终止进程
fkill()
{
    fpid

    if [ -n "$AppMasterPid" ]; then
        echo "$AppMasterPid" | xargs kill -9
        if [ $? -eq 0 ]; then
            echo "终止 $AppName 主进程"
        else
            echo "终止 $AppName 主进程失败"
        fi
    else
        echo "$AppName 主进程未运行"
    fi

    if [ -n "$AppWorkerPid" ]; then
        echo "$AppWorkerPid" | xargs kill -9
        if [ $? -eq 0 ]; then
            echo "终止 $AppName 工作进程"
        else
            echo "终止 $AppName 工作进程失败"
        fi
    else
        echo "$AppName 工作进程未运行"
    fi
}


ScriptDir=$(cd $(dirname $0); pwd)
ScriptFile=$(basename $0)
case "$1" in
    "install"   ) finstall;;
    "update"    ) fupdate;;
    "reinstall" ) fremove && finstall;;
    "remove"    ) fremove;;
    "backup"    ) fbackup;;
    "user"      ) fuser;;
    "init"      ) finit;;
    "start"     ) fstart;;
    "stop"      ) fstop;;
    "restart"   ) frestart;;
    "status"    ) fstatus;;
    "cpconf"    ) fcpconf;;
    "reload"    ) freload;;
    "kill"      ) fkill;;
    *           )
    echo "$ScriptFile install              安装 $AppName"
    echo "$ScriptFile update               更新 $AppName"
    echo "$ScriptFile reinstall            重装 $AppName"
    echo "$ScriptFile remove               删除 $AppName"
    echo "$ScriptFile backup               备份 $AppName"
    echo "$ScriptFile init                 初始化 $AppName"
    echo "$ScriptFile start                启动 $AppName"
    echo "$ScriptFile stop                 停止 $AppName"
    echo "$ScriptFile restart              重启 $AppName"
    echo "$ScriptFile status               查询 $AppName 状态"
    echo "$ScriptFile cpconf               拷贝 $AppName 配置"
    echo "$ScriptFile reload               重载 $AppName 配置"
    echo "$ScriptFile kill                 终止 $AppName 进程"
    echo "$ScriptFile user                 新建 $AppName 运行用户"
    ;;
esac
