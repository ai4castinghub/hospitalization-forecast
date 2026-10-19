#!/usr/bin/env node

import { createRequire } from "node:module";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright-core");

const REPORT_URL =
  "https://ws-rpt1.publichealthontario.ca/Home/EmbedReport/8a8e0f42-4f8e-430f-a382-3ad221e717cb";
const inspectOnly = process.argv.includes("--inspect");
const outputArgument = process.argv.find((argument) =>
  argument.startsWith("--output="),
);
const outputPath = path.resolve(
  outputArgument?.slice("--output=".length) ??
    "auxiliary-data/pho-outcomes.csv",
);

const browser = await chromium.launch({
  channel: process.env.PLAYWRIGHT_BROWSER_CHANNEL ?? "chrome",
  headless: true,
});

try {
  const page = await browser.newPage({ locale: "en-CA" });
  page.setDefaultTimeout(60_000);

  await page.goto(REPORT_URL, { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => {
    const container = document.getElementById("embedContainer");
    return Boolean(container && window.powerbi?.get(container));
  });

  const reportState = await page.evaluate(async () => {
    const container = document.getElementById("embedContainer");
    const report = window.powerbi.get(container);

    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(
        () => reject(new Error("Timed out waiting for the Power BI report")),
        45_000,
      );

      const finish = (state) => {
        window.clearTimeout(timeout);
        resolve(state);
      };

      report.on("loaded", () => finish("loaded"));
      report.on("error", (event) => {
        window.clearTimeout(timeout);
        reject(new Error(event?.detail?.message ?? "Power BI report error"));
      });

      report
        .getPages()
        .then((pages) => {
          if (pages.length > 0) finish("already loaded");
        })
        .catch(() => {
          // The loaded event will resolve the promise once the report is ready.
        });
    });
  });

  if (inspectOnly) {
    const outcomePages = await page.evaluate(async () => {
      const container = document.getElementById("embedContainer");
      const report = window.powerbi.get(container);
      const pages = await report.getPages();
      const result = [];

      for (const reportPage of pages.filter(
        (candidate) =>
          candidate.displayName.toLowerCase() === "outcomes (data tables)",
      )) {
        const rendered = new Promise((resolve) => {
          const timeout = window.setTimeout(resolve, 15_000);
          const handler = () => {
            window.clearTimeout(timeout);
            report.off("rendered", handler);
            resolve();
          };
          report.on("rendered", handler);
        });
        await reportPage.setActive();
        await rendered;
        const visuals = await reportPage.getVisuals();
        const visualInventory = [];
        for (const visual of visuals) {
          let slicerState;
          if (visual.type === "slicer") {
            try {
              slicerState = await visual.getSlicerState();
            } catch (error) {
              slicerState = { error: error?.message ?? String(error) };
            }
          }
          visualInventory.push({
            name: visual.name,
            title: visual.title,
            type: visual.type,
            slicerState,
          });
        }
        result.push({
          name: reportPage.name,
          displayName: reportPage.displayName,
          isActive: reportPage.isActive,
          visibility: reportPage.visibility,
          visuals: visualInventory,
        });
      }

      return result;
    });

    console.error(
      `Power BI report ${reportState}; found ${outcomePages.length} Outcomes data-table pages.`,
    );
    process.stdout.write(`${JSON.stringify(outcomePages, null, 2)}\n`);
  } else {
    const exported = await page.evaluate(async () => {
      const container = document.getElementById("embedContainer");
      const report = window.powerbi.get(container);
      const models = window["powerbi-client"].models;
      const pages = await report.getPages();
      const dataPages = pages.filter(
        (candidate) =>
          candidate.displayName.toLowerCase() === "outcomes (data tables)",
      );

      if (dataPages.length !== 1) {
        throw new Error(
          `Expected one Outcomes data-table page, found ${dataPages.length}`,
        );
      }

      const dataPage = dataPages[0];
      const rendered = new Promise((resolve) => {
        const timeout = window.setTimeout(resolve, 15_000);
        const handler = () => {
          window.clearTimeout(timeout);
          report.off("rendered", handler);
          resolve();
        };
        report.on("rendered", handler);
      });
      await dataPage.setActive();
      await rendered;

      const visuals = await dataPage.getVisuals();
      const slicerByTitle = (title) => {
        const matches = visuals.filter(
          (visual) =>
            visual.type === "slicer" &&
            visual.title.toLowerCase() === title.toLowerCase(),
        );
        if (matches.length !== 1) {
          throw new Error(`Expected one ${title} slicer, found ${matches.length}`);
        }
        return matches[0];
      };
      const waitForRenderAfter = async (operation) => {
        const rendered = new Promise((resolve) => {
          const timeout = window.setTimeout(resolve, 15_000);
          const handler = () => {
            window.clearTimeout(timeout);
            report.off("rendered", handler);
            resolve();
          };
          report.on("rendered", handler);
        });
        await operation();
        await rendered;
      };

      const seasonSlicer = slicerByTitle("Respiratory season");
      const phuSlicer = slicerByTitle("Public health unit");
      const diseaseSlicer = slicerByTitle("Disease and outcome");
      const seasonState = await seasonSlicer.getSlicerState();
      const seasonFilter = seasonState.filters[0];
      const currentSeason = [...seasonFilter.values].sort().at(-1);
      const diseaseState = await diseaseSlicer.getSlicerState();
      const diseaseFilter = diseaseState.filters[0];

      await waitForRenderAfter(() =>
        seasonSlicer.setSlicerState({
          filters: [{ ...seasonFilter, values: [currentSeason] }],
        }),
      );
      await waitForRenderAfter(() =>
        phuSlicer.setSlicerState({ filters: [] }),
      );
      await waitForRenderAfter(() =>
        diseaseSlicer.setSlicerState({
          filters: [
            {
              ...diseaseFilter,
              values: ["COVID-19", "Influenza", "RSV"],
            },
          ],
        }),
      );

      const tables = visuals.filter(
        (visual) =>
          visual.type === "tableEx" &&
          visual.title.toLowerCase() === "table simple",
      );
      if (tables.length !== 1) {
        throw new Error(
          `Expected one simple table on the Outcomes data-table page, found ${tables.length}`,
        );
      }

      const table = tables[0];
      const result = await table.exportData(
        models.ExportDataType.Summarized,
        30_000,
      );

      return {
        csv: result.data,
        page: dataPage.displayName,
        visualName: table.name,
        visualTitle: table.title,
        respiratorySeason: currentSeason,
      };
    });

    const requiredText = [
      "Public health unit",
      "COVID-19 hospital bed occupancy (total)",
      "Influenza hospital bed occupancy (total)",
      "RSV hospital bed occupancy (total)",
    ];
    const missingText = requiredText.filter(
      (expected) => !exported.csv.includes(expected),
    );
    if (missingText.length > 0) {
      throw new Error(`Export is missing expected data: ${missingText.join(", ")}`);
    }

    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, exported.csv, "utf8");
    console.error(
      `Exported ${exported.respiratorySeason} ${exported.page} / ${exported.visualTitle} (${exported.visualName}) to ${outputPath}.`,
    );
  }
} finally {
  await browser.close();
}
