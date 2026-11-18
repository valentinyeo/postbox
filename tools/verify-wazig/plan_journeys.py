def plan_journeys(files, mapping, journeys, repro=None):
    files = list(files)
    repro = repro if repro and repro != 'none' else None
    needed = bool(repro) or any(
        path.startswith(('src/', 'tools/verify-wazig/'))
        or path in ('build.zig', '.github/workflows/verify.yml')
        for path in files
    )
    names = set(mapping['default']) if needed else set()
    if repro:
        names.add(repro)
    for path in files:
        for prefix, features in mapping['paths'].items():
            if path.startswith(prefix):
                names.update(features)
    if len(names) > mapping['max_journeys']:
        raise ValueError('PR journey limit exceeded; split the change rather than skip coverage')
    if len([row for row in journeys if row['name'] in names]) != len(names):
        raise ValueError('PR journey map contains unknown journeys')
    return names
