FROM php:8.2-apache

# Install extensions
RUN apt-get update && apt-get install -y     libzip-dev libpng-dev libonig-dev libxml2-dev     && docker-php-ext-install mysqli pdo pdo_mysql zip gd     && a2enmod rewrite headers expires

# Copy app
COPY . /var/www/html/

# Set Apache docroot
ENV APACHE_DOCUMENT_ROOT=/var/www/html
RUN sed -ri -e "s!/var/www/html!!g" /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/default-ssl.conf

# Permissions (basic)
RUN chown -R www-data:www-data /var/www/html && chmod -R 755 /var/www/html

EXPOSE 80
