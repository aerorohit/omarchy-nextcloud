import json
import os
import re
import shutil
import stat
import subprocess
import sys
import heapq
import time
from pathlib import Path


MAX_CFG_BYTES = 64 * 1024
MAX_LOG_BYTES = 128 * 1024
MAX_SUBPROCESS_BYTES = 32 * 1024
MAX_SCAN_DEPTH = 10
MAX_FILES_SCANNED = 10000
SCAN_DEADLINE_SEC = 5.0
MAX_RESPONSE_BYTES = 256 * 1024


def read_nextcloud_cfg():
  cfg_path = Path.home() / ".config" / "Nextcloud" / "nextcloud.cfg"
  if not cfg_path.exists():
    return {}
  try:
    cfg = {}
    with cfg_path.open("r", encoding="utf-8") as f:
      data = f.read(MAX_CFG_BYTES)
      current_section = None
      for line in data.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
          current_section = line[1:-1]
          cfg[current_section] = {}
        elif "=" in line and current_section:
          key, value = line.split("=", 1)
          cfg[current_section][key.strip()] = value.strip()
    return cfg
  except (OSError, Exception):
    return {}


def get_accounts(cfg):
  accounts = []
  accounts_section = cfg.get("Accounts", {})
  if not accounts_section:
    return accounts
  
  account_ids = set()
  for key in accounts_section.keys():
    match = re.match(r"^(\d+)\\", key)
    if match:
      account_ids.add(match.group(1))
  
  for aid in sorted(account_ids):
    prefix = f"{aid}\\"
    url = ""
    display_name = ""
    dav_user = ""
    folders = []
    
    folder_prefix = f"{prefix}Folders\\"
    folder_keys = [k for k in accounts_section.keys() if k.startswith(folder_prefix) and k.endswith("\\localPath")]
    
    for fk in folder_keys:
      local_path = accounts_section.get(fk, "")
      folder_num = fk.replace(folder_prefix, "").replace("\\localPath", "")
      paused_key = f"{prefix}Folders\\{folder_num}\\paused"
      target_key = f"{prefix}Folders\\{folder_num}\\targetPath"
      paused = accounts_section.get(paused_key, "false").lower() == "true"
      target_path = accounts_section.get(target_key, "/")
      if local_path:
        folders.append({
          "localPath": local_path,
          "targetPath": target_path,
          "paused": paused,
        })
    
    url = accounts_section.get(f"{prefix}url", "")
    display_name = accounts_section.get(f"{prefix}displayName", "")
    dav_user = accounts_section.get(f"{prefix}dav_user", "")
    
    accounts.append({
      "url": url,
      "displayName": display_name,
      "davUser": dav_user,
      "folders": folders,
    })
  
  return accounts


def _run_bounded(command, timeout):
  try:
    proc = subprocess.Popen(
      command,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
    )
    try:
      stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
      proc.kill()
      stdout, stderr = proc.communicate()
    out = (stdout + stderr)[:MAX_SUBPROCESS_BYTES].decode("utf-8", errors="ignore").strip()
    return proc.returncode, out
  except (OSError, Exception):
    return 1, ""


def check_nextcloud_running():
  return _run_bounded(["pgrep", "-x", "nextcloud"], 2)[0] == 0


def get_dbus_sync_status():
  returncode, out = _run_bounded([
    "busctl", "--user", "get-property",
    "com.nextcloudgmbh.Nextcloud",
    "/com/nextcloudgmbh/Nextcloud/Folder/0",
    "org.freedesktop.CloudProviders.Account", "Status"
  ], 2)
  if returncode == 0:
    value = out.strip().split()[-1]
    status_map = {
      "1": "syncing",
      "2": "error",
      "3": "paused",
      "4": "offline",
    }
    return status_map.get(value, "unknown")
  return "unknown"


def get_dbus_status_details():
  returncode, out = _run_bounded([
    "busctl", "--user", "get-property",
    "com.nextcloudgmbh.Nextcloud",
    "/com/nextcloudgmbh/Nextcloud/Folder/0",
    "org.freedesktop.CloudProviders.Account", "StatusDetails"
  ], 2)
  if returncode == 0:
    details = out.strip()
    parts = details.split('"')
    if len(parts) >= 2:
      return parts[1]
  return ""


def toggle_sync():
  if not check_nextcloud_running():
    return False
  returncode, _ = _run_bounded([
    "gdbus", "call", "--session",
    "--dest", "com.nextcloudgmbh.Nextcloud",
    "--object-path", "/com/nextcloudgmbh/Nextcloud/Folder/0",
    "--method", "org.gtk.Actions.Activate",
    "pause", "[]", "{}"
  ], 4)
  return returncode == 0


def get_sync_status_from_log():
  log_path = Path.home() / ".local" / "share" / "data" / "Nextcloud" / "Nextcloud_sync.log"
  if not log_path.exists():
    return "Unknown"

  try:
    size = log_path.stat().st_size
    read_size = min(size, MAX_LOG_BYTES)
    with log_path.open("rb") as f:
      if size > read_size:
        f.seek(-read_size, os.SEEK_END)
        f.readline()
      data = f.read(read_size).decode("utf-8", errors="ignore")
    lines = data.strip().split("\n")
    for line in reversed(lines):
      if "Sync state" in line or "status.php" in line.lower() or "sync" in line.lower():
        if "finished" in line.lower() or "complete" in line.lower():
          return "Up to date"
        elif "pause" in line.lower() or "paused" in line.lower():
          return "Paused"
        elif "error" in line.lower() or "fail" in line.lower():
          return "Error"
        elif "sync" in line.lower():
          return "Syncing"
    return "Running"
  except (OSError, Exception):
    return "Unknown"


