const fs = require("fs");
const path = require("path");
const model = require("./model");
const view = require("./view");

// ---------------------------------------------------------------------------
// help
// ---------------------------------------------------------------------------

function cmdHelp() {
  view.renderHelp(model.BRANCH_PREFIX);
}

// ---------------------------------------------------------------------------
// ls
// ---------------------------------------------------------------------------

function cmdLs() {
  const names = model.allWorkspaces();
  const workspaces = names.map((name) => ({
    name,
    repos: model.getRepos(path.join(model.WS_DIR, name)),
    running: model.tmuxHasSession(name),
  }));
  view.renderLs(workspaces);
}

// ---------------------------------------------------------------------------
// info
// ---------------------------------------------------------------------------

function cmdInfo(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws info <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);
  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const repos = model.getRepos(wsRoot);
  const branch = `${model.BRANCH_PREFIX}/${name}`;
  const appBase = `https://${name}.local.app.hubspotqa.com`;
  const testBase = `https://${name}.local.hsappstatic.net`;

  view.renderInfo({
    name,
    root: wsRoot,
    branch,
    repos: repos.map((repo) => ({
      name: repo,
      appUrl: model.appUrl(repo, appBase),
      testUrls: model.testUrls(repo, testBase),
    })),
  });
}

// ---------------------------------------------------------------------------
// attach
// ---------------------------------------------------------------------------

function cmdAttach(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws attach <name>");
    process.exit(1);
  }
  const name = args[0];
  if (!model.tmuxHasSession(name)) {
    view.renderError(`No tmux session for workspace '${name}'`);
    process.exit(1);
  }
  model.tmuxAttachOrSwitch(name);
}

// ---------------------------------------------------------------------------
// down
// ---------------------------------------------------------------------------

function cmdDown(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws down <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const messages = model.teardownWorkspace(name, wsRoot);
  view.renderMessages(messages);
  console.log(`Workspace '${name}' torn down.`);
}

// ---------------------------------------------------------------------------
// nuke
// ---------------------------------------------------------------------------

function cmdNuke(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws nuke <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const branchInfo = model.gatherBranchInfo(wsRoot);
  view.renderNukePrompt(name, branchInfo);

  const readline = require("readline");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  rl.question(`Nuke workspace '${name}'? [y/N] `, (answer) => {
    rl.close();
    if (answer.trim().toLowerCase() !== "y") {
      console.log("Aborted.");
      process.exit(0);
    }

    const messages = model.teardownWorkspace(name, wsRoot);
    view.renderMessages(messages);

    for (const { repoDir, branch, repo } of branchInfo) {
      const result = model.deleteBranch(repoDir, branch);
      if (result.success) {
        console.log(`Deleted branch: ${branch} (${repo})`);
      } else {
        console.log(`Could not delete branch: ${branch} (${repo})`);
      }
    }

    console.log(`Workspace '${name}' nuked.`);
  });
}

// ---------------------------------------------------------------------------
// up
// ---------------------------------------------------------------------------

function cmdUp(args) {
  if (args.length < 2) {
    view.renderError("Usage: ws up <name> <repo...>");
    process.exit(1);
  }

  const name = args[0];
  const repos = args.slice(1);
  const wsRoot = path.join(model.WS_DIR, name);
  const branch = `${model.BRANCH_PREFIX}/${name}`;

  if (model.tmuxHasSession(name)) {
    view.renderError(
      `Workspace '${name}' already exists. Use 'ws attach ${name}' or 'ws down ${name}' first.`
    );
    process.exit(1);
  }

  console.log(`Creating workspace: ${name}`);
  fs.mkdirSync(wsRoot, { recursive: true });

  for (const repo of repos) {
    const repoDir = path.join(model.SRC, repo);
    if (!fs.existsSync(repoDir)) {
      view.renderError(`  Error: repo not found at ${repoDir}`);
      process.exit(1);
    }
    const wtPath = path.join(wsRoot, repo);
    if (fs.existsSync(wtPath)) {
      console.log(`  Exists: ${repo}`);
      continue;
    }
    const result = model.createWorktree(repoDir, wtPath, branch);
    if (result) {
      console.log(`  Created: ${repo} (${result.status} branch ${result.branch})`);
    } else {
      view.renderError(`  Error: could not create worktree for ${repo}`);
      view.renderError(
        `  (branch '${branch}' may already be checked out elsewhere)`
      );
      process.exit(1);
    }
  }

  const serveCmd = model.buildServeCmd(name, wsRoot, repos);
  model.tmuxCreateSession(name, wsRoot, serveCmd);

  const base = `https://${name}.local.app.hubspotqa.com`;
  const repoUrls = repos.map((repo) => ({
    repo,
    url: model.appUrl(repo, base),
  }));
  view.renderWorkspaceReady(name, repoUrls);

  model.tmuxAttachOrSwitch(name);
}

// ---------------------------------------------------------------------------
// add
// ---------------------------------------------------------------------------

