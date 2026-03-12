const api = require("./api");
const model = require("./model");
const view = require("./view");

async function list(flags) {
  const params = {};
  let cachedProjects;

  if (flags.project) {
    cachedProjects = await api.listProjects();
    const id = model.resolveProjectId(
      flags.project,
      cachedProjects.map(model.formatProject)
    );
    if (!id) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    params.project_id = id;
  }

  if (flags.filter) {
    params.filter = flags.filter;
  }

  const completedParams = { limit: 5 };
  if (params.project_id) completedParams.project_id = params.project_id;

  const fetches = [
    api.listTasks(Object.keys(params).length ? params : null),
    api.listCompletedTasks(completedParams),
  ];
  if (!cachedProjects) fetches.push(api.listProjects());

  const results = await Promise.all(fetches);
  const rawTasks = results[0];
  const rawCompleted = results[1];
  const rawProjects = cachedProjects || results[2];

  const tasks = model.sortTasks(rawTasks.map(model.formatTask));
  const completed = rawCompleted.map(model.formatTask);
  const projects = rawProjects.map(model.formatProject);
  const grouped = model.groupTasksByProject(tasks, projects);
  view.printTasks(grouped, completed);
}

async function add(flags) {
  if (!flags.content) {
    view.printError("Usage: todo add \"task\" [--project NAME] [--priority 1-4] [--due DATE]");
    process.exit(1);
  }

  if (flags.project) {
    const projects = await api.listProjects();
    const id = model.resolveProjectId(
      flags.project,
      projects.map(model.formatProject)
    );
    if (!id) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    flags.projectId = id;
  }

  const body = model.buildTaskBody(flags);
  const task = await api.createTask(body);
  view.printSuccess(`Created: ${task.content} (${task.id})`);
}

async function done(args) {
  if (args.length === 0) {
    view.printError("Usage: todo done <id> [id2 ...]");
    process.exit(1);
  }
  for (const id of args) {
    const task = await api.getTask(id);
    await api.closeTask(id);
    view.printSuccess(`Completed: ${task.content} (${id})`);
  }
}

async function del(args) {
  if (args.length === 0) {
    view.printError("Usage: todo delete <id> [id2 ...]");
    process.exit(1);
  }
  for (const id of args) {
    const task = await api.getTask(id);
    await api.deleteTask(id);
    view.printSuccess(`Deleted: ${task.content} (${id})`);
  }
}

async function edit(args, flags) {
  const id = args[0];
  if (!id) {
    view.printError("Usage: todo edit <id> [--content TEXT] [--priority 1-4] [--due DATE]");
    process.exit(1);
  }

  const body = model.buildTaskBody(flags);

  if (Object.keys(body).length === 0) {
    view.printError("Nothing to update. Use --content, --priority, --due, or --description.");
    process.exit(1);
  }

  const task = await api.updateTask(id, body);
  view.printSuccess(`Updated: ${task.content} (${task.id})`);
}

async function projects() {
  const rawProjects = await api.listProjects();
  const formatted = rawProjects.map(model.formatProject);
  formatted.sort((a, b) => a.order - b.order);
  view.printProjects(formatted);
}

module.exports = { list, add, done, del, edit, projects };
