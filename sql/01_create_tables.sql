-- Загрузка данных и создание таблицы уровня заказа

CREATE OR REPLACE TABLE customers AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_customers_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE orders AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_orders_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE order_items AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_order_items_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE payments AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_order_payments_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE reviews AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_order_reviews_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE products AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_products_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE sellers AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_sellers_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE geolocation AS
SELECT *
FROM read_csv_auto(
    'data/raw/olist_geolocation_dataset.csv',
    header = true
);

CREATE OR REPLACE TABLE category_translation AS
SELECT *
FROM read_csv_auto(
    'data/raw/product_category_name_translation.csv',
    header = true
);


-- Агрегация товарных позиций до уровня заказа

CREATE OR REPLACE VIEW items_by_order AS
SELECT
    order_id,
    SUM(price) AS product_revenue,
    SUM(freight_value) AS freight_value,
    COUNT(*) AS items_count,
    COUNT(DISTINCT product_id) AS products_count,
    COUNT(DISTINCT seller_id) AS sellers_count
FROM order_items
GROUP BY order_id;


-- Агрегация платежей до уровня заказа

CREATE OR REPLACE VIEW payments_by_order AS
SELECT
    order_id,
    SUM(payment_value) AS payment_value,
    COUNT(*) AS payment_records,
    MAX(payment_installments) AS installments_max,
    COUNT(DISTINCT payment_type) AS payment_types_count
FROM payments
GROUP BY order_id;


-- Агрегация отзывов до уровня заказа

CREATE OR REPLACE VIEW reviews_by_order AS
SELECT
    order_id,
    AVG(review_score) AS review_score,
    COUNT(DISTINCT review_id) AS reviews_count
FROM reviews
GROUP BY order_id;


-- Итоговая таблица: одна строка на один заказ

CREATE OR REPLACE TABLE orders_enriched_sql AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    i.product_revenue,
    i.freight_value,
    i.items_count,
    i.products_count,
    i.sellers_count,

    p.payment_value,
    p.payment_records,
    p.installments_max,
    p.payment_types_count,

    r.review_score,
    r.reviews_count,

    DATE_TRUNC(
        'month',
        o.order_purchase_timestamp
    ) AS purchase_month,

    DATE_DIFF(
        'second',
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
    ) / 86400.0 AS delivery_days,

    DATE_DIFF(
        'second',
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date
    ) / 86400.0 AS delay_days,

    CASE
        WHEN o.order_delivered_customer_date IS NULL
            OR o.order_estimated_delivery_date IS NULL
        THEN NULL

        WHEN o.order_delivered_customer_date
             > o.order_estimated_delivery_date
        THEN TRUE

        ELSE FALSE
    END AS is_late,

    CASE
        WHEN o.order_status = 'canceled'
        THEN TRUE
        ELSE FALSE
    END AS is_canceled

FROM orders AS o

LEFT JOIN customers AS c
    ON o.customer_id = c.customer_id

LEFT JOIN items_by_order AS i
    ON o.order_id = i.order_id

LEFT JOIN payments_by_order AS p
    ON o.order_id = p.order_id

LEFT JOIN reviews_by_order AS r
    ON o.order_id = r.order_id;


-- Проверка уровня детализации


CREATE OR REPLACE TABLE sql_data_quality_check AS
SELECT
    COUNT(*) AS rows_count,
    COUNT(DISTINCT order_id) AS unique_orders
FROM orders_enriched_sql;