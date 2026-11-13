# Hub configuration files

This folder contains configuration files for the Hub, following the recommended [Hub configuration files in Hubverse's documentation.](https://hubverse.io/en/latest/user-guide/hub-config.html)

For the 2026-2027 season, PHO dashboard data are updated on Fridays from
October 23, 2026 through May 28, 2027. The corresponding Saturday forecast
reference dates run from October 24, 2026 through May 29, 2027.
`tasks.json` lists the allowed reference and target end dates for each target.
Its `submissions_due` window opens Friday and ends Saturday; the separate
submission validation workflow enforces the Saturday 11:30 p.m.
America/Toronto cutoff because the Hubverse schema only supports whole dates.
`admin.json` supplies the `America/Toronto` time zone.
