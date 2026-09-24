-- =====================================================================
-- Olist Brazilian E-Commerce: relational schema (SQLite)
-- 9 tables, primary keys and foreign keys reflect the real relations.
-- Центральная таблица — orders; остальные подключаются через order_id,
-- product_id, seller_id, customer_id и почтовый префикс (zip prefix).
-- =====================================================================
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS category_translation;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS geolocation;

-- Клиенты. customer_id уникален для заказа, customer_unique_id — для человека.
CREATE TABLE customers (
    customer_id               TEXT PRIMARY KEY,
    customer_unique_id        TEXT NOT NULL,
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state            TEXT
);

-- Продавцы
CREATE TABLE sellers (
    seller_id                 TEXT PRIMARY KEY,
    seller_zip_code_prefix    TEXT,
    seller_city               TEXT,
    seller_state              TEXT
);

-- Справочник перевода категорий (PT -> EN)
CREATE TABLE category_translation (
    product_category_name          TEXT PRIMARY KEY,
    product_category_name_english  TEXT
);

-- Товары. FK на справочник категорий не ставим: 2 категории в products
-- отсутствуют в переводе, и 610 товаров вообще без категории.
CREATE TABLE products (
    product_id                  TEXT PRIMARY KEY,
    product_category_name       TEXT,
    product_name_lenght         INTEGER,   -- орфография оригинала
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            REAL,
    product_length_cm           REAL,
    product_height_cm           REAL,
    product_width_cm            REAL
);

-- Заказы: статусы и все ключевые даты жизненного цикла
CREATE TABLE orders (
    order_id                       TEXT PRIMARY KEY,
    customer_id                    TEXT NOT NULL REFERENCES customers(customer_id),
    order_status                   TEXT,
    order_purchase_timestamp       TEXT,
    order_approved_at              TEXT,
    order_delivered_carrier_date   TEXT,
    order_delivered_customer_date  TEXT,
    order_estimated_delivery_date  TEXT
);

-- Позиции заказа (один заказ -> много позиций, у каждой свой продавец)
CREATE TABLE order_items (
    order_id             TEXT NOT NULL REFERENCES orders(order_id),
    order_item_id        INTEGER NOT NULL,
    product_id           TEXT NOT NULL REFERENCES products(product_id),
    seller_id            TEXT NOT NULL REFERENCES sellers(seller_id),
    shipping_limit_date  TEXT,
    price                REAL,
    freight_value        REAL,
    PRIMARY KEY (order_id, order_item_id)
);

-- Платежи (заказ может оплачиваться несколькими способами)
CREATE TABLE order_payments (
    order_id              TEXT NOT NULL REFERENCES orders(order_id),
    payment_sequential    INTEGER NOT NULL,
    payment_type          TEXT,
    payment_installments  INTEGER,
    payment_value         REAL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- Отзывы. review_id в исходных данных не уникален (один отзыв может быть
-- привязан к нескольким заказам), поэтому ключ составной.
CREATE TABLE order_reviews (
    review_id                TEXT NOT NULL,
    order_id                 TEXT NOT NULL REFERENCES orders(order_id),
    review_score             INTEGER CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TEXT,
    review_answer_timestamp  TEXT,
    PRIMARY KEY (review_id, order_id)
);

-- Геолокация: много точек на один почтовый префикс, естественного ключа нет
CREATE TABLE geolocation (
    geolocation_zip_code_prefix  TEXT,
    geolocation_lat              REAL,
    geolocation_lng              REAL,
    geolocation_city             TEXT,
    geolocation_state            TEXT
);

-- Индексы под частые JOIN
CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_items_product     ON order_items(product_id);
CREATE INDEX idx_items_seller      ON order_items(seller_id);
CREATE INDEX idx_reviews_order     ON order_reviews(order_id);
CREATE INDEX idx_geo_zip           ON geolocation(geolocation_zip_code_prefix);
