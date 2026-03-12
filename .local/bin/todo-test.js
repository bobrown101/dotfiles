#!/usr/bin/env node

const { spawnSync } = require("child_process");
const path = require("path");

const TODO = path.join(__dirname, "todo");

let passed = 0;
let failed = 0;

function assert(ok, msg) {
  if (ok) {
    passed++;
    console.log(`  \x1b[32m\u2713\x1b[0m ${msg}`);
  } else {
    failed++;
    console.log(`  \x1b[31m\u2717\x1b[0m ${msg}`);
  }
}

function todo(...args) {
  const result = spawnSync(process.execPath, [TODO, ...args], {
    encoding: "utf8",
    stdio: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
    timeout: 10000,
  });
  return {
    stdout: result.stdout,
    stderr: result.stderr,
    status: result.status,
    output: result.stdout + result.stderr,
  };
}

function testHelp() {
  console.log("\nhelp");

  const r1 = todo("help");
  assert(r1.status === 0, "help exits 0");
  assert(r1.output.includes("todo - Todoist"), "help shows title");
  assert(r1.output.includes("todo list"), "help lists commands");
  assert(r1.output.includes("todo add"), "help shows add");
  assert(r1.output.includes("todo done"), "help shows done");
  assert(r1.output.includes("todo delete"), "help shows delete");
  assert(r1.output.includes("todo edit"), "help shows edit");
  assert(r1.output.includes("todo projects"), "help shows projects");
  assert(r1.output.includes("TODOIST_API_TOKEN"), "help mentions token env var");

  const r2 = todo("--help");
  assert(r2.status === 0, "--help exits 0");
  assert(r2.output.includes("todo - Todoist"), "--help shows title");

  const r3 = todo("-h");
  assert(r3.status === 0, "-h exits 0");
  assert(r3.output.includes("todo - Todoist"), "-h shows title");
}

function testUnknownCommand() {
  console.log("\nunknown command");

  const r = todo("bogus");
  assert(r.status === 1, "unknown command exits 1");
  assert(r.output.includes("Unknown command: bogus"), "shows unknown command name");
}

function testCompletions() {
  console.log("\ncompletions");

  const r = todo("--completions");
  assert(r.status === 0, "completions with no subcommand exits 0");
  assert(r.output.includes("list"), "completions includes list");
  assert(r.output.includes("add"), "completions includes add");
  assert(r.output.includes("done"), "completions includes done");
  assert(r.output.includes("delete"), "completions includes delete");
  assert(r.output.includes("projects"), "completions includes projects");
  assert(r.output.includes("help"), "completions includes help");
}

function testCompletionsFlags() {
  console.log("\ncompletions flags");

  const r1 = todo("--completions", "list");
  assert(r1.output.includes("--project"), "list completions include --project");
  assert(r1.output.includes("--filter"), "list completions include --filter");

  const r2 = todo("--completions", "add");
  assert(r2.output.includes("--project"), "add completions include --project");
  assert(r2.output.includes("--priority"), "add completions include --priority");
  assert(r2.output.includes("--due"), "add completions include --due");
  assert(r2.output.includes("--description"), "add completions include --description");
}

function testAddNoContent() {
  console.log("\nadd with no content");

  const r = todo("add");
  assert(r.status === 1, "add with no content exits 1");
  assert(r.output.includes("Usage"), "add shows usage");
}

function testDoneNoId() {
  console.log("\ndone with no id");

  const r = todo("done");
  assert(r.status === 1, "done with no id exits 1");
  assert(r.output.includes("Usage"), "done shows usage");
}

function testDeleteNoId() {
  console.log("\ndelete with no id");

  const r = todo("delete");
  assert(r.status === 1, "delete with no id exits 1");
  assert(r.output.includes("Usage"), "delete shows usage");
}

function testEditNoId() {
  console.log("\nedit with no id");

  const r = todo("edit");
  assert(r.status === 1, "edit with no id exits 1");
  assert(r.output.includes("Usage"), "edit shows usage");
}

