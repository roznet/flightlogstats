#!/usr/bin/env python3
# convert the csv file into json for easier import
import csv
import json
from pprint import pprint
csvFilePath = 'logFileFields.csv'
jsonFilePath = 'logFileFields.json'

with open(csvFilePath, encoding='utf-8-sig') as csvf:
        csvReader = csv.DictReader(csvf)
        updated = []
        for row in csvReader:
            if row['order']:
                row['order'] = int(row['order'])
                updated.append(row)
        
        with open(jsonFilePath, 'w', encoding='utf-8') as jsonf:
            jsonf.write(json.dumps(updated, indent=2))
            

