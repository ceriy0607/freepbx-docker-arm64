FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Установка зависимостей
RUN apt-get update && apt-get install -y \
    apache2 mariadb-server mariadb-client \
    php php-cli php-mysql php-curl php-mbstring php-xml php-gd php-bcmath \
    sox lame ffmpeg ghostscript libapache2-mod-php \
    curl sudo git subversion wget unzip nano cron supervisor \
    build-essential autoconf libxml2-dev libncurses5-dev uuid-dev libjansson-dev \
    libsqlite3-dev libssl-dev libedit-dev && \
    apt-get clean

#Скачиваем и собираем Asterisk
WORKDIR /usr/src
RUN wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz && \
    mkdir ./asterisk && \
    tar xvf asterisk-22-current.tar.gz --strip-components=1 -C ./asterisk && \
    cd asterisk && \
    contrib/scripts/install_prereq install && \
    ./configure && \
    make -j$(nproc) && make install && make samples && make config && ldconfig && \
    rm -rf ./asterisk-22-current.tar.gz

# Пользователь Asterisk
RUN groupadd asterisk && \
    useradd -r -d /var/lib/asterisk -g asterisk asterisk && \
    usermod -aG audio,dialout asterisk && \
    mkdir -p /var/{lib,log,spool}/asterisk /usr/lib/aarch64-linux-gnu/asterisk && \
    chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /usr/lib/aarch64-linux-gnu/asterisk && \
    echo 'AST_USER="asterisk"' >> /etc/default/asterisk && \
    echo 'AST_GROUP="asterisk"' >> /etc/default/asterisk

# Apache и PHP настройка
RUN bash -c '\
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2) && \
    sed -i "s/^\(upload_max_filesize = \).*/\120M/" /etc/php/${PHP_VERSION}/apache2/php.ini && \
    sed -i "s/^\(memory_limit = \).*/\1256M/" /etc/php/${PHP_VERSION}/apache2/php.ini && \
    sed -i "s/^\(User\|Group\).*/\1 asterisk/" /etc/apache2/apache2.conf && \
    sed -i "s/AllowOverride None/AllowOverride All/" /etc/apache2/apache2.conf && \
    a2enmod rewrite ssl && \
    a2ensite default-ssl && \
    /etc/init.d/apache2 restart'

# Настройка ODBC
RUN echo "[MySQL]" > /etc/odbcinst.ini && \
    echo "Description = ODBC for MySQL (MariaDB)" >> /etc/odbcinst.ini && \
    echo "Driver = /usr/lib/aarch64-linux-gnu/odbc/libmaodbc.so" >> /etc/odbcinst.ini && \
    echo "FileUsage = 1" >> /etc/odbcinst.ini

# Настройка MySQL
RUN echo "[MySQL-asteriskcdrdb]" > /etc/odbc.ini && \
    echo "Description = MySQL connection to 'asteriskcdrdb' database" >> /etc/odbc.ini && \
    echo "Driver = MySQL" >> /etc/odbc.ini && \
    echo "Server = localhost" >> /etc/odbc.ini && \
    echo "Database = asteriskcdrdb" >> /etc/odbc.ini && \
    echo "Port = 3306" >> /etc/odbc.ini && \
    echo "Socket = /var/run/mysqld/mysqld.sock" >> /etc/odbc.ini && \
    echo "Option = 3" >> /etc/odbc.ini

# Настройка mysqld
RUN echo "[mysqld]" > /etc/mysql/mariadb.conf.d/60-freepbx.cnf && \
    echo 'sql_mode = "ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"' >> /etc/mysql/mariadb.conf.d/60-freepbx.cnf

#Перезагрузка mariadb и apache2 
RUN /etc/init.d/mariadb restart && /etc/init.d/apache2 restart

# Установка FreePBX
WORKDIR /usr/src
RUN git clone -b release/17.0 https://github.com/FreePBX/framework.git freepbx && \
    cd freepbx && \
    ./start_asterisk start && \
    ./install -n

# Правильная работа systemd
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80 443 5060/udp 5061/udp

CMD ["/usr/bin/supervisord", "-n"]