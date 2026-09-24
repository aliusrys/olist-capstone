-- =====================================================================
-- Промежуточные агрегаты уровня заказа (JOIN + GROUP BY + оконные функции).
-- Материализуем их в таблицы с индексами: финальная витрина (03) собирается
-- из них за секунды. Используются ТОЛЬКО данные, известные к моменту доставки;
-- из отзывов берём лишь целевую оценку.
-- =====================================================================

-- 1. Целевая переменная. У 547 заказов несколько отзывов: берём последний.
DROP TABLE IF EXISTS f_review;
CREATE TABLE f_review AS
SELECT order_id, review_score, review_answer_timestamp
FROM (
    SELECT order_id, review_score, review_answer_timestamp,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_timestamp DESC) AS rn
    FROM order_reviews
)
WHERE rn = 1;
CREATE UNIQUE INDEX ix_f_review ON f_review(order_id);

-- 2. Позиции заказа + характеристики товаров (JOIN order_items x products)
DROP TABLE IF EXISTS f_items;
CREATE TABLE f_items AS
SELECT oi.order_id,
       COUNT(*)                                AS n_items,
       COUNT(DISTINCT oi.product_id)           AS n_products,
       COUNT(DISTINCT oi.seller_id)            AS n_sellers,
       SUM(oi.price)                           AS items_price,
       SUM(oi.freight_value)                   AS freight_value,
       MAX(oi.price)                           AS max_item_price,
       SUM(p.product_weight_g)                 AS total_weight_g,
       SUM(p.product_length_cm * p.product_height_cm * p.product_width_cm)
                                               AS total_volume_cm3,
       AVG(p.product_photos_qty)               AS avg_photos_qty,
       AVG(p.product_description_lenght)       AS avg_description_len,
       MAX(oi.shipping_limit_date)             AS shipping_limit_date
FROM order_items oi
LEFT JOIN products p ON p.product_id = oi.product_id
GROUP BY oi.order_id;
CREATE UNIQUE INDEX ix_f_items ON f_items(order_id);

-- 3. «Главная» позиция заказа (самая дорогая) -> категория и продавец
DROP TABLE IF EXISTS f_main_item;
CREATE TABLE f_main_item AS
SELECT order_id, product_id, seller_id
FROM (
    SELECT order_id, product_id, seller_id,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY price DESC, order_item_id) AS rn
    FROM order_items
)
WHERE rn = 1;
CREATE UNIQUE INDEX ix_f_main_item ON f_main_item(order_id);

-- 4. Платежи: сумма, рассрочка, число платежей, основной способ оплаты
DROP TABLE IF EXISTS f_payments;
CREATE TABLE f_payments AS
WITH ranked AS (
    SELECT order_id, payment_type, payment_value, payment_installments,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY payment_value DESC) AS rn
    FROM order_payments
)
SELECT order_id,
       SUM(payment_value)                              AS payment_value,
       MAX(payment_installments)                       AS max_installments,
       COUNT(*)                                        AS n_payments,
       COUNT(DISTINCT payment_type)                    AS n_payment_types,
       MAX(CASE WHEN rn = 1 THEN payment_type END)     AS payment_type
FROM ranked
GROUP BY order_id;
CREATE UNIQUE INDEX ix_f_payments ON f_payments(order_id);

-- 5. Опыт продавца: сколько заказов у него было ДО текущей покупки.
--    Окно упорядочено по времени покупки -> без заглядывания в будущее.
DROP TABLE IF EXISTS f_seller_hist;
CREATE TABLE f_seller_hist AS
SELECT o.order_id,
       COUNT(*) OVER (PARTITION BY mi.seller_id
                      ORDER BY o.order_purchase_timestamp
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
           AS seller_prior_orders
FROM orders o
JOIN f_main_item mi ON mi.order_id = o.order_id;
CREATE UNIQUE INDEX ix_f_seller_hist ON f_seller_hist(order_id);

-- 6. Средние координаты почтового префикса (1 млн точек -> ~19 тыс. префиксов)
DROP TABLE IF EXISTS f_geo_zip;
CREATE TABLE f_geo_zip AS
SELECT geolocation_zip_code_prefix AS zip,
       AVG(geolocation_lat)        AS lat,
       AVG(geolocation_lng)        AS lng
FROM geolocation
GROUP BY geolocation_zip_code_prefix;
CREATE UNIQUE INDEX ix_f_geo_zip ON f_geo_zip(zip);

-- 7. Репутация продавца на момент покупки: доля низких оценок по отзывам,
--    которые были оставлены ДО даты текущего заказа (range JOIN по времени).
--    Для новых продавцов без истории значение NULL.
DROP TABLE IF EXISTS f_seller_reviews;
CREATE TABLE f_seller_reviews AS
SELECT mi.seller_id,
       fr.review_answer_timestamp                     AS answer_ts,
       CASE WHEN fr.review_score <= 2 THEN 1 ELSE 0 END AS is_low
FROM f_review fr
JOIN f_main_item mi ON mi.order_id = fr.order_id;
CREATE INDEX ix_f_seller_reviews ON f_seller_reviews(seller_id, answer_ts);

DROP TABLE IF EXISTS f_seller_rating;
CREATE TABLE f_seller_rating AS
SELECT o.order_id,
       COUNT(sr.seller_id) AS seller_prior_reviews,
       AVG(sr.is_low)      AS seller_prior_low_rate
FROM orders o
JOIN f_main_item mi ON mi.order_id = o.order_id
LEFT JOIN f_seller_reviews sr
       ON sr.seller_id = mi.seller_id
      AND sr.answer_ts < o.order_purchase_timestamp
GROUP BY o.order_id;
CREATE UNIQUE INDEX ix_f_seller_rating ON f_seller_rating(order_id);
