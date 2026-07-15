-- Financial data warehouse (star schema) — separate 'findw' database, same MySQL instance.
-- Used by the Ballerina DataService to serve financial reports to the finance app.
CREATE DATABASE IF NOT EXISTS findw
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE findw;

-- Date dimension (daily grain).
CREATE TABLE IF NOT EXISTS dim_date (
  date_key    INT          NOT NULL PRIMARY KEY,   -- YYYYMMDD
  full_date   DATE         NOT NULL,
  year        INT          NOT NULL,
  quarter     INT          NOT NULL,
  month       INT          NOT NULL,
  month_name  VARCHAR(12)  NOT NULL,
  day         INT          NOT NULL,
  KEY idx_dim_date_ym (year, month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Photo (product) dimension — denormalized from the operational store.
CREATE TABLE IF NOT EXISTS dim_photo (
  photo_id      BIGINT       NOT NULL PRIMARY KEY,
  title         VARCHAR(200) NOT NULL,
  photographer  VARCHAR(150) NOT NULL,
  license_type  ENUM('standard','extended') NOT NULL,
  price_cents   INT          NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sales fact (one row per licensed sale).
CREATE TABLE IF NOT EXISTS fact_sales (
  sale_id       BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  date_key      INT          NOT NULL,
  photo_id      BIGINT       NOT NULL,
  customer_ref  VARCHAR(64)  NOT NULL,
  license_type  ENUM('standard','extended') NOT NULL,
  amount_cents  INT          NOT NULL,
  currency      CHAR(3)      NOT NULL DEFAULT 'USD',
  KEY idx_fs_date (date_key),
  KEY idx_fs_photo (photo_id),
  KEY idx_fs_license (license_type),
  CONSTRAINT fk_fs_date  FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
  CONSTRAINT fk_fs_photo FOREIGN KEY (photo_id) REFERENCES dim_photo(photo_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Let the app user (used by the Ballerina service) read/write the warehouse.
GRANT ALL PRIVILEGES ON findw.* TO 'authphotos_app'@'%';
FLUSH PRIVILEGES;
