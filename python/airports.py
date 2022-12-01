#!/usr/bin/env python3
# source of data https://ourairports.com/data/
import csv
import sqlite3
import urllib.request
import os

airportsfile = 'airports.csv'
runwaysfile = 'runways.csv'
if not os.path.exists("airports.csv"):
    urllib.request.urlretrieve("https://davidmegginson.github.io/ourairports-data/airports.csv", airportsfile)
    urllib.request.urlretrieve("https://davidmegginson.github.io/ourairports-data/runways.csv", runwaysfile)

sql_create_airports = '''CREATE TABLE airports (
id INT,
ident TEXT PRIMARY KEY,
type TEXT,
name TEXT,
latitude_deg REAL,
longitude_deg REAL,
elevation_ft REAL,
continent TEXT,
iso_country TEXT,
iso_region TEXT,
municipality TEXT,
scheduled_service TEXT,
gps_code TEXT,
iata_code TEXT,
local_code TEXT,
home_link TEXT,
wikipedia_link TEXT,
keywords TEXT
)'''
sql_insert_airports = '''INSERT INTO airports VALUES (
:id,
:ident,
:type,
:name,
:latitude_deg,
:longitude_deg,
:elevation_ft,
:continent,
:iso_country,
:iso_region,
:municipality,
:scheduled_service,
:gps_code,
:iata_code,
:local_code,
:home_link,
:wikipedia_link,
:keywords
)'''


db = sqlite3.connect('airports.db')
cur = db.cursor()

cur.execute( 'DROP TABLE IF EXISTS airports' )
cur.execute( sql_create_airports )
db.commit()

with open(airportsfile, encoding='utf-8-sig') as csvf:
    csvReader = csv.DictReader(csvf)

    for row in csvReader:
        if row['type'] != 'heliport':
            db.execute(sql_insert_airports,row)

db.commit()

sql_create_runways = '''CREATE TABLE runways (
id INT,
airport_ref INT,
airport_ident TEXT,
length_ft REAL,
width_ft REAL,
surface TEXT,
lighted INT,
closed INT,
le_ident TEXT,
le_latitude_deg REAL,
le_longitude_deg REAL,
le_elevation_ft REAL,
le_heading_degT REAL,
le_displaced_threshold_ft REAL,
he_ident TEXT,
he_latitude_deg REAL,
he_longitude_deg REAL,
he_elevation_ft REAL,
he_heading_degT REAL,
he_displaced_threshold_ft REAL
)
'''
sql_insert_runways = '''INSERT INTO runways VALUES (
:id,
:airport_ref,
:airport_ident,
:length_ft,
:width_ft,
:surface,
:lighted,
:closed,
:le_ident,
:le_latitude_deg,
:le_longitude_deg,
:le_elevation_ft,
:le_heading_degT,
:le_displaced_threshold_ft,
:he_ident,
:he_latitude_deg,
:he_longitude_deg,
:he_elevation_ft,
:he_heading_degT,
:he_displaced_threshold_ft
)
'''

cur.execute( 'DROP TABLE IF EXISTS runways' )
cur.execute( sql_create_runways )
cur.execute( 'CREATE INDEX idx_airport_ident ON runways (airport_ident)' )
db.commit()

with open(runwaysfile, encoding='utf-8-sig') as csvf:
    csvReader = csv.DictReader(csvf)

    for row in csvReader:
        db.execute(sql_insert_runways,row)


db.commit()

