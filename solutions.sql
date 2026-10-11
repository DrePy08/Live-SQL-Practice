-- =========================================================
-- SOLUTIONS  (SQLite syntax) — try the questions first!
-- =========================================================

-- ---------- LEVEL 1: Basics ----------

-- Q1
SELECT line_name, status_desc
FROM line_status
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND mode = 'tube'
ORDER BY line_name;

-- Q2
SELECT name, symbol, price_gbp
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
ORDER BY market_cap_rank
LIMIT 10;

-- Q3
SELECT line_name, status_desc, reason
FROM line_status
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND status_severity <> 10;

-- Q4
SELECT name, nb_bikes, nb_docks
FROM bike_points
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND nb_bikes = 0
ORDER BY nb_docks DESC;

-- Q5
SELECT destination, platform, ROUND(time_to_station_sec / 60.0, 1) AS mins_away
FROM arrivals
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND station_name LIKE 'Stanmore%'
ORDER BY time_to_station_sec;

-- ---------- LEVEL 2: Aggregation ----------

-- Q6
SELECT COUNT(*)            AS stations,
       SUM(nb_bikes)       AS bikes,
       SUM(nb_ebikes)      AS ebikes,
       SUM(nb_empty_docks) AS empty_docks
FROM bike_points
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots);

-- Q7
SELECT line_name, COUNT(*) AS predictions, COUNT(DISTINCT vehicle_id) AS trains
FROM arrivals
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
GROUP BY line_name
ORDER BY trains DESC;

-- Q8
SELECT COUNT(*) AS coins_up,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM crypto_prices
                                 WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)), 1) AS pct_up
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND change_24h_pct > 0;

-- Q9
SELECT station_name, COUNT(*) AS trains_due
FROM arrivals
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND time_to_station_sec <= 600
GROUP BY station_name
HAVING COUNT(*) >= 5
ORDER BY trains_due DESC;

-- Q10
SELECT CASE
         WHEN market_cap_rank <= 10 THEN '1. Top 10'
         WHEN market_cap_rank <= 50 THEN '2. 11-50'
         ELSE '3. 51-100'
       END AS tier,
       COUNT(*) AS coins,
       ROUND(AVG(change_24h_pct), 2) AS avg_24h_change,
       ROUND(SUM(market_cap_gbp) / 1e9, 1) AS total_mcap_bn
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
GROUP BY tier
ORDER BY tier;

-- ---------- LEVEL 3: CTEs, subqueries, CASE ----------

-- Q11
WITH latest AS (
  SELECT * FROM bike_points WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
)
SELECT name, nb_bikes, nb_docks,
       ROUND(100.0 * nb_bikes / nb_docks, 1) AS pct_full,
       CASE WHEN 1.0 * nb_bikes / nb_docks >= 0.8 THEN 'Nearly full'
            WHEN 1.0 * nb_bikes / nb_docks <= 0.2 THEN 'Nearly empty'
            ELSE 'OK' END AS status
FROM latest
WHERE nb_docks > 0;

-- Q12
SELECT name, symbol, price_gbp, ath_gbp,
       ROUND(100.0 * (price_gbp - ath_gbp) / ath_gbp, 1) AS pct_below_ath
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND market_cap_rank <= 20
ORDER BY pct_below_ath ASC;

-- Q13
SELECT name, volume_24h_gbp, market_cap_gbp,
       ROUND(volume_24h_gbp / market_cap_gbp, 3) AS turnover
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND volume_24h_gbp / market_cap_gbp >
      (SELECT AVG(volume_24h_gbp / market_cap_gbp) FROM crypto_prices
       WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots) AND market_cap_gbp > 0)
ORDER BY turnover DESC;

-- Q14
WITH latest AS (
  SELECT * FROM arrivals WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
)
SELECT line_name, destination, COUNT(*) AS predictions
FROM latest
GROUP BY line_name, destination
HAVING COUNT(*) = (SELECT MAX(c) FROM (SELECT COUNT(*) AS c FROM latest l2
                                       WHERE l2.line_name = latest.line_name
                                       GROUP BY l2.destination));

