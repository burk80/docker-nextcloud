FROM php:%%PHP_VERSION%%-%%VARIANT%%3.11

ARG BUILD_DATE
ARG VERSION
ARG NEXTCLOUD_RELEASE
LABEL build_version="Burkversion:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Burk"

# entrypoint.sh and cron.sh dependencies
RUN set -ex; \
    \
    apk add --no-cache \
        rsync \
    ; \
    \
    rm /var/spool/cron/crontabs/root; \
    echo '*/%%CRONTAB_INT%% * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data

# install the PHP extensions we need
# see https://docs.nextcloud.com/server/stable/admin_manual/installation/source_installation.html
RUN \
	apk add --no-cache --virtual=build-dependencies --upgrade \
	$PHPIZE_DEPS \
	autoconf \
	automake \
	bzip2-dev \
	curl \
	ffmpeg \
	file \
	freetype-dev \
	g++ \
	gcc \
        gmp-dev \
	icu-dev \
        imagemagick-dev \	
        libevent-dev \
        libjpeg-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libmemcached-dev \
        libwebp-dev \	
	libxml2 \
        libxml2-dev \
        libzip-dev \	
	make \
	nginx \
        openldap-dev \	
        pcre-dev \	
	php7-dev \
        postgresql-dev \	
	re2c \
	samba-dev \
	samba-client \
	sudo \
	tar \
	unzip  \
	zlib-dev && \
    
    wget https://github.com/matiasdelellis/pdlib/archive/master.zip && \
    mkdir -p /usr/src/php/ext/ && \
    unzip -d /usr/src/php/ext/ master.zip && \
    rm master.zip && \
    docker-php-ext-configure gd --with-freetype-dir=/usr --with-png-dir=/usr --with-jpeg-dir=/usr --with-webp-dir=/usr && \
    docker-php-ext-configure ldap && \
    docker-php-ext-install -j "$(nproc)" \
        bz2 \
	exif \
        gd \
        intl \
        ldap \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
	pdlib-master \
        zip \
        gmp \
	
	
    && \
    \
# pecl will claim success even if one install fails, so we need to perform each install separately
    pecl install APCu-%%APCU_VERSION%%; \
    pecl install memcached-%%MEMCACHED_VERSION%%; \
    pecl install redis-%%REDIS_VERSION%%; \
    pecl install imagick-%%IMAGICK_VERSION%%; \
    \
    docker-php-ext-enable \
        apcu \
        memcached \
        redis \
        imagick \
    ; \
    \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --virtual .nextcloud-phpext-rundeps $runDeps; \
    apk del .build-deps
    
     echo "**** compile smbclient ****" && \
     git clone git://github.com/eduardok/libsmbclient-php.git /tmp/smbclient && \
     cd /tmp/smbclient && \
     phpize7 && \
     ./configure \
	--with-php-config=/usr/bin/php-config7 && \
 make && \
 make install && \

# set recommended PHP.ini settings
# see https://docs.nextcloud.com/server/12/admin_manual/configuration_server/server_tuning.html#enable-php-opcache
RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
    \
    echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini; \
    \
    echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini; \
    \
    mkdir /var/www/data; \
    chown -R www-data:root /var/www; \
    chmod -R g=u /var/www
    
    
    
    echo "**** configure php and nginx for nextcloud ****" && \
 echo "extension="smbclient.so"" > /etc/php7/conf.d/00_smbclient.ini && \
 echo 'apc.enable_cli=1' >> /etc/php7/conf.d/apcu.ini && \

 sed -i \
	'/opcache.enable=1/a opcache.enable_cli=1' \
		/etc/php7/php.ini && \
 echo "env[PATH] = /usr/local/bin:/usr/bin:/bin" >> /etc/php7/php-fpm.conf && \
 echo "**** set version tag ****" && \
 if [ -z ${NEXTCLOUD_RELEASE+x} ]; then \
	NEXTCLOUD_RELEASE=$(curl -s https://raw.githubusercontent.com/nextcloud/nextcloud.com/master/strings.php \
	| awk -F\' '/VERSIONS_SERVER_FULL_STABLE/ {print $2;exit}'); \
 fi && \
 echo "**** download nextcloud ****" && \
 curl -o /app/nextcloud.tar.bz2 -L \
	https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_RELEASE}.tar.bz2 && \
 echo "**** cleanup ****" && \
 apk del --purge \
	build-dependencies && \
 rm -rf \
	/tmp/*


VOLUME /var/www/html
%%VARIANT_EXTRAS%%

ENV NEXTCLOUD_VERSION %%VERSION%%
ENV NEXTCLOUD_PATH="/config/www/nextcloud"

RUN set -ex; \
    apk add --no-cache --virtual .fetch-deps \
        bzip2 \
        gnupg \
    ; \
    \
    curl -fsSL -o nextcloud.tar.bz2 \
        "%%BASE_DOWNLOAD_URL%%/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"; \
    curl -fsSL -o nextcloud.tar.bz2.asc \
        "%%BASE_DOWNLOAD_URL%%/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
# gpg key from https://nextcloud.com/nextcloud.asc
    gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys 28806A878AE423A28372792ED75899B9A724937A; \
    gpg --batch --verify nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
    tar -xjf nextcloud.tar.bz2 -C /usr/src/; \
    gpgconf --kill all; \
    rm -r "$GNUPGHOME" nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
    rm -rf /usr/src/nextcloud/updater; \
    mkdir -p /usr/src/nextcloud/data; \
    mkdir -p /usr/src/nextcloud/custom_apps; \
    chmod +x /usr/src/nextcloud/occ; \
    apk del .fetch-deps

COPY root/ /
COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

# copy local files


# ports and volumes
EXPOSE 443
ENTRYPOINT ["/entrypoint.sh"]
VOLUME /config /data
CMD ["%%CMD%%"]
