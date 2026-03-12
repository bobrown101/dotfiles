const isTTY = process.stdout.isTTY && !process.env.NO_COLOR;
const esc = (code) => (isTTY ? `\x1b[${code}m` : "");
const reset = esc(0);
const bold = (s) => `${esc(1)}${s}${reset}`;
const red = (s) => `${esc(31)}${s}${reset}`;
const green = (s) => `${esc(32)}${s}${reset}`;
const yellow = (s) => `${esc(33)}${s}${reset}`;
const blue = (s) => `${esc(34)}${s}${reset}`;
const cyan = (s) => `${esc(36)}${s}${reset}`;
const gray = (s) => `${esc(90)}${s}${reset}`;

const PRIORITY_EMOJI = { 4: "🔴", 3: "🟡", 2: "🟢", 1: "⚪" }; // API values: 4=urgent, 1=none

function priorityIcon(p) {
  return PRIORITY_EMOJI[p] || " ";
}

function formatDue(due) {
  if (!due) return "";
  const today = new Date().toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  if (due === today) return red("today");
  if (due === tomorrow) return yellow("tomorrow");
  if (due < today) return red(due);
  return green(due);
}

function isWide(cp) {
  if (cp >= 0x1100 && cp <= 0x115f) return true;
  if (cp >= 0x2e80 && cp <= 0xa4cf && cp !== 0x303f) return true;
  if (cp >= 0xac00 && cp <= 0xd7a3) return true;
  if (cp >= 0xf900 && cp <= 0xfaff) return true;
  if (cp >= 0xfe10 && cp <= 0xfe6f) return true;
  if (cp >= 0xff01 && cp <= 0xff60) return true;
  if (cp >= 0xffe0 && cp <= 0xffe6) return true;
  if (cp >= 0x1f000 && cp <= 0x1ffff) return true;
  if (cp >= 0x20000 && cp <= 0x2ffff) return true;
  if (cp >= 0x2600 && cp <= 0x27bf) return true;
  if (cp >= 0x2b50 && cp <= 0x2b55) return true;
  return false;
}

function isZeroWidth(cp) {
  if (cp === 0x200b || cp === 0x200c || cp === 0x200d || cp === 0xfeff) return true;
  if (cp >= 0xfe00 && cp <= 0xfe0f) return true;
  if (cp >= 0xe0100 && cp <= 0xe01ef) return true;
  return false;
}

function visLen(str) {
  const plain = str.replace(/\x1b\[[0-9;]*m/g, "");
  let len = 0;
  for (const ch of plain) {
    const cp = ch.codePointAt(0);
    if (isZeroWidth(cp)) continue;
    len += isWide(cp) ? 2 : 1;
  }
  return len;
}

function pad(str, len) {
  const diff = len - visLen(str);
  return diff > 0 ? str + " ".repeat(diff) : str;
}

function truncate(str, max) {
  return str.length > max ? str.slice(0, max - 1) + "\u2026" : str;
}

function table(headers, rows) {
  const cols = headers.length;
  const widths = headers.map((h) => visLen(h));
  for (const row of rows) {
    for (let i = 0; i < cols; i++) {
      widths[i] = Math.max(widths[i], visLen(row[i] || ""));
    }
  }

  const top = "\u250c" + widths.map((w) => "\u2500".repeat(w + 2)).join("\u252c") + "\u2510";
  const mid = "\u251c" + widths.map((w) => "\u2500".repeat(w + 2)).join("\u253c") + "\u2524";
  const bot = "\u2514" + widths.map((w) => "\u2500".repeat(w + 2)).join("\u2534") + "\u2518";
  const line = (cells) =>
    "\u2502" + cells.map((c, i) => " " + pad(c, widths[i]) + " ").join("\u2502") + "\u2502";

  console.log(top);
  console.log(line(headers.map((h) => cyan(h))));
  console.log(mid);
  for (const row of rows) {
    console.log(line(row));
  }
  console.log(bot);
}

function activeRow(task) {
  return [priorityIcon(task.priority), truncate(task.content, 50), formatDue(task.due), gray(task.id)];
}

function completedRow(task) {
  return [priorityIcon(task.priority), gray(truncate(task.content, 50)), task.completedAt ? gray(task.completedAt) : "", gray(task.id)];
}

function printTasks(groupedTasks, completedTasks) {
  const entries = Object.entries(groupedTasks);
  if (entries.length === 0 && (!completedTasks || completedTasks.length === 0)) {
    console.log("No tasks.");
    return;
  }

  for (const [projectName, tasks] of entries) {
    console.log(bold(cyan(projectName)));
    const rows = tasks.map(activeRow);
    table(["", "Task", "Due", "ID"], rows);
    console.log("");
  }

  if (completedTasks && completedTasks.length > 0) {
    console.log(bold(gray("Recently completed")));
    const rows = completedTasks.map(completedRow);
    table(["", "Task", "Completed", "ID"], rows);
    console.log("");
  }
}

function printTasksFlat(tasks) {
  if (tasks.length === 0) {
    console.log("No tasks.");
    return;
  }
  const rows = tasks.map(activeRow);
  table(["", "Task", "Due", "ID"], rows);
}

function printProjects(projects) {
  if (projects.length === 0) {
    console.log("No projects.");
    return;
  }
  const rows = projects.map((p) => {
    const fav = p.isFavorite ? yellow("*") : "";
    return [p.name, fav, gray(p.id)];
  });
  table(["Name", "", "ID"], rows);
}

function printSuccess(msg) {
  console.log(green(msg));
}

function printError(msg) {
  console.error(red(msg));
}

function printHelp() {
  console.log("");
  console.log(bold("todo - Todoist from the terminal"));
  console.log("");
  console.log(bold("Commands:"));
  console.log("");
  console.log(cyan("  todo") + "                             List all tasks");
  console.log(
    cyan("  todo list") +
      " [--project NAME] [--filter FILTER]"
  );
  console.log("    List tasks, optionally filtered by project or Todoist filter");
  console.log("");
  console.log(
    cyan("  todo add") +
      " <task> [--project NAME] [--priority 1-4] [--due DATE] [--description TEXT]"
  );
  console.log("    Create a new task (priority: 1=urgent, 4=none)");
  console.log("    Due accepts natural language: tomorrow, next friday, every monday");
  console.log("");
  console.log(cyan("  todo done") + " <id> [id2 ...]");
  console.log("    Complete one or more tasks");
  console.log("");
  console.log(cyan("  todo delete") + " <id> [id2 ...]");
  console.log("    Delete one or more tasks");
  console.log("");
  console.log(
    cyan("  todo edit") + " <id> [--content TEXT] [--priority 1-4] [--due DATE]"
  );
  console.log("    Update a task");
  console.log("");
  console.log(cyan("  todo projects"));
  console.log("    List all projects");
  console.log("");
  console.log(bold("Environment:"));
  console.log(
    "  TODOIST_API_TOKEN    API token (or put in ~/.config/todoist/token)"
  );
  console.log("");
}

module.exports = {
  printTasks,
  printTasksFlat,
  printProjects,
  printSuccess,
  printError,
  printHelp,
};
