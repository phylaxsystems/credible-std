#!/usr/bin/env python3
import csv
import math
from pathlib import Path

source = Path(__file__).with_name("aave-v4-flow-rate-observed-maxima.csv")
with source.open(newline="") as handle:
    for row in csv.DictReader(handle):
        limits = [
            math.ceil(float(row[column]) * 1.20)
            for column in ("in_window_bps", "out_window_bps", "in_peak_rate_bps", "out_peak_rate_bps")
        ]
        print(f"{row['hub']} {row['asset']}: {limits}")
