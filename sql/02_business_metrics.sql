-- Основные бизнес-показатели

-- Общие KPI

CREATE OR REPLACE TABLE kpi_summary_sql AS
SELECT
    COUNT(DISTINCT order_id) AS delivered_orders,

    COUNT(
        DISTINCT customer_unique_id
    ) AS unique_customers,

    ROUND(
        SUM(product_revenue),
        2
    ) AS product_revenue,

    ROUND(
        AVG(product_revenue),
        2
    ) AS average_order_value,

    ROUND(
        AVG(items_count),
        2
    ) AS average_items_per_order,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN is_late = TRUE THEN 1
                ELSE 0
            END
        ),
        2
    ) AS late_delivery_rate_percent,

    ROUND(
        AVG(review_score),
        3
    ) AS average_review_score,

    ROUND(
        100.0 * (
            SELECT AVG(
                CASE
                    WHEN is_canceled = TRUE THEN 1
                    ELSE 0
                END
            )
            FROM orders_enriched_sql
        ),
        2
    ) AS cancellation_rate_percent

FROM orders_enriched_sql
WHERE order_status = 'delivered';


-- Месячные показатели

CREATE OR REPLACE TABLE monthly_metrics_sql AS
SELECT
    purchase_month,

    COUNT(
        DISTINCT order_id
    ) AS orders_count,

    COUNT(
        DISTINCT customer_unique_id
    ) AS unique_customers,

    ROUND(
        SUM(product_revenue),
        2
    ) AS product_revenue,

    ROUND(
        AVG(product_revenue),
        2
    ) AS average_order_value,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN is_late = TRUE THEN 1
                ELSE 0
            END
        ),
        2
    ) AS late_delivery_rate_percent,

    ROUND(
        AVG(review_score),
        3
    ) AS average_review_score

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND purchase_month >= DATE '2017-01-01'
  AND purchase_month <= DATE '2018-08-01'

GROUP BY purchase_month
ORDER BY purchase_month;


-- Оценки по продолжительности доставки

CREATE OR REPLACE TABLE delivery_group_summary_sql AS

WITH delivery_groups AS (
    SELECT
        order_id,
        review_score,
        delivery_days,

        CASE
            WHEN delivery_days <= 7 THEN '0-7'
            WHEN delivery_days <= 14 THEN '8-14'
            WHEN delivery_days <= 21 THEN '15-21'
            WHEN delivery_days <= 30 THEN '22-30'
            ELSE '31+'
        END AS delivery_group,

        CASE
            WHEN delivery_days <= 7 THEN 1
            WHEN delivery_days <= 14 THEN 2
            WHEN delivery_days <= 21 THEN 3
            WHEN delivery_days <= 30 THEN 4
            ELSE 5
        END AS group_order,

        CASE
            WHEN review_score <= 2 THEN 1
            ELSE 0
        END AS low_review

    FROM orders_enriched_sql

    WHERE order_status = 'delivered'
      AND delivery_days IS NOT NULL
      AND review_score IS NOT NULL
)

SELECT
    delivery_group,
    group_order,

    COUNT(
        DISTINCT order_id
    ) AS orders_count,

    ROUND(
        AVG(review_score),
        3
    ) AS average_review,

    ROUND(
        100.0 * AVG(low_review),
        2
    ) AS low_review_rate_percent

FROM delivery_groups

GROUP BY
    delivery_group,
    group_order

ORDER BY group_order;


-- Сравнение своевременных и задержанных заказов

CREATE OR REPLACE TABLE delivery_status_summary_sql AS
SELECT
    is_late,

    COUNT(
        DISTINCT order_id
    ) AS orders_count,

    ROUND(
        AVG(review_score),
        3
    ) AS average_review,

    MEDIAN(
        review_score
    ) AS median_review,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ),
        2
    ) AS low_review_rate_percent,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND is_late IS NOT NULL
  AND review_score IS NOT NULL

GROUP BY is_late
ORDER BY is_late;


-- Показатели доставки по штатам

CREATE OR REPLACE TABLE state_delivery_summary_sql AS
SELECT
    customer_state,

    COUNT(
        DISTINCT order_id
    ) AS orders_count,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN is_late = TRUE THEN 1
                ELSE 0
            END
        ),
        2
    ) AS late_delivery_rate_percent,

    ROUND(
        AVG(review_score),
        3
    ) AS average_review

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND customer_state IS NOT NULL

GROUP BY customer_state

HAVING COUNT(
    DISTINCT order_id
) >= 100

ORDER BY late_delivery_rate_percent DESC;


-- Проверка стоимости товаров, доставки и платежей

CREATE OR REPLACE TABLE financial_check_sql AS
SELECT
    order_id,
    product_revenue,
    freight_value,
    payment_value,

    ROUND(
        product_revenue + freight_value,
        2
    ) AS calculated_total,

    ROUND(
        payment_value
        - product_revenue
        - freight_value,
        2
    ) AS payment_difference

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND product_revenue IS NOT NULL
  AND freight_value IS NOT NULL
  AND payment_value IS NOT NULL;


CREATE OR REPLACE TABLE financial_mismatches_sql AS
SELECT *
FROM financial_check_sql
WHERE ABS(payment_difference) > 0.01;


-- Экспорт для дашборда

COPY kpi_summary_sql
TO 'data/processed/kpi_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY monthly_metrics_sql
TO 'data/processed/monthly_metrics_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY delivery_group_summary_sql
TO 'data/processed/delivery_group_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY delivery_status_summary_sql
TO 'data/processed/delivery_status_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY state_delivery_summary_sql
TO 'data/processed/state_delivery_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);