function testNoToken() {
  console.log("\nno token");

  const result = spawnSync(process.execPath, [TODO, "list"], {
    encoding: "utf8",
    stdio: "pipe",
    env: { PATH: process.env.PATH, HOME: "/tmp/todo-test-nonexistent" },
    timeout: 10000,
  });
  const output = result.stdout + result.stderr;
  assert(result.status === 1, "list with no token exits 1");
  assert(output.includes("token") || output.includes("Token"), "shows token error");
}

function testModelPureFunctions() {
  console.log("\nmodel pure functions");

  const model = require("./todo-lib/model");

  const task = model.formatTask({
    id: "123",
    content: "Test task",
    description: "desc",
    priority: 3,
    project_id: "456",
    due: { date: "2025-01-15", string: "Jan 15" },
    order: 1,
    url: "https://todoist.com/task/123",
  });
  assert(task.id === "123", "formatTask preserves id");
  assert(task.content === "Test task", "formatTask preserves content");
  assert(task.due === "2025-01-15", "formatTask flattens due date");
  assert(task.projectId === "456", "formatTask maps project_id");

  const taskNoDue = model.formatTask({
    id: "124",
    content: "No due",
    priority: 1,
    project_id: "456",
    due: null,
    order: 2,
  });
  assert(taskNoDue.due === null, "formatTask handles null due");

  const project = model.formatProject({
    id: "456",
    name: "Work",
    color: "red",
    order: 1,
    is_favorite: true,
  });
  assert(project.id === "456", "formatProject preserves id");
  assert(project.name === "Work", "formatProject preserves name");
  assert(project.isFavorite === true, "formatProject maps is_favorite");

  const sorted = model.sortTasks([
    { priority: 1, due: "2025-02-01", order: 1 },
    { priority: 4, due: null, order: 2 },
    { priority: 1, due: "2025-01-01", order: 3 },
  ]);
  assert(sorted[0].priority === 4, "sortTasks: highest priority first");
  assert(sorted[1].due === "2025-01-01", "sortTasks: earlier due second");
  assert(sorted[2].due === "2025-02-01", "sortTasks: later due third");

  const grouped = model.groupTasksByProject(
    [
      { projectId: "1", content: "a" },
      { projectId: "2", content: "b" },
      { projectId: "1", content: "c" },
    ],
    [
      { id: "1", name: "Work" },
      { id: "2", name: "Personal" },
    ]
  );
  assert(grouped["Work"].length === 2, "groupTasksByProject: groups correctly");
  assert(grouped["Personal"].length === 1, "groupTasksByProject: second group");

  const id = model.resolveProjectId("work", [
    { id: "1", name: "Work" },
    { id: "2", name: "Personal" },
  ]);
  assert(id === "1", "resolveProjectId: case insensitive match");

  const partialId = model.resolveProjectId("pers", [
    { id: "1", name: "Work" },
    { id: "2", name: "Personal" },
  ]);
  assert(partialId === "2", "resolveProjectId: partial match");

  const noMatch = model.resolveProjectId("nope", [
    { id: "1", name: "Work" },
  ]);
  assert(noMatch === null, "resolveProjectId: returns null on no match");

  const body = model.buildTaskBody({
    content: "Test",
    priority: "1",
    due: "tomorrow",
    projectId: "456",
  });
  assert(body.content === "Test", "buildTaskBody: content");
  assert(body.priority === 4, "buildTaskBody: user p1 maps to API p4 (urgent)");
  assert(body.due_string === "tomorrow", "buildTaskBody: due mapped to due_string");
  assert(body.project_id === "456", "buildTaskBody: project_id");

  const body2 = model.buildTaskBody({ content: "Low", priority: "4" });
  assert(body2.priority === 1, "buildTaskBody: user p4 maps to API p1 (none)");
}

console.log("todo tests");

testHelp();
testUnknownCommand();
testCompletions();
testCompletionsFlags();
testAddNoContent();
testDoneNoId();
testDeleteNoId();
testEditNoId();
testNoToken();
testModelPureFunctions();

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
