import csv
import datetime as dt
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('submission_validation', ROOT / 'scripts/validate_peak_submissions.py')
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)
FIELDS = ['reference_date', 'target', 'horizon', 'target_end_date', 'location', 'output_type', 'output_type_id', 'value']


def row(target, horizon, target_date, output_type='quantile', output_type_id='0.5', value='100'):
    return dict(reference_date='2026-11-14', target=target, horizon=horizon,
                target_end_date=target_date, location='Ontario', output_type=output_type,
                output_type_id=output_type_id, value=value)


class SubmissionValidationTest(unittest.TestCase):
    def check_rows(self, rows, valid=True):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'forecast.csv'
            with path.open('w', encoding='utf-8', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerows(rows)
            if valid:
                validation.validate(path)
            else:
                with self.assertRaises(ValueError):
                    validation.validate(path)

    def test_all_weekly_targets_and_horizons(self):
        ref = dt.date(2026, 11, 14)
        for disease in ('covid', 'flu', 'rsv'):
            for horizon in (-1, 0, 1, 2, 3):
                with self.subTest(disease=disease, horizon=horizon):
                    self.check_rows([row(f'wk inc {disease} hosp', str(horizon),
                                         str(ref + dt.timedelta(weeks=horizon)))])

    def test_invalid_date_for_weekly_horizon_is_rejected(self):
        for disease in ('covid', 'flu', 'rsv'):
            with self.subTest(disease=disease):
                self.check_rows([row(f'wk inc {disease} hosp', '1', '2026-12-05')], False)

    def test_invalid_or_missing_weekly_dates_and_horizons_are_rejected(self):
        for horizon, date in [('', '2026-11-14'), ('nan', '2026-11-14'),
                              ('4', '2026-12-12'), ('0', ''), ('0', 'not-a-date')]:
            with self.subTest(horizon=horizon, date=date):
                self.check_rows([row('wk inc flu hosp', horizon, date)], False)

    def test_seasonal_and_mixed_submissions(self):
        weeks = sorted(validation.WEEKS)
        pmf = [row(validation.WEEK, '', '', 'pmf', date, '1' if i == 0 else '0')
               for i, date in enumerate(weeks)]
        self.check_rows(pmf)
        self.check_rows(pmf + [row('wk inc flu hosp', '1', '2026-11-21')])
        self.check_rows(pmf[:-1], False)
        self.check_rows([row(validation.WEEK, '0', '', 'pmf', weeks[0], '1')] + pmf[1:], False)


if __name__ == '__main__':
    unittest.main()
