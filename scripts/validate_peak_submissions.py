"""Validate weekly target dates and optional seasonal forecasts."""
import csv
import datetime as dt
import math
import sys
from collections import defaultdict
from pathlib import Path

WEEK = 'peak week inc flu hosp'
INC = 'peak inc flu hosp'
QUANTILES = {0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975}
LOCATIONS = {'Ontario', 'North East', 'West', 'East', 'Central', 'North West', 'Toronto'}
START = dt.date(2026, 10, 17)
END = dt.date(2027, 5, 29)
WEEKS = {(START + dt.timedelta(weeks=i)).isoformat() for i in range((END - START).days // 7 + 1)}
WEEKLY_TARGETS = {f'wk inc {disease} hosp' for disease in ('covid', 'flu', 'rsv')}

def validate(path):
    groups = defaultdict(list)
    with open(path, newline='', encoding='utf-8-sig') as f:
        for line, row in enumerate(csv.DictReader(f), start=2):
            if row.get('target') in WEEKLY_TARGETS:
                try:
                    reference = dt.date.fromisoformat(row.get('reference_date', ''))
                    target_date = dt.date.fromisoformat(row.get('target_end_date', ''))
                    horizon = float(row.get('horizon', ''))
                except (ValueError, TypeError):
                    raise ValueError(f'line {line}: invalid weekly date or horizon')
                if horizon not in (-1, 0, 1, 2, 3):
                    raise ValueError(f'line {line}: invalid weekly horizon')
                if target_date != reference + dt.timedelta(weeks=int(horizon)):
                    raise ValueError(f'line {line}: weekly target_end_date must equal reference_date + 7 days × horizon')
            if row.get('target') in (WEEK, INC):
                groups[(row.get('reference_date'), row.get('location'), row['target'])].append(row)
    for (reference, location, target), rows in groups.items():
        try:
            date = dt.date.fromisoformat(reference)
        except (ValueError, TypeError):
            raise ValueError('invalid reference date')
        if date < dt.date(2026, 10, 24) or date > END or date.weekday() != 5 or location not in LOCATIONS:
            raise ValueError('invalid seasonal reference date or location')
        if any(r.get('horizon', '').strip() or r.get('target_end_date', '').strip() for r in rows):
            raise ValueError('seasonal horizon and target_end_date must be blank')
        ids = [r.get('output_type_id', '').strip() for r in rows]
        try:
            values = [float(r.get('value', '')) for r in rows]
        except ValueError:
            raise ValueError('seasonal values must be numeric')
        if not all(math.isfinite(v) and v >= 0 for v in values):
            raise ValueError('seasonal values must be finite and nonnegative')
        if target == WEEK:
            if any(r.get('output_type') != 'pmf' for r in rows) or len(ids) != len(WEEKS) or set(ids) != WEEKS:
                raise ValueError('peak week requires exactly one pmf for every season week')
            if any(v > 1 for v in values) or not math.isclose(sum(values), 1, rel_tol=0, abs_tol=1e-6):
                raise ValueError('peak week probabilities must be in [0,1] and sum to 1')
        else:
            try:
                levels = [float(i) for i in ids]
            except ValueError:
                raise ValueError('peak incidence quantile levels must be numeric')
            if any(r.get('output_type') != 'quantile' for r in rows) or len(levels) != len(QUANTILES) or set(levels) != QUANTILES:
                raise ValueError('peak incidence requires exactly the seven quantiles')
            if any(not v.is_integer() for v in values) or any(a[1] > b[1] for a, b in zip(sorted(zip(levels, values)), sorted(zip(levels, values))[1:])):
                raise ValueError('peak incidence quantiles must be nonnegative integers in increasing order')

if __name__ == '__main__':
    errors = []
    for item in sys.argv[1:]:
        p = Path(item)
        if p.is_file() and p.suffix == '.csv' and p.parts[0] == 'model-output':
            try:
                validate(p)
            except (ValueError, KeyError) as e:
                errors.append(f'{p}: {e}')
    if errors:
        sys.exit('\n'.join(errors))
