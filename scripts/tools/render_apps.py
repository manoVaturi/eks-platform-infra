#!/usr/bin/env python3
"""Render every Argo CD Application of the gitops repo with helm, one file per Application.

Used to prove that a refactor changed no manifest: run it before and after, then `diff -r BEFORE AFTER`.
No cluster is needed: the Applications are read offline (kubectl patch --local, which works offline) and rendered with helm.

Usage: render_apps.py GITOPS_DIR OUT_DIR
"""
import itertools
import json
import pathlib
import re
import subprocess
import sys


def repo_alias(url):
    return "snap-" + re.sub(r"[^a-z0-9]+", "-", url.lower().replace("https://", "")).strip("-")


def apps_dir(gitops):
    """The folder the root Application reads: argocd/ in the config-driven layout, apps/ in the older one."""
    return gitops / "argocd" if (gitops / "argocd").is_dir() else gitops / "apps"


def add_repos(gitops):
    """Add every Helm repository the Applications use, under its own alias, and refresh only those."""
    urls = set()
    for path in apps_dir(gitops).rglob("*.yaml"):
        for match in re.finditer(r"repoURL:\s*(https://\S+)", path.read_text(encoding="utf-8")):
            if not match.group(1).endswith(".git"):
                urls.add(match.group(1))
    aliases = []
    for url in sorted(urls):
        run(["helm", "repo", "add", repo_alias(url), url, "--force-update"])
        aliases.append(repo_alias(url))
    run(["helm", "repo", "update", *aliases])


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def read_objects(path):
    """The objects of a YAML file, read offline by kubectl (no PyYAML needed)."""
    r = run(["kubectl", "patch", "--local", "-f", str(path), "--type", "merge", "-p", "{}", "-o", "json"])
    if r.returncode != 0:
        return []
    data = json.loads(r.stdout)
    return data["items"] if data.get("kind") == "List" else [data]


def read_flat_yaml(path):
    """A config.yaml of plain `key: value` lines (comments allowed), the shape the git files generator reads here."""
    params = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^([A-Za-z_]\w*):\s*(.*?)\s*(?:#.*)?$", line)
        if match:
            params[match.group(1)] = match.group(2).strip("'\"")
    return params


def generator_lists(gen, gitops):
    """The parameter sets of one generator: a list, a git files generator, or a matrix of those."""
    if "list" in gen:
        return [gen["list"]["elements"]]
    if "git" in gen:
        files = []
        for entry in gen["git"]["files"]:
            files += sorted(gitops.glob(entry["path"]))
        return [[read_flat_yaml(f) for f in files]]
    return [generator_lists(sub, gitops)[0] for sub in gen.get("matrix", {}).get("generators", [])]


def expand_application_set(obj, gitops):
    """An ApplicationSet with list or git-files generators (alone or in a matrix) becomes the Applications it would generate."""
    lists = []
    for gen in obj["spec"]["generators"]:
        lists += generator_lists(gen, gitops)
    apps = []
    for combo in itertools.product(*lists):
        params = {}
        for item in combo:
            params.update(item)
        text = json.dumps(obj["spec"]["template"])
        # {{key}} (fasttemplate) and {{ .key }} (Go template) both
        text = re.sub(r"\{\{\s*\.?(\w+)\s*\}\}", lambda m: str(params.get(m.group(1), m.group(0))), text)
        tpl = json.loads(text)
        apps.append({"metadata": tpl["metadata"], "spec": tpl["spec"]})
    return apps


def render(app, gitops, out):
    name = app["metadata"]["name"]
    spec = app["spec"]
    namespace = spec["destination"].get("namespace", "default")
    sources = spec.get("sources") or [spec["source"]]
    values_root = None
    chart_src = None
    for src in sources:
        if "ref" in src:
            values_root = gitops
        else:
            chart_src = src
    helm = chart_src.get("helm", {})
    args = ["helm", "template", helm.get("releaseName", name), "", "-n", namespace, "--include-crds"]
    if "chart" in chart_src:  # a chart from a Helm repository (added under a "snap-" alias by add_repos)
        args[3] = f"{repo_alias(chart_src['repoURL'])}/{chart_src['chart']}"
        args += ["--version", str(chart_src["targetRevision"])]
        base = None
    else:  # a chart inside the gitops repo
        base = gitops / chart_src["path"]
        args[3] = str(base)
    for value_file in helm.get("valueFiles", []):
        if value_file.startswith("$values/"):
            file = values_root / value_file[len("$values/"):]
        else:
            file = (base or gitops) / value_file
        if helm.get("ignoreMissingValueFiles") and not file.is_file():
            continue
        args += ["-f", str(file)]
    for param in helm.get("parameters", []):
        args += ["--set", f"{param['name']}={param['value']}"]
    result = run(args)
    body = result.stdout if result.returncode == 0 else f"# helm failed: {result.stderr.strip()}\n"
    # the folder of the gitops checkout must not appear in the output
    body = body.replace(str(gitops), "<gitops>")
    # certificates that a chart generates differently on every render are not a difference
    body = re.sub(r"^(\s*(?:ca\.crt|tls\.crt|tls\.key|caBundle):\s*).*$", r"\1<generated>", body, flags=re.M)
    (out / f"{name}.yaml").write_text(body, encoding="utf-8", newline="\n")
    return name, result.returncode


def main():
    gitops = pathlib.Path(sys.argv[1]).resolve()
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    add_repos(gitops)
    count, failed = 0, []
    for path in sorted(apps_dir(gitops).rglob("*.yaml")):
        if "projects" in path.parts:
            continue
        for obj in read_objects(path):
            apps = expand_application_set(obj, gitops) if obj.get("kind") == "ApplicationSet" else (
                [obj] if obj.get("kind") == "Application" else [])
            for app in apps:
                name, code = render(app, gitops, out)
                count += 1
                if code != 0:
                    failed.append(name)
    print(f"rendered {count} Applications into {out}" + (f"; helm failed for: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
