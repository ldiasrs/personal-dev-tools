import inquirer from "inquirer";
import {
  startOfQuarter,
  endOfQuarter,
  subQuarters,
  startOfWeek,
  endOfWeek,
  subWeeks,
  subDays,
  format,
  parseISO,
  isValid,
} from "date-fns";

const DATE_FORMAT = "yyyy-MM-dd";

function fmt(date) {
  return format(date, DATE_FORMAT);
}

function quarterLabel(date) {
  const q = Math.ceil((date.getMonth() + 1) / 3);
  return `Q${q} ${date.getFullYear()}`;
}

function lastCompletedWeek() {
  const now = new Date();
  const lastWeekDate = subWeeks(now, 1);
  const start = startOfWeek(lastWeekDate, { weekStartsOn: 1 });
  const end = endOfWeek(lastWeekDate, { weekStartsOn: 1 });
  return { start: fmt(start), end: fmt(end), label: `Last week (${fmt(start)} – ${fmt(end)})` };
}

function currentQuarter() {
  const now = new Date();
  return {
    start: fmt(startOfQuarter(now)),
    end: fmt(endOfQuarter(now)),
    label: `${quarterLabel(now)} (${fmt(startOfQuarter(now))} – ${fmt(endOfQuarter(now))})`,
  };
}

function previousQuarter() {
  const prev = subQuarters(new Date(), 1);
  return {
    start: fmt(startOfQuarter(prev)),
    end: fmt(endOfQuarter(prev)),
    label: `${quarterLabel(prev)} (${fmt(startOfQuarter(prev))} – ${fmt(endOfQuarter(prev))})`,
  };
}

function yesterday() {
  const day = subDays(new Date(), 1);
  const d = fmt(day);
  return { start: d, end: d, label: `Yesterday (${d})` };
}

async function promptCustomRange() {
  const { start } = await inquirer.prompt([
    { type: "input", name: "start", message: "Start date (YYYY-MM-DD):" },
  ]);
  const { end } = await inquirer.prompt([
    { type: "input", name: "end", message: "End date (YYYY-MM-DD):" },
  ]);

  if (!isValid(parseISO(start)) || !isValid(parseISO(end))) {
    throw new Error("Invalid date format. Use YYYY-MM-DD.");
  }
  if (start > end) {
    throw new Error("Start date must be before or equal to end date.");
  }

  return { start, end, label: `Custom range (${start} – ${end})` };
}

export async function promptTimeWindow() {
  const week = lastCompletedWeek();
  const currQ = currentQuarter();
  const prevQ = previousQuarter();
  const day = yesterday();

  const { choice } = await inquirer.prompt([
    {
      type: "list",
      name: "choice",
      message: "Select time window:",
      choices: [
        { name: `Current quarter   ${currQ.label}`, value: "currQ" },
        { name: `Previous quarter  ${prevQ.label}`, value: "prevQ" },
        { name: `Last week         ${week.label}`, value: "week" },
        { name: `Yesterday         ${day.label}`, value: "day" },
        { name: "Custom range", value: "custom" },
      ],
    },
  ]);

  const windows = { currQ, prevQ, week, day };
  if (choice === "custom") return promptCustomRange();
  return windows[choice];
}
