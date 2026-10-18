#!/usr/bin/env python3
"""Fail builds if platform UI or native playback dependencies cross targets."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project = root / "Dusk.xcodeproj/project.pbxproj"
data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = data["objects"]
paths = {}


def visit(identifier, parent=Path()):
    value = objects[identifier]
    path = parent / value.get("path", "")
    if value.get("isa") == "PBXFileReference":
        paths[identifier] = path.as_posix()
    for child in value.get("children", []):
        visit(child, path)


visit(objects[data["rootObject"]]["mainGroup"])
targets = {value["name"]: value for value in objects.values() if value.get("isa") == "PBXNativeTarget"}


def files(target, phase_kind):
    result = set()
    for identifier in targets[target]["buildPhases"]:
        phase = objects[identifier]
        if phase["isa"] == phase_kind:
            for entry in phase.get("files", []):
                reference = objects[entry].get("fileRef")
                if reference:
                    result.add(paths[reference])
    return result


mac = files("Dusk-macOS", "PBXSourcesBuildPhase")
tv = files("Dusk-tvOS", "PBXSourcesBuildPhase")
mac_resources = files("Dusk-macOS", "PBXResourcesBuildPhase")
tv_resources = files("Dusk-tvOS", "PBXResourcesBuildPhase")
# Data-only Home models/helpers are shared explicitly. Mac views and Mac route
# adapters are deliberately absent from this allowlist.
allowed_tv_shared = {
    "Dusk/Sources/Shared/AppImageCache.swift", "Dusk/Sources/Shared/String+NilIfEmpty.swift",
    "Dusk/Sources/Features/Home/HomeViewModel.swift",
    "Dusk/Sources/Features/Home/HomeHubItemsViewModel.swift",
    "Dusk/Sources/Features/Home/HomeRecommendationEngine.swift",
    "Dusk/Sources/Features/Home/HomePersonalizedShelf.swift",
    "Dusk/Sources/Features/Home/HomeHubFilter.swift",
    "Dusk/Sources/Features/Home/HomeHubArrangement.swift",
    "Dusk/Sources/Features/Home/HomeFirstPaintGate.swift",
    "Dusk/Sources/Features/Libraries/LibraryGenreSupport.swift",
    "Dusk/Sources/Features/Libraries/LibraryItemsViewModel.swift",
    "Dusk/Sources/Features/Libraries/LibraryUnwatchedFilter.swift",
    "Dusk/Sources/Shared/RecommendationCore.swift",
    "Dusk/Sources/Shared/MediaFormatting.swift",
    "Dusk/Sources/Shared/PlexItemPresentation.swift",
    "Dusk/Sources/Shared/PlexService+WatchedFanOut.swift",
}
violations = [f"Mac includes TV input: {path}" for path in mac | mac_resources if path.startswith("DuskTV/")]
violations += [f"TV includes Mac UI/engine input: {path}" for path in tv
               if not (path.startswith(("DuskTV/Sources/", "Dusk/Sources/Models/", "Dusk/Sources/PlexService/"))
                       or path in allowed_tv_shared)]
violations += [f"TV includes Mac resources: {path}" for path in tv_resources if path.startswith("Dusk/")]
violations += [f"TV links desktop dependency: {path}" for path in files("Dusk-tvOS", "PBXFrameworksBuildPhase")
               if Path(path).name in {"VLCKit.xcframework", "DuskDovi.xcframework"}]
if violations:
    raise SystemExit("Platform source boundaries failed:\n" + "\n".join(violations))
print(f"Platform boundaries verified: {len(mac)} Mac sources, {len(tv)} TV/shared sources.")
