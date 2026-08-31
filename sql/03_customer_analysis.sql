-- Повторные покупки, retention и RFM-сегментация

-- Количество заказов каждого клиента

CREATE OR REPLACE TABLE customer_frequency_sql AS
SELECT
    customer_unique_id,

    COUNT(
        DISTINCT order_id
    ) AS orders_count,

    ROUND(
        SUM(product_revenue),
        2
    ) AS total_product_value

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND customer_unique_id IS NOT NULL

GROUP BY customer_unique_id;


-- Доля повторных клиентов

CREATE OR REPLACE TABLE repeat_customer_summary_sql AS
SELECT
    COUNT(*) AS customers_count,

    SUM(
        CASE
            WHEN orders_count > 1 THEN 1
            ELSE 0
        END
    ) AS repeat_customers,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN orders_count > 1 THEN 1
                ELSE 0
            END
        ),
        2
    ) AS repeat_customer_rate_percent

FROM customer_frequency_sql;


-- Когортный анализ в длинном формате

CREATE OR REPLACE TABLE cohort_retention_long_sql AS

WITH customer_orders AS (
    SELECT DISTINCT
        customer_unique_id,

        DATE_TRUNC(
            'month',
            order_purchase_timestamp
        ) AS order_month

    FROM orders_enriched_sql

    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
      AND order_purchase_timestamp IS NOT NULL
),

first_purchase AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
),

cohort_activity AS (
    SELECT
        fp.cohort_month,
        co.order_month,

        DATE_DIFF(
            'month',
            fp.cohort_month,
            co.order_month
        ) AS cohort_index,

        COUNT(
            DISTINCT co.customer_unique_id
        ) AS customers_count

    FROM customer_orders AS co

    INNER JOIN first_purchase AS fp
        ON co.customer_unique_id
           = fp.customer_unique_id

    GROUP BY
        fp.cohort_month,
        co.order_month,
        cohort_index
),

cohort_sizes AS (
    SELECT
        cohort_month,
        customers_count AS cohort_size
    FROM cohort_activity
    WHERE cohort_index = 0
)

SELECT
    ca.cohort_month,
    ca.cohort_index,
    ca.customers_count,
    cs.cohort_size,

    ROUND(
        1.0 * ca.customers_count
        / cs.cohort_size,
        5
    ) AS retention_rate

FROM cohort_activity AS ca

INNER JOIN cohort_sizes AS cs
    ON ca.cohort_month = cs.cohort_month

WHERE ca.cohort_month >= DATE '2017-01-01'
  AND ca.cohort_month <= DATE '2018-08-01'

ORDER BY
    ca.cohort_month,
    ca.cohort_index;


-- RFM: реальные показатели клиентов

CREATE OR REPLACE TABLE customer_rfm_sql AS
SELECT
    customer_unique_id,

    DATE_DIFF(
        'day',
        MAX(
            CAST(
                order_purchase_timestamp AS DATE
            )
        ),
        DATE '2018-09-01'
    ) AS recency,

    COUNT(
        DISTINCT order_id
    ) AS frequency,

    ROUND(
        SUM(product_revenue),
        2
    ) AS monetary

FROM orders_enriched_sql

WHERE order_status = 'delivered'
  AND customer_unique_id IS NOT NULL
  AND product_revenue IS NOT NULL
  AND order_purchase_timestamp
      < TIMESTAMP '2018-09-01 00:00:00'

GROUP BY customer_unique_id;


-- RFM-score

CREATE OR REPLACE TABLE customer_rfm_scores_sql AS

WITH scored AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY recency DESC
        ) AS r_score,

        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 2
            WHEN frequency = 3 THEN 3
            ELSE 4
        END AS f_score,

        NTILE(4) OVER (
            ORDER BY monetary ASC
        ) AS m_score

    FROM customer_rfm_sql
)

SELECT
    *,

    CAST(r_score AS VARCHAR)
    || CAST(f_score AS VARCHAR)
    || CAST(m_score AS VARCHAR)
    AS rfm_score

FROM scored;


-- Присвоение RFM-сегментов

CREATE OR REPLACE TABLE customer_segments_sql AS

SELECT
    *,

    CASE
        WHEN r_score >= 3
             AND f_score >= 2
             AND m_score >= 3
        THEN 'Champions'

        WHEN f_score >= 2
             AND r_score >= 2
        THEN 'Loyal customers'

        WHEN r_score = 4
             AND f_score = 1
        THEN 'New customers'

        WHEN f_score = 1
             AND m_score = 4
             AND r_score >= 2
        THEN 'High-value one-time'

        WHEN r_score <= 2
             AND (
                 f_score >= 2
                 OR m_score >= 3
             )
        THEN 'At risk'

        WHEN r_score = 1
             AND f_score = 1
        THEN 'Inactive one-time'

        ELSE 'Regular one-time'
    END AS segment

FROM customer_rfm_scores_sql;


-- Агрегированные показатели сегментов

CREATE OR REPLACE TABLE segment_summary_sql AS

WITH segment_aggregates AS (
    SELECT
        segment,

        COUNT(*) AS customers_count,

        AVG(recency) AS average_recency,
        AVG(frequency) AS average_frequency,
        AVG(monetary) AS average_monetary,
        SUM(monetary) AS total_monetary

    FROM customer_segments_sql

    GROUP BY segment
)

SELECT
    segment,
    customers_count,

    ROUND(
        average_recency,
        2
    ) AS average_recency,

    ROUND(
        average_frequency,
        2
    ) AS average_frequency,

    ROUND(
        average_monetary,
        2
    ) AS average_monetary,

    ROUND(
        total_monetary,
        2
    ) AS total_monetary,

    ROUND(
        100.0 * customers_count
        / SUM(customers_count) OVER (),
        2
    ) AS customers_share_percent

FROM segment_aggregates

ORDER BY customers_count DESC;


-- Экспорт для дашборда

COPY repeat_customer_summary_sql
TO 'data/processed/repeat_customer_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY cohort_retention_long_sql
TO 'data/processed/cohort_retention_long_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY customer_segments_sql
TO 'data/processed/customer_segments_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);

COPY segment_summary_sql
TO 'data/processed/segment_summary_sql.csv'
WITH (
    HEADER,
    DELIMITER ','
);