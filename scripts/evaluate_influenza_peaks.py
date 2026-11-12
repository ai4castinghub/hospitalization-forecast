"""Report seasonal forecasts and score only against complete 2026-27 truth."""
import csv
import math
from collections import defaultdict
from pathlib import Path
from validate_peak_submissions import WEEKS, WEEK, INC

truth_path = Path('target-data/season_2026_2027/influenza-admissions.csv')
forecast_path = Path('auxiliary-data/concatenated_model_output.csv')
out_path = Path('auxiliary-data/influenza-peak-evaluation.csv')
truth = defaultdict(dict)
if truth_path.exists():
    with truth_path.open(newline='', encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            if r['time'] in WEEKS:
                try:
                    v = float(r['admissions'])
                    if math.isfinite(v) and v >= 0:
                        truth[r['geo_value']][r['time']] = v
                except (ValueError, TypeError):
                    pass
forecasts = defaultdict(list)
with forecast_path.open(newline='', encoding='utf-8-sig') as f:
    for r in csv.DictReader(f):
        if r['target'] in (WEEK, INC):
            forecasts[(r['model'], r['reference_date'], r['location'], r['target'])].append(r)
with out_path.open('w', newline='', encoding='utf-8') as f:
    fields = ['model', 'reference_date', 'location', 'target', 'status', 'observed_peak', 'observed_peak_week', 'score', 'score_type']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for (model, ref, location, target), rows in sorted(forecasts.items()):
        result = dict(model=model, reference_date=ref, location=location, target=target, status='truth incomplete')
        obs = truth[location]
        if set(obs) == WEEKS:
            peak = max(obs.values())
            winners = [day for day, v in obs.items() if v == peak]
            result.update(observed_peak=peak, observed_peak_week=winners[0] if len(winners) == 1 else '', status='scored')
            if target == WEEK:
                if len(winners) != 1:
                    result['status'] = 'peak week tied'
                else:
                    probs = {r['output_type_id']: float(r['value']) for r in rows}
                    cumulative = 0.0
                    score = 0.0
                    for day in sorted(WEEKS):
                        cumulative += probs[day]
                        score += (cumulative - (day >= winners[0])) ** 2
                    result.update(score=score, score_type='ranked probability score')
            else:
                q = {float(r['output_type_id']): float(r['value']) for r in rows}
                total = 0.5 * abs(q[0.5] - peak)
                for alpha in (0.05, 0.2, 0.5):
                    lo, hi = q[alpha / 2], q[1 - alpha / 2]
                    interval = hi - lo + 2 / alpha * max(lo - peak, 0) + 2 / alpha * max(peak - hi, 0)
                    total += alpha / 2 * interval
                result.update(score=total / 3.5, score_type='weighted interval score')
        w.writerow(result)
print('Wrote', out_path)