-- Q15
SELECT ls.line_name, ls.status_desc, COUNT(DISTINCT a.vehicle_id) AS trains_running
FROM line_status ls
LEFT JOIN arrivals a
       ON a.line_id = ls.line_id AND a.snapshot_id = ls.snapshot_id
WHERE ls.snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND ls.mode = 'tube'
GROUP BY ls.line_name, ls.status_desc
ORDER BY trains_running DESC;

-- ---------- LEVEL 4: Window functions ----------

-- Q16
SELECT line_name, station_name, destination, time_to_station_sec
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY line_name ORDER BY time_to_station_sec DESC) AS rn
  FROM arrivals
  WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
)
WHERE rn = 1;

-- Q17
SELECT name, market_cap_gbp,
       ROUND(100.0 * market_cap_gbp / SUM(market_cap_gbp) OVER (), 2) AS share_pct,
       ROUND(100.0 * SUM(market_cap_gbp) OVER (ORDER BY market_cap_rank)
                   / SUM(market_cap_gbp) OVER (), 2)               AS running_share_pct
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
ORDER BY market_cap_rank;

-- Q18
SELECT name, change_24h_pct,
       DENSE_RANK() OVER (ORDER BY change_24h_pct DESC) AS gain_rank,
       NTILE(4)     OVER (ORDER BY change_24h_pct DESC) AS quartile
FROM crypto_prices
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
  AND change_24h_pct IS NOT NULL;

-- ---------- LEVEL 5: Time series across snapshots ----------

-- Q19
SELECT s.taken_at, c.price_gbp,
       c.price_gbp - LAG(c.price_gbp) OVER (ORDER BY s.snapshot_id) AS change_since_prev
FROM crypto_prices c
JOIN snapshots s ON s.snapshot_id = c.snapshot_id
WHERE c.coin_id = 'bitcoin'
ORDER BY s.snapshot_id;

-- Q20
WITH first_last AS (
  SELECT coin_id, name,
         FIRST_VALUE(price_gbp) OVER w AS first_price,
         LAST_VALUE(price_gbp)  OVER w AS last_price
  FROM crypto_prices
  WINDOW w AS (PARTITION BY coin_id ORDER BY snapshot_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT DISTINCT name,
       ROUND(100.0 * (last_price - first_price) / first_price, 3) AS pct_change
FROM first_last
WHERE first_price > 0
ORDER BY ABS(pct_change) DESC
LIMIT 5;

-- Q21
WITH changes AS (
  SELECT bikepoint_id, name, snapshot_id, nb_bikes,
         nb_bikes - LAG(nb_bikes) OVER (PARTITION BY bikepoint_id ORDER BY snapshot_id) AS delta
  FROM bike_points
)
SELECT name, SUM(ABS(delta)) AS total_movement
FROM changes
WHERE delta IS NOT NULL
GROUP BY bikepoint_id, name
ORDER BY total_movement DESC
LIMIT 10;

-- Q22
SELECT line_name,
       COUNT(*) AS snapshots_seen,
       SUM(CASE WHEN status_severity = 10 THEN 1 ELSE 0 END) AS good_service,
       ROUND(100.0 * SUM(CASE WHEN status_severity = 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_good
FROM line_status
GROUP BY line_name
ORDER BY pct_good ASC, line_name;

-- ---------- BONUS ----------

-- Q23 (5-min buckets over all snapshots, using SQLite date functions)
SELECT s.taken_at,
       strftime('%H:%M', s.taken_at) AS time_utc,
       SUM(b.nb_bikes) AS bikes_docked
FROM bike_points b
JOIN snapshots s ON s.snapshot_id = b.snapshot_id
GROUP BY s.snapshot_id
ORDER BY s.snapshot_id;

-- Q24 (stations served by 2+ of the 6 lines right now)
SELECT naptan_id, MIN(station_name) AS station,
       COUNT(DISTINCT line_id) AS lines,
       GROUP_CONCAT(DISTINCT line_name) AS line_list
FROM arrivals
WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)
GROUP BY naptan_id
HAVING COUNT(DISTINCT line_id) >= 2
ORDER BY lines DESC, station;
