def plan_journeys(files, mapping, journeys):
    files = list(files)
    needed = any(
        path.startswith(('src/', 'tools/verify-wazig/'))
        or path in ('build.zig', '.github/workflows/verify.yml')
        for path in files
    )
    names = set(mapping['default']) if needed else set()
    for path in files:
        for prefix, features in mapping['paths'].items():
            if path.startswith(prefix):
                names.update(features)
    if len(names) > mapping['max_journeys']:
        raise ValueError('PR journey limit exceeded; split the change rather than skip coverage')
    if len([row for row in journeys if row['name'] in names]) != len(names):
        raise ValueError('PR journey map contains unknown journeys')
    return names
