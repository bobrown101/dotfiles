// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

const isTTY = process.stdout.isTTY && !process.env.NO_COLOR;
const esc = (code) => (isTTY ? `\x1b[${code}m` : "");
const reset = esc(0);
const bold = (s) => `${esc(1)}${s}${reset}`;
const cyan = (s) => `${esc(36)}${s}${reset}`;
const green = (s) => `${esc(32)}${s}${reset}`;
const yellow = (s) => `${esc(33)}${s}${reset}`;
const gray = (s) => `${esc(90)}${s}${reset}`;

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

function renderHelp(BRANCH_PREFIX) {
  console.log("");
  console.log(bold("ws - parallel multi-repo development with git worktrees"));
  console.log("");
  console.log(
    "Spins up isolated workspaces so you can work on multiple features at once."
  );
  console.log(
    "Each workspace gets its own git worktrees, bend serve (with unique URL),"
  );
  console.log("tmux session, and Claude Code instance.");
  console.log("");
  console.log(bold("Commands:"));
  console.log("");
  console.log(cyan("  ws up <name> <repo[:branch]...>"));
  console.log(
    `    Create or update a workspace. Makes a git worktree for each repo,`
  );
  console.log(
    "    starts bend reactor serve with BEND_WORKTREE=<name>, and launches"
  );
  console.log("    a tmux session with [serve], [shell], and [claude] windows.");
  console.log("");
  console.log(
    `    Repos without :branch default to ${BRANCH_PREFIX}/<name>.`
  );
  console.log(
    "    If the workspace already exists, new repos are added and existing"
  );
  console.log(
    "    repos can have their branch switched (with confirmation)."
  );
  console.log("");
  console.log(cyan("  ws rm <name> <repo...>"));
  console.log(
    "    Remove repos from a workspace. Removes worktrees and restarts serve."
  );
  console.log("");
  console.log(cyan("  ws down <name>"));
  console.log(
    "    Tear down a workspace. Kills the tmux session, removes git worktrees,"
  );
  console.log("    and cleans up ~/workspaces/<name>/. Branches are kept.");
  console.log("");
  console.log(cyan("  ws nuke <name>"));
  console.log("    Like 'down', but also deletes local git branches.");
  console.log(
    "    Prompts for confirmation. Use when you're completely done with a workspace."
  );
  console.log("");
  console.log(cyan("  ws ls"));
  console.log(
    "    List all workspaces and whether their tmux session is running."
  );
  console.log("");
  console.log(cyan("  ws attach <name>"));
  console.log("    Switch to (or attach to) a workspace's tmux session.");
  console.log("");
  console.log(cyan("  ws info <name>"));
  console.log(
    "    Show workspace details: repos, branches, URLs, and helpful commands."
  );
  console.log("");
  console.log(bold("Examples:"));
  console.log("");
  console.log(gray("  # Work on a table refactor across three repos"));
  console.log(
    "  ws up table-refactor crm-index-ui crm-object-table customer-data-table"
  );
  console.log("");
  console.log(gray("  # Use a specific branch for one repo"));
  console.log(
    "  ws up table-refactor crm-index-ui customer-data-table:jsmith/table-fix"
  );
  console.log("");
  console.log(gray("  # Add another repo to an existing workspace"));
  console.log("  ws up table-refactor reporting:jsmith/reporting-fix");
  console.log("");
  console.log(gray("  # Done with the refactor"));
  console.log("  ws down table-refactor");
  console.log("");
  console.log(bold("Layout:"));
  console.log("  Worktrees:  ~/workspaces/<name>/<repo>/");
  console.log("  Serve URL:  https://<name>.local.app.hubspotqa.com");
  console.log("");
}

// ---------------------------------------------------------------------------
// Workspace list
// ---------------------------------------------------------------------------

// workspaces: [{ name, repos: string[], running: boolean }]
function renderLs(workspaces) {
  if (workspaces.length === 0) {
    console.log("No workspaces.");
    return;
  }
  for (const ws of workspaces) {
    if (ws.running) {
      console.log(green(`${ws.name} [running]`));
    } else {
      console.log(yellow(`${ws.name} [stopped]`));
    }
    for (const repo of ws.repos) {
      console.log(`  ${repo}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Workspace info
// ---------------------------------------------------------------------------

// data: { name, root, repos: [{ name, branch, appUrl, testUrls: string[] }] }
function renderInfo(data) {
  console.log("");
  process.stdout.write(
    `${gray("  ── ")}${bold(cyan(data.name))}${gray(" ──────────────────────────────────────────────")}\n`
  );
  console.log("");
  console.log(`${gray("  root   ")}${data.root}`);
  console.log("");

  for (const repo of data.repos) {
    console.log(`${green(`  ${repo.name}`)} ${gray("on")} ${yellow(repo.branch)}`);
    if (repo.appUrl) console.log(gray(`    app   ${repo.appUrl}`));
    for (const t of repo.testUrls) {
      console.log(gray(`    test  ${t}`));
    }
  }
  console.log("");

  console.log(
    gray("  ────────────────────────────────────────────────────")
  );
  console.log("");
  console.log(
    `  ws up ${data.name} ${gray("<repo>            add a repo")}`
  );
  console.log(
    `  ws up ${data.name} ${gray("<repo>:<branch>   add a repo on a specific branch")}`
  );
  console.log(
    `  ws down ${data.name}${gray("                  tear down (keeps branches)")}`
  );
  console.log(
    `  ws nuke ${data.name}${gray("                  tear down + delete branches")}`
  );
  console.log(
    `  ws attach ${data.name}${gray("                rejoin this session")}`
  );
  console.log("");
}

// ---------------------------------------------------------------------------
// Creation / teardown output
// ---------------------------------------------------------------------------

function renderMessages(messages) {
  for (const m of messages) console.log(m);
}

function renderWorkspaceReady(name, repoUrls) {
  console.log("");
  console.log(`Workspace '${name}' ready.`);
  for (const { repo, url } of repoUrls) {
    if (url) console.log(`  ${repo}: ${url}`);
  }
  console.log(`  Tmux: ${name}`);
}

function renderNukePrompt(name, branchInfo) {
  console.log(`About to nuke workspace '${name}':`);
  for (const { repo, branch } of branchInfo) {
    console.log(`  ${repo} (branch: ${branch})`);
  }
}

function renderError(msg) {
  console.error(msg);
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  bold,
  cyan,
  green,
  yellow,
  gray,
  renderHelp,
  renderLs,
  renderInfo,
  renderMessages,
  renderWorkspaceReady,
  renderNukePrompt,
  renderError,
};
