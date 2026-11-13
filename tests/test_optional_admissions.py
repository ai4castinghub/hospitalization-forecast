import csv
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RSCRIPT = os.environ.get('RSCRIPT') or shutil.which('Rscript')
if not RSCRIPT and os.name == 'nt':
    candidate = Path('C:/Program Files/R/R-4.6.1/bin/Rscript.exe')
    RSCRIPT = str(candidate) if candidate.exists() else None


@unittest.skipUnless(RSCRIPT, 'Rscript is required')
class OptionalAdmissionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'auxiliary-data').mkdir()
        shutil.copy(ROOT / 'auxiliary-data/phu_region_mapping.csv', self.root / 'auxiliary-data')
        with (self.root / 'auxiliary-data/phu_region_mapping.csv').open(encoding='utf-8-sig', newline='') as f:
            phus = [r['NAME_ENG'] for r in csv.DictReader(f) if r['NAME_ENG'] not in ('', 'NA')]
        self.rows = []
        for date in ('2026-10-17 00:00:00', '2026-10-24 00:00:00'):
            for phu in phus:
                for outcome in ('COVID-19 hospital bed occupancy (total)',
                                'Influenza hospital bed occupancy (total)',
                                'RSV hospital bed occupancy (total)',
                                'Influenza hospital admissions'):
                    self.rows.append({'Public health unit': phu, 'Outcome': outcome,
                                      'Respiratory season': '2026-27', 'Surveillance week': '42',
                                      'Week end date': date, 'Number': '1'})
        self.raw = self.root / 'auxiliary-data/pho-outcomes.csv'
        self.target = self.root / 'target-data/season_2026_2027'

    def tearDown(self):
        self.tmp.cleanup()

    def process(self):
        with self.raw.open('w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=self.rows[0].keys())
            writer.writeheader()
            writer.writerows(self.rows)
        result = subprocess.run([RSCRIPT, str(ROOT / 'scripts/get_target_data.R')], cwd=self.root,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with (self.target / 'influenza-admissions-status.csv').open(newline='', encoding='utf-8-sig') as f:
            return next(csv.DictReader(f)), result

    def test_missing_admissions_preserve_occupancy_and_block_stale_peak_data(self):
        status, _ = self.process()
        self.assertEqual(status['status'], 'available')
        admissions = self.target / 'influenza-admissions.csv'
        previous = admissions.read_bytes()
        for row in self.rows:
            if (row['Public health unit'] == 'Toronto Public Health' and
                    row['Outcome'] == 'Influenza hospital admissions'):
                row['Number'] = ''
            if (row['Public health unit'] == 'Ontario' and
                    row['Outcome'] == 'COVID-19 hospital bed occupancy (total)'):
                row['Number'] = '9'
        status, result = self.process()
        self.assertEqual(status['status'], 'unavailable')
        self.assertIn('not updated', result.stderr)
        self.assertEqual(admissions.read_bytes(), previous)
        with (self.target / 'hospitalization-data.csv').open(newline='', encoding='utf-8-sig') as f:
            ontario = [r for r in csv.DictReader(f) if r['geo_value'] == 'Ontario']
        self.assertEqual({r['covid'] for r in ontario}, {'9'})
        code = ("a<-commandArgs(TRUE); source(a[1]); "
                "tryCatch({read_admissions_history(current_file=a[2]); quit(status=2)}, "
                "error=function(e){if(grepl('admissions are unavailable',conditionMessage(e),fixed=TRUE)) "
                "quit(status=0) else {message(e); quit(status=1)}})")
        check = subprocess.run([RSCRIPT, '-e', code, str(ROOT / 'scripts/hub-peak-forecasts.R'),
                                str(admissions)], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
        for row in self.rows:
            if row['Outcome'] == 'Influenza hospital admissions':
                row['Number'] = '2'
        status, _ = self.process()
        self.assertEqual(status['status'], 'available')
        self.assertNotEqual(admissions.read_bytes(), previous)

    def test_absent_admissions_outcome_does_not_block_weekly_targets(self):
        self.rows = [r for r in self.rows if r['Outcome'] != 'Influenza hospital admissions']
        status, _ = self.process()
        self.assertEqual(status['status'], 'unavailable')
        self.assertTrue((self.target / 'hospitalization-data.csv').exists())
        self.assertFalse((self.target / 'influenza-admissions.csv').exists())

    def test_unavailable_status_excludes_only_hub_models_from_peak_ensemble(self):
        status, _ = self.process()
        self.assertEqual(status['status'], 'available')
        metadata = self.root / 'model-metadata'
        metadata.mkdir()
        models = ('AI4Casting_Hub-PeakAR', 'Participant-Model')
        paths = []
        for model in models:
            (metadata / f'{model}.yml').write_text('designated_model: true\n', encoding='utf-8')
            directory = self.root / 'model-output' / model
            directory.mkdir(parents=True)
            path = directory / 'forecast.csv'
            paths.append(path)
            from datetime import date, timedelta
            with path.open('w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(('reference_date', 'location', 'target', 'target_end_date',
                                 'horizon', 'output_type', 'output_type_id', 'value'))
                for week in range(33):
                    day = date(2026, 10, 17) + timedelta(weeks=week)
                    value = int(week == (0 if model == models[0] else 1))
                    writer.writerow(('2026-10-24', 'Ontario', 'peak week inc flu hosp', '', '',
                                     'pmf', day.isoformat(), value))
        status_file = self.target / 'influenza-admissions-status.csv'
        status_file.write_text('status,reason\nunavailable,missing\n', encoding='utf-8')
        code = ("a<-commandArgs(TRUE); source(a[1]); "
                "f<-function() peak_ensemble_rows(a[2:3],as.Date('2026-10-24'),'Ontario',"
                "c(.025,.1,.25,.5,.75,.9,.975),character()); "
                "x<-f(); stopifnot(x$value[x$output_type_id=='2026-10-17']==0, "
                "x$value[x$output_type_id=='2026-10-24']==1); "
                "writeLines(c('status,reason','available,'),a[4]); x<-f(); "
                "stopifnot(x$value[x$output_type_id=='2026-10-17']==0.5, "
                "x$value[x$output_type_id=='2026-10-24']==0.5)")
        check = subprocess.run([RSCRIPT, '-e', code, str(ROOT / 'scripts/peak-ensemble.R'),
                                *(str(path) for path in paths), str(status_file)],
                               cwd=self.root, capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)


if __name__ == '__main__':
    unittest.main()
