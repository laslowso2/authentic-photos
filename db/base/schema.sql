-- Authentic Photos - database schema (metadata-only photo store)
-- Idempotent DDL: safe to run more than once.
-- Engine InnoDB (transactions, FKs), utf8mb4 (full Unicode incl. emoji).

CREATE DATABASE IF NOT EXISTS authphotos
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE authphotos;

-- Photos available for licensing. image_url is a placeholder (no object storage yet).
CREATE TABLE IF NOT EXISTS photos (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title         VARCHAR(200)    NOT NULL,
  photographer  VARCHAR(150)    NOT NULL,
  description    TEXT           NULL,
  price_cents   INT UNSIGNED    NOT NULL,              -- store money as integer cents
  currency      CHAR(3)         NOT NULL DEFAULT 'USD',
  license_type  ENUM('standard','extended') NOT NULL DEFAULT 'standard',
  image_url     VARCHAR(500)    NOT NULL,
  is_active     BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_photos_active (is_active),
  KEY idx_photos_photographer (photographer)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Customers. external_subject holds the OIDC 'sub' from Thunder after login.
CREATE TABLE IF NOT EXISTS customers (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  external_subject VARCHAR(255)    NOT NULL,           -- Thunder/OIDC subject id
  email            VARCHAR(255)    NULL,
  display_name     VARCHAR(200)    NULL,
  created_at       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_customers_subject (external_subject)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Orders: a customer's request to license a photo.
CREATE TABLE IF NOT EXISTS orders (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id  BIGINT UNSIGNED NOT NULL,
  photo_id     BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED    NOT NULL,
  currency     CHAR(3)         NOT NULL DEFAULT 'USD',
  status       ENUM('pending','paid','fulfilled','cancelled') NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_photo (photo_id),
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
  CONSTRAINT fk_orders_photo    FOREIGN KEY (photo_id)    REFERENCES photos(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Licenses: issued once an order is fulfilled. license_key is what the buyer receives.
CREATE TABLE IF NOT EXISTS licenses (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id     BIGINT UNSIGNED NOT NULL,
  photo_id     BIGINT UNSIGNED NOT NULL,
  customer_id  BIGINT UNSIGNED NOT NULL,
  license_key  CHAR(36)        NOT NULL,               -- UUID issued by the API
  license_type ENUM('standard','extended') NOT NULL,
  issued_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   TIMESTAMP       NULL,                   -- NULL = perpetual license
  PRIMARY KEY (id),
  UNIQUE KEY uq_licenses_key (license_key),
  KEY idx_licenses_customer (customer_id),
  CONSTRAINT fk_licenses_order    FOREIGN KEY (order_id)    REFERENCES orders(id),
  CONSTRAINT fk_licenses_photo    FOREIGN KEY (photo_id)    REFERENCES photos(id),
  CONSTRAINT fk_licenses_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
