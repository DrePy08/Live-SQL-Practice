"""
Live SQL practice data loader
-----------------------------
Pulls LIVE data from free public APIs (no API key needed) into a SQLite database:
  - TfL tube/rail line status        (api.tfl.gov.uk)
  - TfL live train arrival predictions for 6 tube lines
  - TfL Santander Cycles docking stations (bikes available right now)
  - Top 100 cryptocurrencies priced in GBP (api.coingecko.com)

Every run adds a new "snapshot", so run it a few times (e.g. every 10-15 mins)
to build up time-series data for the harder questions.

Usage:
    python live_sql_data.py              # creates/updates live_data.db
    python live_sql_data.py my.db        # custom db name

Only uses the Python standard library.
"""

import json
import sqlite3
import sys
import time
import urllib.request
from datetime import datetime, timezone

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "live_data.db"
TUBE_LINES = ["jubilee", "metropolitan", "northern", "central", "victoria", "piccadilly"]
HEADERS = {"User-Agent": "sql-practice-loader/1.0", "Accept": "application/json"}

SCHEMA = """
CREATE TABLE IF NOT EXISTS snapshots (
    snapshot_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    taken_at      TEXT NOT NULL              -- UTC, ISO 8601
);

CREATE TABLE IF NOT EXISTS line_status (
    snapshot_id      INTEGER REFERENCES snapshots(snapshot_id),
    line_id          TEXT,
    line_name        TEXT,
    mode             TEXT,                   -- tube, overground, dlr, elizabeth-line
    status_severity  INTEGER,                -- 10 = Good Service, lower = worse
    status_desc      TEXT,
    reason           TEXT
);

CREATE TABLE IF NOT EXISTS arrivals (
    snapshot_id          INTEGER REFERENCES snapshots(snapshot_id),
    prediction_id        TEXT,
    line_id              TEXT,
    line_name            TEXT,
    station_name         TEXT,
    naptan_id            TEXT,
    platform             TEXT,
    direction            TEXT,
    destination          TEXT,
    time_to_station_sec  INTEGER,
    expected_arrival     TEXT,
    vehicle_id           TEXT,
    current_location     TEXT
);

CREATE TABLE IF NOT EXISTS bike_points (
    snapshot_id     INTEGER REFERENCES snapshots(snapshot_id),
    bikepoint_id    TEXT,
    name            TEXT,
    lat             REAL,
    lon             REAL,
    nb_bikes        INTEGER,
    nb_standard     INTEGER,
    nb_ebikes       INTEGER,
    nb_empty_docks  INTEGER,
    nb_docks        INTEGER
);

CREATE TABLE IF NOT EXISTS crypto_prices (
    snapshot_id         INTEGER REFERENCES snapshots(snapshot_id),
    coin_id             TEXT,
    symbol              TEXT,
    name                TEXT,
    market_cap_rank     INTEGER,
    price_gbp           REAL,
    market_cap_gbp      REAL,
    volume_24h_gbp      REAL,
    high_24h_gbp        REAL,
    low_24h_gbp         REAL,
    change_1h_pct       REAL,
    change_24h_pct      REAL,
    change_7d_pct       REAL,
    circulating_supply  REAL,
    max_supply          REAL,
    ath_gbp             REAL,
    last_updated        TEXT
);
"""


def get_json(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def load_line_status(cur, sid):
    data = get_json("https://api.tfl.gov.uk/Line/Mode/tube,overground,dlr,elizabeth-line/Status")
    rows = []
    for line in data:
        for s in line.get("lineStatuses", []) or [{}]:
            rows.append((sid, line.get("id"), line.get("name"), line.get("modeName"),
                         s.get("statusSeverity"), s.get("statusSeverityDescription"), s.get("reason")))
    cur.executemany("INSERT INTO line_status VALUES (?,?,?,?,?,?,?)", rows)
    return len(rows)


def load_arrivals(cur, sid):
    total = 0
    for line_id in TUBE_LINES:
        data = get_json(f"https://api.tfl.gov.uk/Line/{line_id}/Arrivals")
        rows = [(sid, a.get("id"), a.get("lineId"), a.get("lineName"), a.get("stationName"),
                 a.get("naptanId"), a.get("platformName"), a.get("direction"),
                 a.get("destinationName"), a.get("timeToStation"), a.get("expectedArrival"),
                 a.get("vehicleId"), a.get("currentLocation")) for a in data]
        cur.executemany("INSERT INTO arrivals VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        total += len(rows)
        time.sleep(0.5)  # be polite to the API
    return total


def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def load_bike_points(cur, sid):
    data = get_json("https://api.tfl.gov.uk/BikePoint")
    rows = []
    for b in data:
        props = {p.get("key"): p.get("value") for p in b.get("additionalProperties", [])}
        rows.append((sid, b.get("id"), b.get("commonName"), b.get("lat"), b.get("lon"),
                     _int(props.get("NbBikes")), _int(props.get("NbStandardBikes")),
                     _int(props.get("NbEBikes")), _int(props.get("NbEmptyDocks")),
                     _int(props.get("NbDocks"))))
    cur.executemany("INSERT INTO bike_points VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    return len(rows)


def load_crypto(cur, sid):
    url = ("https://api.coingecko.com/api/v3/coins/markets?vs_currency=gbp&order=market_cap_desc"
           "&per_page=100&page=1&price_change_percentage=1h,24h,7d")
    data = get_json(url)
    rows = [(sid, c.get("id"), c.get("symbol"), c.get("name"), c.get("market_cap_rank"),
             c.get("current_price"), c.get("market_cap"), c.get("total_volume"),
             c.get("high_24h"), c.get("low_24h"),
             c.get("price_change_percentage_1h_in_currency"),
             c.get("price_change_percentage_24h_in_currency", c.get("price_change_percentage_24h")),
             c.get("price_change_percentage_7d_in_currency"),
             c.get("circulating_supply"), c.get("max_supply"), c.get("ath"),
             c.get("last_updated")) for c in data]
    cur.executemany("INSERT INTO crypto_prices VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    return len(rows)


def main():
    con = sqlite3.connect(DB_PATH)
    con.executescript(SCHEMA)
    cur = con.cursor()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    cur.execute("INSERT INTO snapshots (taken_at) VALUES (?)", (now,))
    sid = cur.lastrowid
    print(f"Snapshot {sid} at {now}")

    for label, fn in [("line_status", load_line_status), ("arrivals", load_arrivals),
                      ("bike_points", load_bike_points), ("crypto_prices", load_crypto)]:
        try:
            n = fn(cur, sid)
            print(f"  {label:<14} {n:>5} rows")
        except Exception as e:  # one API failing shouldn't stop the others
            print(f"  {label:<14} FAILED: {e}")

    con.commit()
    con.close()
    print(f"Saved to {DB_PATH}")


if __name__ == "__main__":
    main()