def _is_safe_path(path):
  try:
    resolved = os.path.realpath(path)
    home = os.path.realpath(Path.home())
    return resolved.startswith(home + os.sep) or resolved == home
  except (OSError, ValueError):
    return False


def scan_folder(path, limit):
  if not _is_safe_path(path):
    return 0, []
  if not os.path.isdir(path):
    return 0, []
  total = 0
  counter = 0
  recent = []
  files_scanned = 0
  base_depth = path.rstrip(os.sep).count(os.sep)
  deadline = time.monotonic() + SCAN_DEADLINE_SEC
  try:
    for root_dir, dirs, files in os.walk(path):
      if time.monotonic() > deadline:
        break
      current_depth = root_dir.count(os.sep) - base_depth
      if current_depth >= MAX_SCAN_DEPTH:
        dirs[:] = []
        continue
      dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root_dir, name))]
      for name in files:
        if files_scanned >= MAX_FILES_SCANNED:
          break
        if time.monotonic() > deadline:
          break
        file_path = os.path.join(root_dir, name)
        if os.path.islink(file_path) or name.startswith("."):
          continue
        try:
          st = os.lstat(file_path)
        except OSError:
          continue
        if not stat.S_ISREG(st.st_mode):
          continue
        total += st.st_size
        rel = os.path.relpath(file_path, path)
        folder = os.path.dirname(rel)
        row = {
          "name": name,
          "path": file_path,
          "folder": "/" if folder in ("", ".") else folder,
          "modifiedTs": int(st.st_mtime),
          "sizeBytes": st.st_size,
        }
        counter += 1
        files_scanned += 1
        entry = (row["modifiedTs"], counter, row)
        if len(recent) < limit:
          heapq.heappush(recent, entry)
        else:
          heapq.heappushpop(recent, entry)
      if files_scanned >= MAX_FILES_SCANNED:
        break
  except OSError:
    return 0, []
  rows = [entry[2] for entry in sorted(recent, reverse=True)]
  return total, rows


def main():
  if len(sys.argv) > 1 and sys.argv[1] == "--toggle":
    if toggle_sync():
      print(json.dumps({"ok": True, "action": "toggled"}))
    else:
      print(json.dumps({"ok": False, "error": "Failed to toggle sync"}))
    return

  limit = 25
  if len(sys.argv) > 1:
    try:
      limit = max(1, min(100, int(sys.argv[1])))
    except ValueError:
      limit = 25

  nextcloud_bin = shutil.which("nextcloud")
  cfg = read_nextcloud_cfg()
  accounts = get_accounts(cfg)
  
  running = check_nextcloud_running() if nextcloud_bin else False
  
  dbus_status = get_dbus_sync_status() if running else "unknown"
  dbus_details = get_dbus_status_details() if running else ""
  
  total_used = 0
  all_files = []
  any_folder_paused = False
  all_folders_paused = True
  
  for account in accounts:
    for folder in account["folders"]:
      local_path = folder["localPath"]
      if folder["paused"] or dbus_status == "paused":
        any_folder_paused = True
      else:
        all_folders_paused = False
      
      if Path(local_path).exists():
        used, files = scan_folder(local_path, limit)
        total_used += used
        all_files.extend(files)
  
  all_files.sort(key=lambda x: x["modifiedTs"], reverse=True)
  files = all_files[:limit]
  
  authenticated = len(accounts) > 0 and any(a["url"] for a in accounts)
  server_url = accounts[0]["url"] if accounts and accounts[0]["url"] else ""
  display_name = accounts[0]["displayName"] if accounts and accounts[0]["displayName"] else ""
  dav_user = accounts[0]["davUser"] if accounts and accounts[0]["davUser"] else ""
  
  if not running:
    status_text = "Not running"
  elif dbus_status == "paused":
    status_text = "Paused"
  elif dbus_status == "error":
    status_text = dbus_details if dbus_details else "Error"
  elif dbus_status == "offline":
    status_text = "Offline"
  elif dbus_status == "syncing":
    status_text = dbus_details if dbus_details else "Syncing"
  elif all_folders_paused:
    status_text = "Paused"
  elif any_folder_paused:
    status_text = "Partially paused"
  else:
    status_text = dbus_details if dbus_details else get_sync_status_from_log()
  
  account_path = accounts[0]["folders"][0]["localPath"] if accounts and accounts[0]["folders"] else ""
  
  quota_bytes = 0
  quota_known = False
  usage_percent = (total_used / quota_bytes * 100) if quota_bytes > 0 else 0

  result = {
    "ok": True,
    "installed": nextcloud_bin is not None,
    "running": running,
    "authenticated": authenticated,
    "statusText": status_text,
    "accountPath": account_path,
    "serverUrl": server_url,
    "displayName": display_name,
    "davUser": dav_user,
    "usedBytes": total_used,
    "quotaBytes": quota_bytes,
    "usagePercent": usage_percent,
    "quotaKnown": quota_known,
    "files": files,
    "dbusStatus": dbus_status,
  }

  output = json.dumps(result)
  if len(output.encode("utf-8")) > MAX_RESPONSE_BYTES:
    while files and len(output.encode("utf-8")) > MAX_RESPONSE_BYTES:
      files = files[:-1]
      result["files"] = files
      output = json.dumps(result)

  print(output)


if __name__ == "__main__":
  main()
