#!/usr/bin/env python3
"""Fail builds if platform UI or native playback dependencies cross targets."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project = root / "Cinerama.xcodeproj/project.pbxproj"
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


mac = files("Cinerama-macOS", "PBXSourcesBuildPhase")
tv = files("Cinerama-tvOS", "PBXSourcesBuildPhase")
mac_resources = files("Cinerama-macOS", "PBXResourcesBuildPhase")
tv_resources = files("Cinerama-tvOS", "PBXResourcesBuildPhase")
# Data-only Home models/helpers are shared explicitly. Mac views and Mac route
# adapters are deliberately absent from this allowlist.
allowed_tv_shared = {
    "Cinerama/Sources/Shared/AppImageCache.swift", "Cinerama/Sources/Shared/String+NilIfEmpty.swift",
    "Cinerama/Sources/Features/Home/HomeViewModel.swift",
    "Cinerama/Sources/Features/Home/HomeHubItemsViewModel.swift",
    "Cinerama/Sources/Features/Home/HomeRecommendationEngine.swift",
    "Cinerama/Sources/Features/Home/HomePersonalizedShelf.swift",
    "Cinerama/Sources/Features/Home/HomeHubFilter.swift",
    "Cinerama/Sources/Features/Home/HomeHubArrangement.swift",
    "Cinerama/Sources/Features/Home/HomeFirstPaintGate.swift",
    "Cinerama/Sources/Features/Libraries/LibraryGenreSupport.swift",
    "Cinerama/Sources/Features/Libraries/LibraryItemsViewModel.swift",
    "Cinerama/Sources/Features/Libraries/LibraryUnwatchedFilter.swift",
    "Cinerama/Sources/Shared/RecommendationCore.swift",
    "Cinerama/Sources/Shared/MediaFormatting.swift",
    "Cinerama/Sources/Shared/PlexItemPresentation.swift",
    "Cinerama/Sources/Shared/PlexService+WatchedFanOut.swift",
}
violations = [f"Mac includes TV input: {path}" for path in mac | mac_resources if path.startswith("CineramaTV/")]
violations += [f"TV includes Mac UI/engine input: {path}" for path in tv
               if not (path.startswith(("CineramaTV/Sources/", "Cinerama/Sources/Models/", "Cinerama/Sources/PlexService/"))
                       or path in allowed_tv_shared)]
violations += [f"TV includes Mac resources: {path}" for path in tv_resources if path.startswith("Cinerama/")]
violations += [f"TV links desktop dependency: {path}" for path in files("Cinerama-tvOS", "PBXFrameworksBuildPhase")
               if Path(path).name in {"VLCKit.xcframework", "CineramaDovi.xcframework"}]
if violations:
    raise SystemExit("Platform source boundaries failed:\n" + "\n".join(violations))
print(f"Platform boundaries verified: {len(mac)} Mac sources, {len(tv)} TV/shared sources.")
