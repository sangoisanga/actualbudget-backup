module.exports = function minimist(args) {
  const parsed = {};

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (!arg.startsWith('--')) {
      continue;
    }

    const raw = arg.slice(2);
    const equalsIndex = raw.indexOf('=');

    if (equalsIndex >= 0) {
      parsed[raw.slice(0, equalsIndex)] = raw.slice(equalsIndex + 1);
      continue;
    }

    const next = args[i + 1];
    if (next && !next.startsWith('--')) {
      parsed[raw] = next;
      i++;
    } else {
      parsed[raw] = true;
    }
  }

  return parsed;
};
