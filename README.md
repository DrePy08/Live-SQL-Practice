# Live SQL Practice — London Transport + Crypto

## Setup (2 mins)

1. Run `python live_sql_data.py`. It creates **live_data.db** (SQLite) with data pulled from the TfL and CoinGecko APIs at that moment. You don't need an API key.
2. Open it in **DB Browser for SQLite** (free), the **SQLite extension in VS Code**, or DBeaver.
3. **Run the script again every 10–15 mins** (do it 3+ times). Each run adds a new snapshot, and you need several of them for Levels 4–5.

Most questions are about the **latest snapshot**. Filter with:
`WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM snapshots)`

## Tables

| Table | What's in it | Key columns |
|---|---|---|
| `snapshots` | One row per script run | snapshot_id, taken_at (UTC) |
| `line_status` | Status of every Tube, Overground, DLR and Elizabeth line | line_id, line_name, mode, status_severity (10 = Good Service), status_desc, reason |
| `arrivals` | Live train predictions on the Jubilee, Metropolitan, Northern, Central, Victoria and Piccadilly lines | line_name, station_name, naptan_id, platform, destination, time_to_station_sec, vehicle_id |
| `bike_points` | Every Santander Cycles dock | name, lat, lon, nb_bikes, nb_ebikes, nb_empty_docks, nb_docks |
| `crypto_prices` | Top 100 coins in GBP | coin_id, name, symbol, market_cap_rank, price_gbp, market_cap_gbp, volume_24h_gbp, change_1h/24h/7d_pct, ath_gbp |

---

## Level 1: Basics (SELECT, WHERE, ORDER BY, LIMIT)

1. List every **tube** line and its current status, A–Z.
2. Show the top 10 coins by market cap with their name, symbol and GBP price.
3. Which lines are **not** running a Good Service right now? Show the reason.
4. Find all bike docks that have **zero bikes**, biggest docks first.
5. What trains are coming into **Stanmore** right now? Show destination, platform and minutes away (1 decimal place), soonest first.

## Level 2: Aggregation (GROUP BY, HAVING, CASE)

6. Across London right now, how many docks, bikes, e-bikes and empty docks are there in total?
7. For each tube line, count the predictions and the **distinct trains** (vehicle_id). Which line has the most trains running?
8. How many of the top 100 coins are up over 24h, and what % is that?
9. Which stations have **5+ trains due in the next 10 minutes**?
10. Group coins into tiers (Top 10 / 11–50 / 51–100). For each tier, show the count, the average 24h change and the total market cap in £bn.

## Level 3: CTEs, subqueries, joins

11. Label each bike dock 'Nearly full' (≥80%), 'Nearly empty' (≤20%) or 'OK', and show its % full. *(Watch out for integer division and docks where nb_docks = 0.)*
12. For the top 20 coins, how far is each one below its all-time high, as a %? Sort with the furthest below first.
13. Find coins whose turnover (volume ÷ market cap) is **above the average** turnover. *(subquery)*
14. For each tube line, which destination appears most often in the predictions? *(correlated subquery or CTE)*
15. Join `line_status` to `arrivals`: for each tube line, show its status next to the number of trains currently running. *(Hint: some lines in line_status have no arrivals data, so think about which join to use.)*

## Level 4: Window functions

16. For each line, find the single prediction that is furthest away. Use `ROW_NUMBER()`.
17. Show each coin's share of the total top-100 market cap, plus a **running cumulative share**. How many coins make up 90%?
18. Rank coins by 24h gain with `DENSE_RANK()` and split them into quartiles with `NTILE(4)`.

## Level 5: Time series (needs 3+ snapshots)

19. Show Bitcoin's price at each snapshot and its change since the previous snapshot. Use `LAG()`.
20. Which 5 coins moved the most (by absolute %) between your first and latest snapshot? Use `FIRST_VALUE` / `LAST_VALUE`.
21. Which 10 bike docks were **busiest**, i.e. had the most total bikes added or removed across snapshots?
22. For each line, what % of your snapshots showed Good Service? Which line is the least reliable?

## Bonus

23. Plot it: the total number of bikes docked across London at each snapshot, with the time formatted as HH:MM. *(This is a good one to chart in Power BI.)*
24. Which stations are served by **2 or more** of the 6 lines? List the lines with `GROUP_CONCAT`. *(Group by naptan_id, not by name.)*

---

Solutions are in **solutions.sql**. Your answers will be different from anyone else's because the data is live, so check your **logic**, not the numbers.
