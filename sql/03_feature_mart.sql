-- =====================================================================
-- Финальная витрина признаков: одна строка = один доставленный заказ с отзывом.
-- JOIN 5 исходных таблиц (orders, customers, sellers, products, category_translation
-- + агрегаты f_* из 02_feature_tables.sql).
-- =====================================================================
DROP TABLE IF EXISTS order_features;
CREATE TABLE order_features AS
SELECT
    o.order_id,
    o.order_purchase_timestamp,
    -- ---------- сроки и логистика ----------
    julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
        AS delivery_days,                         -- фактический срок доставки
    julianday(o.order_estimated_delivery_date) - julianday(o.order_purchase_timestamp)
        AS estimated_days,                        -- обещанный срок
    julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date)
        AS delay_days,                            -- >0 = опоздание
    CASE WHEN date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date)
         THEN 1 ELSE 0 END                                        AS is_late,
    (julianday(o.order_approved_at) - julianday(o.order_purchase_timestamp)) * 24
        AS approval_hours,
    julianday(o.order_delivered_carrier_date) - julianday(o.order_approved_at)
        AS seller_handling_days,                  -- продавец -> перевозчик
    julianday(o.order_delivered_customer_date) - julianday(o.order_delivered_carrier_date)
        AS carrier_days,                          -- перевозчик -> клиент
    CASE WHEN o.order_delivered_carrier_date > fi.shipping_limit_date
         THEN 1 ELSE 0 END                                        AS seller_missed_limit,
    CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER)   AS purchase_month,
    CAST(strftime('%w', o.order_purchase_timestamp) AS INTEGER)   AS purchase_dow,
    CAST(strftime('%H', o.order_purchase_timestamp) AS INTEGER)   AS purchase_hour,
    -- ---------- состав заказа ----------
    fi.n_items, fi.n_products, fi.n_sellers,
    fi.items_price, fi.freight_value, fi.max_item_price,
    fi.freight_value / NULLIF(fi.items_price, 0)                  AS freight_ratio,
    fi.total_weight_g, fi.total_volume_cm3,
    fi.avg_photos_qty, fi.avg_description_len,
    COALESCE(ct.product_category_name_english,
             p.product_category_name, 'unknown')                  AS category,
    -- ---------- оплата ----------
    fp.payment_value, fp.max_installments, fp.n_payments, fp.n_payment_types,
    fp.payment_type,
    -- ---------- география и продавец ----------
    c.customer_state,
    s.seller_state,
    CASE WHEN c.customer_state = s.seller_state THEN 1 ELSE 0 END AS same_state,
    gc.lat AS customer_lat, gc.lng AS customer_lng,
    gs.lat AS seller_lat,   gs.lng AS seller_lng,
    sh.seller_prior_orders,
    sr.seller_prior_reviews,
    sr.seller_prior_low_rate,
    -- ---------- целевая переменная ----------
    fr.review_score
FROM orders o
JOIN f_review     fr ON fr.order_id   = o.order_id
JOIN f_items      fi ON fi.order_id   = o.order_id
JOIN f_main_item  mi ON mi.order_id   = o.order_id
JOIN customers    c  ON c.customer_id = o.customer_id
JOIN sellers      s  ON s.seller_id   = mi.seller_id
JOIN products     p  ON p.product_id  = mi.product_id
LEFT JOIN category_translation ct ON ct.product_category_name = p.product_category_name
LEFT JOIN f_payments    fp ON fp.order_id = o.order_id
LEFT JOIN f_seller_hist sh ON sh.order_id = o.order_id
LEFT JOIN f_seller_rating sr ON sr.order_id = o.order_id
LEFT JOIN f_geo_zip     gc ON gc.zip = c.customer_zip_code_prefix
LEFT JOIN f_geo_zip     gs ON gs.zip = s.seller_zip_code_prefix
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
ORDER BY o.order_purchase_timestamp;