function cmdAdd(args) {
  if (args.length < 2) {
    view.renderError("Usage: ws add <name> <repo...> [--branch <branch>]");
    process.exit(1);
  }

  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);
  let branch = `${model.BRANCH_PREFIX}/${name}`;
  const repos = [];

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--branch") {
      i++;
      if (i >= args.length) {
        view.renderError("Error: --branch requires a value");
        process.exit(1);
      }
      branch = args[i];
    } else {
      repos.push(args[i]);
    }
  }

  if (repos.length === 0) {
    view.renderError("Usage: ws add <name> <repo...> [--branch <branch>]");
    process.exit(1);
  }

  const added = [];
  for (const repo of repos) {
    const repoDir = path.join(model.SRC, repo);
    if (!fs.existsSync(repoDir)) {
      view.renderError(`  Error: repo not found at ${repoDir}`);
      process.exit(1);
    }
    const wtPath = path.join(wsRoot, repo);
    if (fs.existsSync(wtPath)) {
      console.log(`  Exists: ${repo} (already in workspace)`);
      continue;
    }
    const result = model.createWorktree(repoDir, wtPath, branch);
    if (result) {
      console.log(`  Created: ${repo} (${result.status} branch ${result.branch})`);
      added.push(repo);
    } else {
      view.renderError(`  Error: could not create worktree for ${repo}`);
      view.renderError(
        `  (branch '${branch}' may already be checked out elsewhere)`
      );
      process.exit(1);
    }
  }

  if (added.length === 0) {
    console.log("No repos added.");
    return;
  }

  model.restartServe(name, wsRoot);

  console.log("");
  console.log(`Added to '${name}': ${added.join(", ")}`);
  const base = `https://${name}.local.app.hubspotqa.com`;
  for (const repo of added) {
    const url = model.appUrl(repo, base);
    if (url) console.log(`  ${repo}: ${url}`);
  }
}

// ---------------------------------------------------------------------------
// rm
// ---------------------------------------------------------------------------

function cmdRm(args) {
  if (args.length < 2) {
    view.renderError("Usage: ws rm <name> <repo...>");
    process.exit(1);
  }

  const name = args[0];
  const repos = args.slice(1);
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const removed = [];
  for (const repo of repos) {
    const wtPath = path.join(wsRoot, repo);
    if (!fs.existsSync(wtPath)) {
      console.log(`  Not found: ${repo} (not in workspace)`);
      continue;
    }
    const gitFile = path.join(wtPath, ".git");
    if (!fs.existsSync(gitFile) || fs.statSync(gitFile).isDirectory()) {
      console.log(`  Skipped: ${repo} (not a worktree)`);
      continue;
    }
    const result = model.removeWorktree(wtPath);
    if (result.status === "removed") {
      console.log(`  Removed: ${repo}`);
      removed.push(repo);
    } else {
      console.log(`  Error: ${result.detail} for ${repo}`);
    }
  }

  if (removed.length === 0) {
    console.log("No repos removed.");
    return;
  }

  model.restartServe(name, wsRoot);

  console.log("");
  console.log(`Removed from '${name}': ${removed.join(", ")}`);
}

// ---------------------------------------------------------------------------
// completions
// ---------------------------------------------------------------------------

function cmdCompletions(args) {
  const subcommand = args[0];
  const rest = args.slice(1);

  const SUBCOMMANDS = [
    "up\tCreate a workspace",
    "down\tTear down a workspace",
    "nuke\tNuke a workspace (delete everything)",
    "add\tAdd repos to a workspace",
    "rm\tRemove repos from a workspace",
    "ls\tList all workspaces",
    "attach\tAttach to a workspace tmux session",
    "info\tShow workspace details",
    "help\tShow help",
  ];

  if (!subcommand) {
    SUBCOMMANDS.forEach((s) => console.log(s));
    return;
  }

  const workspaces = model.allWorkspaces();
  const srcRepos = model.getSrcRepos();

  switch (subcommand) {
    case "up":
      srcRepos.forEach((r) => console.log(r));
      break;
    case "down":
    case "nuke":
    case "attach":
    case "info":
      workspaces.forEach((w) => console.log(w));
      break;
    case "add":
      if (rest.length === 0) {
        workspaces.forEach((w) => console.log(w));
      } else {
        srcRepos.forEach((r) => console.log(r));
      }
      break;
    case "rm": {
      if (rest.length === 0) {
        workspaces.forEach((w) => console.log(w));
      } else {
        const wsName = rest[0];
        const wsPath = path.join(model.WS_DIR, wsName);
        model.getRepos(wsPath).forEach((r) => console.log(r));
      }
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  help: cmdHelp,
  ls: cmdLs,
  info: cmdInfo,
  attach: cmdAttach,
  down: cmdDown,
  nuke: cmdNuke,
  up: cmdUp,
  add: cmdAdd,
  rm: cmdRm,
  completions: cmdCompletions,
};
